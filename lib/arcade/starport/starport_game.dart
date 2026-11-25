import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show EdgeInsets;

import '../../audio/sfx.dart';
import '../arcade_manager.dart';
import 'starport_art.dart';
import 'starport_generator.dart';
import 'starport_sim.dart';
import 'starport_types.dart';

/// Until `ArcadeGame.starport` (id 'starport') is registered in
/// arcade_manager.dart, rounds are recorded under Thread the Needle's slot
/// (harmless, but register the game).
final ArcadeGame starportArcadeGame = ArcadeGame.values.firstWhere(
  (g) => g.id == 'starport',
  orElse: () => ArcadeGame.threadTheNeedle,
);

/// Angle (radians, 0 = pointing right, clockwise positive in canvas space)
/// of a ship that faces [f].
double facingAngle(Facing f) => switch (f) {
      Facing.right => 0,
      Facing.down => math.pi / 2,
      Facing.left => math.pi,
      Facing.up => -math.pi / 2,
    };

/// A ship that has been launched and is flying from the hangar to its bay.
/// Purely visual. [position]/[angle] are in canvas px.
class FlyingShip {
  final StarShip ship;
  final List<Offset> path; // start, out past the hangar edge, bay center
  final double duration;
  final double endScale; // size at the bay relative to the hangar size
  double t = 0; // seconds elapsed

  FlyingShip(this.ship, this.path, this.duration, this.endScale);

  /// 0..1, eased.
  double get progress {
    final x = (t / duration).clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  bool get done => t >= duration;

  double get scale => 1 + (endScale - 1) * progress;

  Offset get position => _at(progress).$1;

  /// Heading of the current path segment.
  double get angle => _at(progress).$2;

  (Offset, double) _at(double p) {
    var total = 0.0;
    for (var i = 1; i < path.length; i++) {
      total += (path[i] - path[i - 1]).distance;
    }
    var want = total * p;
    for (var i = 1; i < path.length; i++) {
      final seg = (path[i] - path[i - 1]).distance;
      final dir = path[i] - path[i - 1];
      final a = seg == 0 ? 0.0 : math.atan2(dir.dy, dir.dx);
      if (want <= seg || i == path.length - 1) {
        final f = seg == 0 ? 1.0 : (want / seg).clamp(0.0, 1.0);
        return (Offset.lerp(path[i - 1], path[i], f)!, a);
      }
      want -= seg;
    }
    return (path.last, 0);
  }
}

/// A passenger token hopping from the queue front to a bay.
class HopToken {
  final int color;
  final Offset from, to;
  final double duration;
  double t = 0;
  HopToken(this.color, this.from, this.to, this.duration);

  double get progress => (t / duration).clamp(0.0, 1.0);
  bool get done => t >= duration;
}

/// A full ship leaving its bay (whoosh).
class DepartingShip {
  final StarShip ship;
  final Rect bayRect;
  final int bay;
  final double duration;
  double t = 0;
  DepartingShip(this.ship, this.bay, this.bayRect, this.duration);

  double get progress => (t / duration).clamp(0.0, 1.0);
  bool get done => t >= duration;
}

/// What the art shows in a docking bay (lags the sim by the animations).
class VisBay {
  final StarShip ship;
  int filled;

  /// 1 -> 0 over a short time after the ship docks or a passenger boards
  /// (for a little pop).
  double pop = 1;
  VisBay(this.ship, {this.filled = 0});
}

class _Step {
  final double at;
  final void Function() run;
  _Step(this.at, this.run);
}

/// Starport: runs [StarportSim], turns taps into launches, animates what the
/// sim's events say happened (in sequence, without ever blocking input),
/// plays sound and haptics, shows the overlays and records the run. All
/// drawing is in [StarportArt] (starport_art.dart) and all Flutter UI in
/// starport_overlays.dart.
///
/// THE SIM IS AUTHORITATIVE; the game keeps a small "visual mirror"
/// ([visParked], [visBays], [visQueue]) that trails the sim by the running
/// animations and snaps back to it on undo / new level / restart. The art
/// draws the mirror, never the sim directly, so what you see is always a
/// consistent picture, even if the player taps faster than the animations.
///
/// Overlays: [hudOverlay] always on; [readyOverlay] before a run;
/// [clearOverlay] between levels; [overOverlay] after a loss;
/// [pauseOverlay] while paused.
class StarportGame extends FlameGame with TapCallbacks {
  StarportGame({
    this.seed,
    ArcadeGame? arcadeGame,
    StarportLevel Function(int number, int seed)? levelSource,
  })  : arcadeGame = arcadeGame ?? starportArcadeGame,
        sim = StarportSim(
          levelSource: levelSource ?? ((n, s) => generateStarportLevel(n, seed: s)),
          seed: seed,
        ) {
    _snapMirror();
  }

  static const hudOverlay = 'StarportHud';
  static const readyOverlay = 'StarportReady';
  static const clearOverlay = 'StarportClear';
  static const overOverlay = 'StarportOver';
  static const pauseOverlay = 'StarportPause';

  // ── Timings (seconds) ────────────────────────────────────────────────────
  static const double flightTime = 0.30; // hangar -> bay
  static const double hopTime = 0.08; // one passenger queue -> bay
  static const double departTime = 0.35; // whoosh out of the bay
  static const double bumpTime = 0.22; // nudge toward the blocker and back
  static const double flashTime = 0.5; // blocker highlight
  static const double noBayTime = 0.45; // bays pulse
  static const double slideTime = 0.12; // queue closes the gap
  /// "Level cleared" card shows this long before the next level starts
  /// (a tap on it skips the wait).
  static const double clearHold = 1.0;

  /// Seconds between the loss and the results panel.
  static const double overDelay = 1.0;

  /// Height reserved at the top for the HUD (below the safe area).
  static const double hudHeight = 64;

  /// How many queue tokens are drawn.
  static const int queueVisible = 12;

  final int? seed;
  final ArcadeGame arcadeGame;
  final StarportSim sim;
  late StarportArt art;

  // ── Notifiers for the HUD ───────────────────────────────────────────────
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> levelNumber = ValueNotifier(1);
  final ValueNotifier<double> power = ValueNotifier(1);
  final ValueNotifier<int> undosLeft = ValueNotifier(StarportTuning.undosPerLevel);
  final ValueNotifier<StarportPhase> phase = ValueNotifier(StarportPhase.ready);

  /// The finished run's result (set when the results panel opens).
  ArcadeResult? result;

  // ── Layout (canvas px; recomputed on resize and on every new level) ─────
  EdgeInsets _insets = EdgeInsets.zero;
  Rect stationRect = Rect.zero;
  List<Rect> bayRects = const [];
  Rect gateRect = Rect.zero;
  Rect queueRect = Rect.zero; // where the tokens go
  Rect hangarRect = Rect.zero;
  double cellSize = 0;

  /// Diameter of a queue token and the distance between token centers.
  double queueTokenSize = 0;
  double queueStep = 0;

  /// The safe-area insets the HUD sits inside (the screen sets this).
  EdgeInsets get insets => _insets;
  set insets(EdgeInsets v) {
    if (v == _insets) return;
    _insets = v;
    if (laidOut) _layout();
  }

  // ── Visual mirror (what the art draws) ──────────────────────────────────
  List<StarShip> visParked = [];
  List<VisBay?> visBays = [];
  List<int> visQueue = [];
  final List<FlyingShip> flights = [];
  final List<HopToken> hops = [];
  final List<DepartingShip> departures = [];

  /// shipId -> seconds into its bump nudge.
  final Map<int, double> _bumps = {};

  /// blockerId -> seconds of highlight left.
  final Map<int, double> blockerFlash = {};

  /// 1 -> 0 after a "no free bay" tap: the bays pulse.
  double noBayPulse = 0;

  /// 1 -> 0 right after a passenger boards: the queue slides left by
  /// `queueSlide * queueStep`.
  double queueSlide = 0;

  final Map<int, StarShip> _shipsById = {};
  final List<_Step> _timeline = [];
  double _clock = 0;
  double _cursor = 0; // when the last scheduled step is done

  bool _clearPending = false;
  bool _clearShown = false;
  double _clearAt = 0;
  double? _overAt;
  bool _overShown = false;
  bool _lowPowerWarned = false;

  bool laidOut = false;

  bool get isOver => _overShown;

  /// True while any launch/boarding/departure animation is still running.
  bool get busy => _timeline.isNotEmpty || flights.isNotEmpty || hops.isNotEmpty;

  @override
  Future<void> onLoad() async {
    art = StarportArt(this);
    add(art);
    _layout();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) _layout();
  }

  // ── Geometry helpers for the art and tests ──────────────────────────────

  Rect cellRect(int col, int row) =>
      Rect.fromLTWH(hangarRect.left + col * cellSize, hangarRect.top + row * cellSize, cellSize, cellSize);

  Offset cellCenter(int col, int row) => cellRect(col, row).center;

  /// The rectangle covering all of [s]'s cells in the hangar.
  Rect shipRect(StarShip s) {
    final cs = s.cells;
    return cellRect(cs.first.$1, cs.first.$2).expandToInclude(cellRect(cs.last.$1, cs.last.$2));
  }

  /// Center of queue token [i] (0 = front) in the gate, before the slide.
  Offset queueTokenCenter(int i) =>
      Offset(queueRect.left + queueStep * (i + 0.5), queueRect.center.dy);

  /// A parked ship's nudge offset right now (zero when not bumping).
  Offset bumpOffset(StarShip s) {
    final t = _bumps[s.id];
    if (t == null) return Offset.zero;
    final k = math.sin(math.pi * (t / bumpTime).clamp(0.0, 1.0));
    final d = cellSize * 0.22 * k;
    return Offset(s.facing.dc * d, s.facing.dr * d);
  }

  /// Seconds of highlight left for a blocking ship, as 0..1.
  double blockerGlow(int shipId) => ((blockerFlash[shipId] ?? 0) / flashTime).clamp(0.0, 1.0);

  /// The passengers not drawn as tokens ("+N").
  int get queueOverflow => math.max(0, visQueue.length - queueVisible);

  /// The ship under a canvas point, or null.
  StarShip? shipAt(Offset p) {
    if (!hangarRect.contains(p) || cellSize <= 0) return null;
    final c = ((p.dx - hangarRect.left) / cellSize).floor();
    final r = ((p.dy - hangarRect.top) / cellSize).floor();
    for (final s in sim.parked) {
      for (final cell in s.cells) {
        if (cell.$1 == c && cell.$2 == r) return s;
      }
    }
    return null;
  }

  void _layout() {
    final w = size.x, h = size.y;
    if (w <= 0 || h <= 0) return;
    final lv = sim.level;
    const side = 12.0, gap = 8.0, pad = 8.0;
    final top = _insets.top + hudHeight;
    final bottom = h - _insets.bottom - 12;

    // Station strip with the bays.
    final n = math.max(1, lv.bays);
    final bayW = (w - 2 * side - 2 * pad - gap * (n - 1)) / n;
    final bayH = bayW.clamp(56.0, 84.0).toDouble();
    stationRect = Rect.fromLTWH(side, top, w - 2 * side, bayH + 2 * pad);
    bayRects = [
      for (var i = 0; i < n; i++)
        Rect.fromLTWH(side + pad + i * (bayW + gap), stationRect.top + pad, bayW, bayH),
    ];

    // Gate with the passenger queue.
    gateRect = Rect.fromLTWH(side, stationRect.bottom + 8, w - 2 * side, 56);
    queueRect = Rect.fromLTRB(gateRect.left + 36, gateRect.top + 8, gateRect.right - 52, gateRect.bottom - 8);
    queueStep = queueRect.width / queueVisible;
    queueTokenSize = math.min(queueRect.height, queueStep * 1.1);

    // Hangar fills the rest, square cells, centered.
    final availTop = gateRect.bottom + 12;
    final availW = w - 2 * side;
    final availH = math.max(1.0, bottom - availTop);
    cellSize = math.min(availW / lv.cols, availH / lv.rows);
    final hw = cellSize * lv.cols, hh = cellSize * lv.rows;
    hangarRect = Rect.fromLTWH(side + (availW - hw) / 2, availTop + (availH - hh) / 2, hw, hh);
    laidOut = true;
  }

  // ── Mirror ──────────────────────────────────────────────────────────────

  /// Copies the sim's state into the mirror and drops every running
  /// animation (undo, new level, restart).
  void _snapMirror() {
    final lv = sim.level;
    _shipsById
      ..clear()
      ..addEntries(lv.ships.map((s) => MapEntry(s.id, s)));
    visParked = List.of(sim.parked);
    visBays = [
      for (final b in sim.bays)
        if (b == null) null else (VisBay(b.ship, filled: b.filled)..pop = 0),
    ];
    visQueue = List.of(sim.queue);
    flights.clear();
    hops.clear();
    departures.clear();
    _bumps.clear();
    blockerFlash.clear();
    _timeline.clear();
    _cursor = _clock;
    queueSlide = 0;
    noBayPulse = 0;
    _clearPending = false;
    if (laidOut) _layout();
  }

  void _syncNotifiers() {
    if (score.value != sim.score) score.value = sim.score;
    if (levelNumber.value != sim.levelNumber) levelNumber.value = sim.levelNumber;
    if (power.value != sim.power) power.value = sim.power;
    if (undosLeft.value != sim.undosLeft) undosLeft.value = sim.undosLeft;
    if (phase.value != sim.phase) phase.value = sim.phase;
  }

  // ── Input ───────────────────────────────────────────────────────────────

  @override
  void onTapDown(TapDownEvent event) {
    if (paused || _overShown || !isLoaded) return;
    tapAt(Offset(event.localPosition.x, event.localPosition.y));
  }

  /// A tap at a canvas point (what [onTapDown] does; also used by tests).
  TapResult tapAt(Offset p) {
    if (sim.phase != StarportPhase.playing) return TapResult.ignored;
    final ship = shipAt(p);
    if (ship == null) return TapResult.ignored;
    return tapShip(ship.id);
  }

  TapResult tapShip(int shipId) {
    final r = sim.tap(shipId);
    _handleEvents(sim.drainEvents());
    _syncNotifiers();
    return r;
  }

  /// The ready card's button.
  void begin() {
    if (sim.phase != StarportPhase.ready) return;
    sim.start();
    _handleEvents(sim.drainEvents());
    overlays.remove(readyOverlay);
    _syncNotifiers();
  }

  /// The HUD's undo button.
  bool undo() {
    if (paused || _overShown) return false;
    final ok = sim.undo();
    _handleEvents(sim.drainEvents());
    _syncNotifiers();
    return ok;
  }

  /// The clear card (tap, or after [clearHold]): start the next level.
  void continueLevel() {
    if (sim.phase != StarportPhase.levelClear) return;
    overlays.remove(clearOverlay);
    _clearShown = false;
    sim.nextLevel();
    _handleEvents(sim.drainEvents());
    _syncNotifiers();
  }

  // ── Events -> animations, sounds, art ───────────────────────────────────

  /// Schedules [run] when the previous steps are done, then advances the
  /// cursor by [duration].
  void _seq(double duration, void Function() run) {
    final at = math.max(_clock, _cursor);
    _timeline.add(_Step(at, run));
    _cursor = at + duration;
  }

  void _handleEvents(List<StarportEvent> events) {
    final sfx = SfxManager.instance;
    for (final e in events) {
      switch (e) {
        case StarLevelStarted():
          _snapMirror();
          _lowPowerWarned = false;
          art.onEvent(e);
        case StarUndone():
          _snapMirror();
          sfx.play(Sfx.click);
          sfx.light();
          art.onEvent(e);
        case StarBumped(:final shipId, :final blockerId):
          _bumps[shipId] = 0;
          blockerFlash[blockerId] = flashTime;
          sfx.play(Sfx.hit, volume: 0.5);
          sfx.medium();
          art.onEvent(e);
        case StarNoBay():
          noBayPulse = 1;
          sfx.play(Sfx.click, volume: 0.35);
          sfx.light();
          art.onEvent(e);
        case StarLaunched(:final shipId, :final bay):
          final ship = _shipsById[shipId];
          if (ship == null) break;
          _seq(flightTime, () {
            visParked.removeWhere((s) => s.id == shipId);
            flights.add(_makeFlight(ship, bay));
            sfx.play(Sfx.dash, volume: 0.5);
            sfx.light();
            art.onEvent(e);
          });
          // Dock when the flight ends.
          _timeline.add(_Step(_cursor, () {
            if (bay < visBays.length) visBays[bay] = VisBay(ship);
          }));
        case StarBoarded(:final bay, :final color, :final filled):
          _seq(hopTime, () {
            if (visQueue.isNotEmpty) visQueue.removeAt(0);
            queueSlide = 1;
            if (bay < bayRects.length) {
              hops.add(HopToken(color, queueTokenCenter(0), bayRects[bay].center, hopTime));
            }
            sfx.play(Sfx.pickup, volume: 0.3);
            art.onEvent(e);
          });
          _timeline.add(_Step(_cursor, () {
            final b = bay < visBays.length ? visBays[bay] : null;
            if (b != null) {
              b.filled = filled;
              b.pop = 1;
            }
          }));
        case StarDeparted(:final bay):
          _seq(0.06, () {
            final b = bay < visBays.length ? visBays[bay] : null;
            if (b != null && bay < bayRects.length) {
              departures.add(DepartingShip(b.ship, bay, bayRects[bay], departTime));
              visBays[bay] = null;
            }
            sfx.play(Sfx.coin, volume: 0.6);
            sfx.light();
            art.onEvent(e);
          });
        case StarLevelCleared():
          _seq(0, () {
            _clearPending = true;
            sfx.play(Sfx.levelUp);
            sfx.medium();
            art.onEvent(e);
          });
        case StarGridlock():
          _seq(0, () {
            _overAt = _clock;
            sfx.play(Sfx.explode);
            sfx.play(Sfx.playerHit);
            sfx.heavy();
            art.onEvent(e);
          });
        case StarPowerOut():
          _seq(0, () {
            _overAt = _clock;
            sfx.play(Sfx.explode);
            sfx.play(Sfx.playerHit);
            sfx.heavy();
            art.onEvent(e);
          });
      }
    }
  }

  FlyingShip _makeFlight(StarShip s, int bay) {
    final rect = shipRect(s);
    final start = rect.center;
    final reach = s.length * cellSize / 2 + 6;
    final out = switch (s.facing) {
      Facing.right => Offset(hangarRect.right + reach, start.dy),
      Facing.left => Offset(hangarRect.left - reach, start.dy),
      Facing.down => Offset(start.dx, hangarRect.bottom + reach),
      Facing.up => Offset(start.dx, hangarRect.top - reach),
    };
    final target = bay < bayRects.length ? bayRects[bay] : bayRects.last;
    final shipLen = s.length * cellSize;
    final endScale = (math.min(target.width, target.height) * 0.8 / shipLen).clamp(0.25, 1.0).toDouble();
    return FlyingShip(s, [start, out, target.center], flightTime, endScale);
  }

  // ── Frame loop ──────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    // Long frames (app switch) must not teleport the animations or drain
    // the power meter.
    final d = dt > 1 / 20 ? 1 / 20 : dt;
    super.update(d);
    _clock += d;

    sim.step(d);
    _handleEvents(sim.drainEvents());

    while (_timeline.isNotEmpty && _timeline.first.at <= _clock) {
      _timeline.removeAt(0).run();
    }
    _advanceAnimations(d);

    // Low power warning, once per dip.
    if (sim.phase == StarportPhase.playing) {
      if (sim.power < 0.2 && !_lowPowerWarned) {
        _lowPowerWarned = true;
        SfxManager.instance.play(Sfx.warning);
      } else if (sim.power > 0.3) {
        _lowPowerWarned = false;
      }
    }

    _syncNotifiers();

    if (_clearPending && !busy && !_clearShown && sim.phase == StarportPhase.levelClear) {
      _clearShown = true;
      _clearAt = _clock;
      overlays.add(clearOverlay);
    }
    if (_clearShown && _clock - _clearAt >= clearHold) continueLevel();

    final overAt = _overAt;
    if (overAt != null && !_overShown && !busy && _clock - overAt >= overDelay) {
      _overShown = true;
      unawaited(_finish());
    }
  }

  void _advanceAnimations(double d) {
    for (final f in flights) {
      f.t += d;
    }
    flights.removeWhere((f) => f.done);
    for (final h in hops) {
      h.t += d;
    }
    hops.removeWhere((h) => h.done);
    for (final p in departures) {
      p.t += d;
    }
    departures.removeWhere((p) => p.done);
    for (final k in _bumps.keys.toList()) {
      final t = _bumps[k]! + d;
      if (t >= bumpTime) {
        _bumps.remove(k);
      } else {
        _bumps[k] = t;
      }
    }
    for (final k in blockerFlash.keys.toList()) {
      final t = blockerFlash[k]! - d;
      if (t <= 0) {
        blockerFlash.remove(k);
      } else {
        blockerFlash[k] = t;
      }
    }
    noBayPulse = math.max(0, noBayPulse - d / noBayTime);
    queueSlide = math.max(0, queueSlide - d / slideTime);
    for (final b in visBays) {
      if (b != null && b.pop > 0) b.pop = math.max(0, b.pop - d / 0.25);
    }
  }

  Future<void> _finish() async {
    result = await ArcadeManager.instance.finishRound(
      arcadeGame,
      score: sim.score,
      bonus: sim.bonus,
    );
    if (result!.newBest) SfxManager.instance.play(Sfx.levelUp);
    overlays.add(overOverlay);
  }

  /// "Play again" on the results panel: a fresh run, straight into level 1.
  void restart() {
    overlays.remove(overOverlay);
    overlays.remove(clearOverlay);
    result = null;
    _overShown = false;
    _overAt = null;
    _clearShown = false;
    sim.reset();
    _snapMirror();
    art.onRestart();
    _syncNotifiers();
    begin();
  }

  void pauseRound() {
    if (_overShown || paused) return;
    pauseEngine();
    overlays.add(pauseOverlay);
  }

  void resumeRound() {
    overlays.remove(pauseOverlay);
    resumeEngine();
  }
}
