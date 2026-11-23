import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../../cosmetics/catalog.dart';
import '../../game/fx/glow.dart';
import '../../game/render/explosion_art.dart';
import '../../game/render/ship_art.dart';
import '../../game/render/trail_art.dart';
import '../arcade_manager.dart';
import 'thread_sim.dart';

/// Draws Thread the Needle from [sim]'s state (the design agent's file).
/// Contract with the game:
///   * `ThreadArt(ThreadSim sim)` and a settable [sim] (the game swaps the
///     sim when the screen is resized before a round starts),
///   * [onEvent] (flap / score / shard / crash, called once per event),
///   * [onRestart] (a new round: clear any leftover effects).
/// It only READS the sim, never changes it.
///
/// Look: deep space baked once to an image, three parallax star layers,
/// rock columns with a shape and stone of their own (per column id, cached),
/// an ion beacon on each gap edge (gold with chevrons when the gap moves),
/// gold NOVA shards, the player's equipped ship + thruster wake, a thrust
/// puff per tap, and a crash in the equipped explosion style with debris
/// and a short shake. Everything per-frame is cached paths, shaders, glow
/// sprites and raw points: no blur, no full-screen layers.
class ThreadArt extends Component {
  ThreadArt(this.sim);

  ThreadSim sim;
  ThreadSim? _laidOutFor;

  double _t = 0; // seconds, always running (bobs, twinkles)
  double _scroll = 0; // px the field has moved

  // ── Effects state ──────────────────────────────────────────────────────
  final _parts = <_Particle>[];
  final _pops = <_Pop>[];
  final _rings = <_Ring>[];
  final _flash = <int, double>{}; // column id → seconds of "passed" flash left
  final _lastGap = <int, double>{}; // column id → gapCenter last frame (for chevrons)
  final _rng = math.Random();
  double _flapKick = 0; // engine flare after a tap, 1 → 0
  double _shake = 0;
  double _readyPulse = 0;

  ExplosionBurst? _boom;
  Offset _boomAt = Offset.zero;
  double _boomT = 0;
  double _crashFlash = 0;

  // Thruster wake: nozzle positions, newest first.
  static const _trailN = 22;
  final _tx = List<double>.filled(_trailN, 0);
  final _ty = List<double>.filled(_trailN, 0);
  int _trailCount = 0;

  // ── Cached per-size assets ─────────────────────────────────────────────
  Image? _bg;
  Size _bgSize = Size.zero;
  late _Stars _stars;
  final _rocks = <int, _RockPair>{};

  void onEvent(ThreadEvent e) {
    switch (e.kind) {
      case ThreadEventKind.flap:
        _flapKick = 1;
        final n = _nozzle();
        _rings.add(_Ring(n.dx, n.dy, _engineColor, 0.32, 4, 18));
        for (var i = 0; i < 6; i++) {
          final a = math.pi + sim.tilt + (_rng.nextDouble() - 0.5) * 1.3;
          final sp = 70 + _rng.nextDouble() * 90;
          _parts.add(_Particle(n.dx, n.dy, math.cos(a) * sp, math.sin(a) * sp + 40, 0.38, 2.5 + _rng.nextDouble() * 2,
              _engineColor, drag: 3));
        }
      case ThreadEventKind.score:
        // Flash the gate just cleared (the right-most passed column).
        ThreadColumn? best;
        for (final c in sim.columns) {
          if (c.passed && (best == null || c.x > best.x)) best = c;
        }
        if (best != null) _flash[best.id] = 0.45;
      case ThreadEventKind.shard:
        _rings.add(_Ring(e.x, e.y, _gold, 0.45, 6, 34));
        for (var i = 0; i < 14; i++) {
          final a = i / 14 * math.pi * 2 + _rng.nextDouble() * 0.3;
          final sp = 90 + _rng.nextDouble() * 120;
          _parts.add(_Particle(e.x, e.y, math.cos(a) * sp, math.sin(a) * sp, 0.55, 2 + _rng.nextDouble() * 2.2, _gold,
              drag: 4, hot: true));
        }
        _pops.add(_Pop(e.x, e.y - 14, '+${ArcadeManager.coinsPerBonus}'));
      case ThreadEventKind.crash:
        _boom = ExplosionBurst(
          style: explosionStyleFor(CoinManager.instance.selectedExplosion),
          radius: 22,
          big: true,
        );
        _boomAt = Offset(e.x, e.y);
        _boomT = 0;
        _crashFlash = 1;
        _shake = 1;
        // Hull fragments and rock chips.
        final p = _palette;
        for (var i = 0; i < 12; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          final sp = 80 + _rng.nextDouble() * 200;
          final rock = i >= 6;
          _parts.add(_Particle(e.x, e.y, math.cos(a) * sp - 40, math.sin(a) * sp - 60, 1.1 + _rng.nextDouble() * 0.5,
              rock ? 3 + _rng.nextDouble() * 3 : 2.5 + _rng.nextDouble() * 2.5,
              rock ? const Color(0xFF5A5F8A) : (i.isEven ? p.wing : p.hull),
              gravity: 420, shard: true, spin: (_rng.nextDouble() - 0.5) * 14));
        }
    }
  }

  void onRestart() {
    _parts.clear();
    _pops.clear();
    _rings.clear();
    _flash.clear();
    _lastGap.clear();
    _rocks.clear();
    _boom = null;
    _crashFlash = 0;
    _shake = 0;
    _flapKick = 0;
    _trailCount = 0;
  }

  // ── Helpers ────────────────────────────────────────────────────────────
  static const _gold = Color(0xFFFFC23D);
  static const _ion = Color(0xFF4DE8FF);
  static const shipScale = 0.66; // ~28 px wingspan for a 13 px hit radius

  ShipPalette get _palette => shipPaletteFor(CoinManager.instance.selectedSkin);
  ThrusterSpec get _thruster => thrusterSpecFor(CoinManager.instance.selectedThruster);
  Color get _engineColor => _thruster.color ?? _palette.engine;

  Offset _nozzle() {
    final a = sim.tilt;
    return Offset(sim.shipX - math.cos(a) * 11, sim.shipY - math.sin(a) * 11);
  }

  void _layout() {
    final size = Size(sim.width, sim.height);
    if (_bgSize != size || _bg == null) {
      _bg?.dispose();
      _bg = _bakeBackground(size);
      _bgSize = size;
      _stars = _Stars(size, 11);
    }
    _rocks.clear();
    _laidOutFor = sim;
  }

  // ── Update ─────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    if (!identical(_laidOutFor, sim)) _layout();
    _t += dt;
    final playing = sim.phase == ThreadPhase.playing;
    final ready = sim.phase == ThreadPhase.ready;
    // The field drifts gently while waiting so the screen never looks frozen.
    final speed = playing ? sim.speed : (ready ? sim.height * 0.05 : 0.0);
    final dx = speed * dt;
    _scroll += dx;
    _readyPulse = ready ? math.min(1, _readyPulse + dt * 3) : math.max(0, _readyPulse - dt * 4);

    if (_flapKick > 0) _flapKick = math.max(0, _flapKick - dt * 4);
    if (_shake > 0) _shake = math.max(0, _shake - dt * 2.4);
    if (_crashFlash > 0) _crashFlash = math.max(0, _crashFlash - dt * 3.5);
    if (_boom != null) {
      _boomT += dt;
      if (_boomT > _boom!.life) _boom = null;
    }

    // Wake: points ride with the field; a new one at the nozzle while alive.
    for (var i = 0; i < _trailCount; i++) {
      _tx[i] -= dx;
    }
    if (sim.phase != ThreadPhase.crashed) {
      for (var i = math.min(_trailCount, _trailN - 1); i > 0; i--) {
        _tx[i] = _tx[i - 1];
        _ty[i] = _ty[i - 1];
      }
      final n = _nozzle();
      _tx[0] = n.dx;
      _ty[0] = n.dy;
      _trailCount = math.min(_trailCount + 1, _trailN);
    } else if (_trailCount > 0 && (_t * 60).floor().isEven) {
      _trailCount--; // the wake dies away behind the wreck
    }

    for (final p in _parts) {
      p.age += dt;
      final k = math.max(0.0, 1 - p.drag * dt);
      p.vx *= k;
      p.vy = p.vy * k + p.gravity * dt;
      p.x += (p.vx - (p.shard ? 0 : speed * 0.6)) * dt;
      p.y += p.vy * dt;
      p.rot += p.spin * dt;
    }
    _parts.removeWhere((p) => p.age >= p.life);
    for (final r in _rings) {
      r.age += dt;
      r.x -= dx;
    }
    _rings.removeWhere((r) => r.age >= r.life);
    for (final p in _pops) {
      p.age += dt;
      p.x -= dx * 0.5;
    }
    _pops.removeWhere((p) => p.age >= 0.8);
    _flash.updateAll((_, v) => v - dt);
    _flash.removeWhere((_, v) => v <= 0);

    // Wreck: smoke puffs while it tumbles.
    if (sim.phase == ThreadPhase.crashed && sim.crashedFor < 1.2 && _rng.nextDouble() < dt * 30) {
      _parts.add(_Particle(sim.shipX + (_rng.nextDouble() - 0.5) * 8, sim.shipY, (_rng.nextDouble() - 0.5) * 20, -30, 0.7,
          5 + _rng.nextDouble() * 4, const Color(0xFF8E97C7), drag: 1, smoke: true));
    }

    // Forget rocks that left the screen.
    if (_rocks.length > 12) {
      final live = {for (final c in sim.columns) c.id};
      _rocks.removeWhere((id, _) => !live.contains(id));
      _lastGap.removeWhere((id, _) => !live.contains(id));
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────
  @override
  void render(Canvas canvas) {
    if (!identical(_laidOutFor, sim)) _layout();
    final w = sim.width, h = sim.height;

    canvas.save();
    if (_shake > 0) {
      final s = _shake * _shake * 9;
      canvas.translate((_rng.nextDouble() * 2 - 1) * s, (_rng.nextDouble() * 2 - 1) * s);
    }

    // Sky (baked) a little oversized so the shake never shows an edge.
    canvas.drawImageRect(_bg!, Rect.fromLTWH(0, 0, _bgSize.width, _bgSize.height), Rect.fromLTWH(-12, -12, w + 24, h + 24),
        _imagePaint);
    _stars.paint(canvas, _scroll, _t);

    for (final c in sim.columns) {
      if (c.right < -12 || c.x > w + 12) {
        _lastGap[c.id] = c.gapCenter;
        continue;
      }
      _paintColumn(canvas, c, h);
    }
    for (final c in sim.columns) {
      if (c.hasShard && !c.shardTaken && c.x < w + 30 && c.right > -30) {
        paintShard(canvas, Offset(c.shardX, c.shardY + math.sin(_t * 3 + c.id) * 2), _t + c.id * 0.7);
      }
    }

    // Wake, puffs and sparks behind the ship.
    TrailArt.paint(canvas, _tx, _ty, _trailCount, _trailN, _engineColor, _thruster.trail, _t);
    for (final r in _rings) {
      final f = r.age / r.life;
      _ringPaint
        ..strokeWidth = 2.4 * (1 - f) + 0.4
        ..color = r.color.withValues(alpha: 0.8 * (1 - f));
      canvas.drawCircle(Offset(r.x, r.y), r.r0 + (r.r1 - r.r0) * (1 - (1 - f) * (1 - f)), _ringPaint);
    }
    _paintParticles(canvas, back: true);

    _paintShip(canvas);

    final boom = _boom;
    if (boom != null) {
      canvas.save();
      canvas.translate(_boomAt.dx, _boomAt.dy);
      boom.paint(canvas, _boomT, const Color(0xFFFF7A45));
      canvas.restore();
    }
    _paintParticles(canvas, back: false);
    for (final p in _pops) {
      _paintPop(canvas, p);
    }

    // Speed streaks in front of everything once the round is quick.
    if (sim.phase == ThreadPhase.playing) _paintStreaks(canvas, w, h);

    canvas.restore();

    if (_crashFlash > 0) {
      _washPaint.color = const Color(0xFFFF4766).withValues(alpha: 0.22 * _crashFlash);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), _washPaint);
    }
  }

  static final _imagePaint = Paint()..filterQuality = FilterQuality.low;
  static final _washPaint = Paint()..blendMode = BlendMode.plus;
  static final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  // ── Columns ────────────────────────────────────────────────────────────
  static final _rockFill = Paint()..isAntiAlias = true;
  static final _crater = Paint();
  static final _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  static final _chevron = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = 2
    ..blendMode = BlendMode.plus;

  void _paintColumn(Canvas canvas, ThreadColumn c, double h) {
    final pair = _rocks.putIfAbsent(c.id, () => _RockPair(c.id, c.width, h + 60));
    final flash = (_flash[c.id] ?? 0) / 0.45;
    final prev = _lastGap[c.id] ?? c.gapCenter;
    final dir = c.gapCenter - prev; // >0 moving down
    _lastGap[c.id] = c.gapCenter;

    // Top piece grows upward from the gap edge (flipped), bottom downward.
    canvas.save();
    canvas.translate(c.x, c.gapTop);
    canvas.scale(1, -1);
    pair.top.paint(canvas, flash);
    canvas.restore();
    canvas.save();
    canvas.translate(c.x, c.gapBottom);
    pair.bottom.paint(canvas, flash);
    canvas.restore();

    // Gate beacons on both edges: ion, gold when the gap moves.
    final col = c.moving ? _gold : _ion;
    final mid = c.x + c.width / 2;
    final pulse = 0.55 + 0.25 * math.sin(_t * 4 + c.id);
    for (final y in [c.gapTop - pair.top.capInset, c.gapBottom + pair.bottom.capInset]) {
      Glow.draw(canvas, Offset(mid, y), 9 + 14 * flash, col.withValues(alpha: (pulse * 0.5 + 0.5 * flash).clamp(0, 1)));
      Glow.draw(canvas, Offset(mid, y), 3 + 2 * flash, const Color(0xFFFFFFFF).withValues(alpha: 0.9), hot: true);
    }
    if (flash > 0) {
      // A light sweep through the gate you just cleared.
      Glow.drawOval(canvas, Rect.fromLTRB(c.x - 6, c.gapTop, c.right + 6, c.gapBottom), _ion.withValues(alpha: 0.28 * flash));
    }
    // Moving gaps: chevrons inside the gap pointing the way it's heading.
    if (c.moving && dir.abs() > 0.02) {
      final down = dir > 0;
      final a = 0.35 + 0.25 * math.sin(_t * 6);
      _chevron.color = _gold.withValues(alpha: a);
      for (var k = 0; k < 2; k++) {
        final y = down ? c.gapBottom - 12 - k * 7 : c.gapTop + 12 + k * 7;
        final s = down ? 1.0 : -1.0;
        canvas.drawPath(
          Path()
            ..moveTo(mid - 5, y - 3 * s)
            ..lineTo(mid, y + 2 * s)
            ..lineTo(mid + 5, y - 3 * s),
          _chevron,
        );
      }
    }
  }

  // ── Shard ──────────────────────────────────────────────────────────────
  static final _shardFill = Paint();
  static final _shardEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = const Color(0xCCFFF3C4);
  static final _shardBody = Path()
    ..moveTo(0, -11)
    ..lineTo(7, -3)
    ..lineTo(5, 7)
    ..lineTo(0, 11)
    ..lineTo(-5, 7)
    ..lineTo(-7, -3)
    ..close();
  static final _shardTop = Path()
    ..moveTo(0, -11)
    ..lineTo(7, -3)
    ..lineTo(0, 1)
    ..lineTo(-7, -3)
    ..close();

  /// A gold NOVA crystal turning on its axis, with a glow and a twinkle.
  /// Shared with the arcade hub's preview.
  static void paintShard(Canvas canvas, Offset c, double t) {
    final spin = math.cos(t * 2.6);
    final sx = 0.3 + 0.7 * spin.abs();
    Glow.draw(canvas, c, 24 + 3 * math.sin(t * 5), _gold.withValues(alpha: 0.45));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(sx, 1);
    _shardFill.color = spin > 0 ? const Color(0xFFFFC23D) : const Color(0xFFE08A12);
    canvas.drawPath(_shardBody, _shardFill);
    _shardFill.color = const Color(0xFFFFE08A);
    canvas.drawPath(_shardTop, _shardFill);
    canvas.drawPath(_shardBody, _shardEdge);
    canvas.restore();
    final tw = math.sin(t * 7);
    if (tw > 0.4) {
      final k = (tw - 0.4) / 0.6;
      Glow.draw(canvas, c + const Offset(4, -8), 6 * k, const Color(0xFFFFFFFF).withValues(alpha: k), hot: true);
    }
  }

  // ── Ship ───────────────────────────────────────────────────────────────
  void _paintShip(Canvas canvas) {
    final crashed = sim.phase == ThreadPhase.crashed;
    if (crashed && sim.crashedFor > 1.4) return;
    final pos = Offset(sim.shipX, sim.shipY);
    if (_readyPulse > 0) {
      // "This is you": a soft ion ring breathing round the ship before the first tap.
      final b = (_t % 1.4) / 1.4;
      _ringPaint
        ..strokeWidth = 1.6
        ..color = _ion.withValues(alpha: 0.5 * (1 - b) * _readyPulse);
      canvas.drawCircle(pos, 20 + 16 * b, _ringPaint);
    }
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(math.pi / 2 + sim.tilt + (crashed ? sim.crashedFor * 7 : 0));
    canvas.scale(shipScale);
    ShipArt.paint(
      canvas,
      _palette,
      time: _t,
      thrust: crashed ? 0 : 0.45 + 0.55 * _flapKick,
      engines: !crashed,
      engine: _thruster.color,
    );
    canvas.restore();
    if (crashed) {
      // Burning wreck.
      final k = (1 - sim.crashedFor / 1.4).clamp(0.0, 1.0);
      Glow.draw(canvas, pos, 16 * k, const Color(0xFFFF7A45).withValues(alpha: 0.8 * k));
    }
  }

  // ── Particles, pops, streaks ───────────────────────────────────────────
  static final _partPaint = Paint();
  static final _chip = Path();

  void _paintParticles(Canvas canvas, {required bool back}) {
    for (final p in _parts) {
      // Smoke and engine puffs go behind the ship; sparks and debris in front.
      final isBack = p.smoke || (!p.shard && !p.hot);
      if (isBack != back) continue;
      final f = p.age / p.life;
      if (p.shard) {
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(p.rot);
        _partPaint.color = p.color.withValues(alpha: (1 - f * f).clamp(0, 1));
        _chip
          ..reset()
          ..moveTo(-p.size, -p.size * 0.6)
          ..lineTo(p.size, -p.size * 0.2)
          ..lineTo(-p.size * 0.3, p.size * 0.8)
          ..close();
        canvas.drawPath(_chip, _partPaint);
        canvas.restore();
      } else if (p.smoke) {
        _partPaint.color = p.color.withValues(alpha: 0.22 * (1 - f));
        canvas.drawCircle(Offset(p.x, p.y), p.size * (1 + f * 1.5), _partPaint);
      } else {
        Glow.draw(canvas, Offset(p.x, p.y), p.size * 2.4 * (1 - f * 0.5), p.color.withValues(alpha: 1 - f), hot: p.hot);
      }
    }
  }

  static final Map<String, Paragraph> _popText = {};
  static final _layerPaint = Paint();

  void _paintPop(Canvas canvas, _Pop p) {
    final para = _popText.putIfAbsent(p.text, () {
      final b = ParagraphBuilder(ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(TextStyle(
          color: _gold,
          fontSize: 17,
          fontFamily: 'ChakraPetch',
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Color(0xCC050817), blurRadius: 4)],
        ))
        ..addText(p.text);
      return b.build()..layout(const ParagraphConstraints(width: 60));
    });
    final f = p.age / 0.8;
    final y = p.y - 22 * (1 - (1 - f) * (1 - f));
    final a = f < 0.6 ? 1.0 : 1 - (f - 0.6) / 0.4;
    // A small, short-lived layer (one pop at a time, 0.8 s) for the fade.
    _layerPaint.color = Color.fromRGBO(0, 0, 0, a);
    canvas.saveLayer(Rect.fromLTWH(p.x - 30, y - 12, 60, 26), _layerPaint);
    canvas.drawParagraph(para, Offset(p.x - 30, y - 10));
    canvas.restore();
  }

  static final _streak = Paint()
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  final _streakPts = Float32List(14 * 4);

  void _paintStreaks(Canvas canvas, double w, double h) {
    // Fade in as speed climbs past the start speed.
    final k = ((sim.speed / h - ThreadTuning.startSpeed) / (ThreadTuning.maxSpeed - ThreadTuning.startSpeed)).clamp(0.0, 1.0);
    if (k <= 0.05) return;
    final len = 18 + 40 * k;
    for (var i = 0; i < 14; i++) {
      final seed = i * 0.6180339;
      final y = (seed * 997 % 1) * h;
      final x = w - ((_scroll * 1.8 + seed * 3000) % (w + len * 2)) + len;
      _streakPts[i * 4] = x;
      _streakPts[i * 4 + 1] = y;
      _streakPts[i * 4 + 2] = x + len;
      _streakPts[i * 4 + 3] = y;
    }
    _streak.color = const Color(0xFFE9EDFF).withValues(alpha: 0.10 * k);
    canvas.drawRawPoints(PointMode.lines, _streakPts, _streak);
  }

  // ── Background bake ────────────────────────────────────────────────────
  static Image _bakeBackground(Size s) {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    paintSky(c, s);
    return rec.endRecording().toImageSync(s.width.ceil(), s.height.ceil());
  }

  /// The game's sky: a deep gradient, two faint nebula clouds and a distant
  /// planet low on the right. Baked once per size in the game; the hub's
  /// preview draws it straight.
  static void paintSky(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.linear(Offset.zero, Offset(0, s.height), const [
          Color(0xFF070B24),
          Color(0xFF0B1233),
          Color(0xFF050817),
        ], const [0, 0.55, 1]),
    );
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.radial(Offset(s.width * 0.82, s.height * 0.18), s.height * 0.55, const [
          Color(0x2EA07CFF),
          Color(0x0FA07CFF),
          Color(0x00A07CFF),
        ], const [0, 0.45, 1]),
    );
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.radial(Offset(s.width * 0.1, s.height * 0.85), s.height * 0.5, const [
          Color(0x224DE8FF),
          Color(0x0A4DE8FF),
          Color(0x004DE8FF),
        ], const [0, 0.5, 1]),
    );
    // A distant planet low on the right: dark disc with an ion rim.
    final pc = Offset(s.width * 0.94, s.height * 1.1);
    final pr = s.height * 0.26;
    c.drawCircle(
      pc,
      pr,
      Paint()
        ..shader = Gradient.radial(pc.translate(-pr * 0.35, -pr * 0.4), pr * 1.3, const [
          Color(0xFF1A2456),
          Color(0xFF0C1235),
          Color(0xFF060A1E),
        ], const [0, 0.55, 1]),
    );
    c.drawCircle(
      pc,
      pr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x554DE8FF),
    );
  }

  // ── Hub preview ────────────────────────────────────────────────────────
  static final _previewRocks = <String, _RockPair>{};
  static final _previewStars = <Size, _Stars>{};

  /// A small, live still of the game for the arcade hub's card: sky, stars,
  /// two rock columns, a shard in a gap and the equipped ship flying
  /// through. [t] in seconds drives the drift, the bob and the shard's turn.
  static void paintPreview(Canvas canvas, Size s, double t) {
    final h = s.height;
    paintSky(canvas, s);
    _previewStars.putIfAbsent(s, () => _Stars(s, 5)).paint(canvas, t * 14, t);
    final colW = h * 0.17;
    final cols = [(s.width * 0.5, h * 0.44, 0.6), (s.width * 0.86, h * 0.6, 0.0)];
    for (var i = 0; i < cols.length; i++) {
      final (x, gap, flash) = cols[i];
      final key = '$i:${colW.round()}:${h.round()}';
      final pair = _previewRocks.putIfAbsent(key, () => _RockPair(12 + i * 5, colW, h + 40));
      final half = h * 0.2;
      canvas.save();
      canvas.translate(x, gap - half);
      canvas.scale(1, -1);
      pair.top.paint(canvas, flash);
      canvas.restore();
      canvas.save();
      canvas.translate(x, gap + half);
      pair.bottom.paint(canvas, flash);
      canvas.restore();
      for (final y in [gap - half - pair.top.capInset, gap + half + pair.bottom.capInset]) {
        Glow.draw(canvas, Offset(x + colW / 2, y), 9, _ion.withValues(alpha: 0.6));
        Glow.draw(canvas, Offset(x + colW / 2, y), 3, const Color(0xFFFFFFFF).withValues(alpha: 0.9), hot: true);
      }
      if (i == 1) paintShard(canvas, Offset(x + colW / 2, gap + math.sin(t * 3) * 2), t);
    }
    // Ship climbing toward the first gap, with a short wake.
    final p = shipPaletteFor(CoinManager.instance.selectedSkin);
    final th = thrusterSpecFor(CoinManager.instance.selectedThruster);
    final ship = Offset(s.width * 0.24, h * 0.5 + math.sin(t * 2.2) * h * 0.05);
    final tilt = -0.22 * math.cos(t * 2.2);
    const n = 12;
    final xs = List<double>.generate(n, (k) => ship.dx - 10 - k * 7);
    final ys = List<double>.generate(n, (k) => h * 0.5 + math.sin(t * 2.2 - (k + 1) * 0.12) * h * 0.05);
    TrailArt.paint(canvas, xs, ys, n, n, th.color ?? p.engine, th.trail, t);
    canvas.save();
    canvas.translate(ship.dx, ship.dy);
    canvas.rotate(math.pi / 2 + tilt);
    canvas.scale(shipScale * 1.1);
    ShipArt.paint(canvas, p, time: t, thrust: 0.7 + 0.3 * math.sin(t * 9).abs(), engine: th.color);
    canvas.restore();
  }
}

// ── Rocks ──────────────────────────────────────────────────────────────────

/// Three stones, so neighbouring columns read as different rocks.
const _stones = [
  (Color(0xFF3B4479), Color(0xFF232A55), Color(0xFF12163A)), // slate blue
  (Color(0xFF4A3B78), Color(0xFF2A2152), Color(0xFF140F31)), // violet basalt
  (Color(0xFF4B3B4E), Color(0xFF2C2233), Color(0xFF16101C)), // umber
];

class _RockPair {
  final _Rock top;
  final _Rock bottom;
  _RockPair(int id, double width, double length)
      : top = _Rock(math.Random(id * 7919 + 1), width, length, _stones[id % 3]),
        bottom = _Rock(math.Random(id * 7919 + 2), width, length, _stones[id % 3]);
}

/// One rock piece in "into the rock" coordinates: x across the column
/// (0..width), y = 0 at the gap edge, growing into the rock. The outline
/// stays inside the column's rectangle, so what you see never hurts you
/// more than what's there.
class _Rock {
  final Path body;
  final Path rim; // the gap-facing end and the lit side near it
  final Path capEdge;
  final List<(double, double, double)> craters;
  final Path facets; // lighter planes on the lit side
  final Path cracks; // dark fracture lines between boulders
  final Shader shader;
  final double capInset;

  factory _Rock(math.Random r, double w, double len, (Color, Color, Color) stone) {
    // Left side, from deep in the rock up toward the cap.
    final leftPts = <Offset>[];
    for (var y = len; y > 34; y -= 30 + r.nextDouble() * 22) {
      leftPts.add(Offset(r.nextDouble() * 4.5, y));
    }
    // Cap: a chunky, broken edge a few px inside the gap edge.
    final capPts = <Offset>[];
    const steps = 5;
    var inset = 0.0;
    for (var i = 0; i <= steps; i++) {
      final x = i == 0 ? 2 + r.nextDouble() * 3 : (i == steps ? w - 2 - r.nextDouble() * 3 : (i / steps) * w);
      final y = 1.5 + r.nextDouble() * 6.5;
      capPts.add(Offset(x, y));
      if (i == steps ~/ 2) inset = y;
    }
    // Shoulders: corners chipped back so the end reads as rock, not a slab.
    final shoulderL = Offset(r.nextDouble() * 3, 10 + r.nextDouble() * 10);
    final shoulderR = Offset(w - r.nextDouble() * 3, 10 + r.nextDouble() * 10);
    final rightPts = <Offset>[];
    for (var y = 34.0; y < len; y += 30 + r.nextDouble() * 22) {
      rightPts.add(Offset(w - r.nextDouble() * 4.5, y));
    }

    final body = Path()..moveTo(leftPts.isEmpty ? 0 : leftPts.first.dx, len);
    for (final p in leftPts) {
      body.lineTo(p.dx, p.dy);
    }
    body.lineTo(shoulderL.dx, shoulderL.dy);
    for (final p in capPts) {
      body.lineTo(p.dx, p.dy);
    }
    body.lineTo(shoulderR.dx, shoulderR.dy);
    for (final p in rightPts) {
      body.lineTo(p.dx, p.dy);
    }
    body
      ..lineTo(w - 2, len)
      ..close();

    // Rim: up the left side near the end, across the cap, onto the right shoulder.
    final nearLeft = leftPts.where((p) => p.dy < 110).toList();
    final rim = Path()..moveTo(nearLeft.isEmpty ? shoulderL.dx : nearLeft.first.dx, nearLeft.isEmpty ? shoulderL.dy + 30 : nearLeft.first.dy);
    for (final p in nearLeft.skip(1)) {
      rim.lineTo(p.dx, p.dy);
    }
    rim.lineTo(shoulderL.dx, shoulderL.dy);
    for (final p in capPts) {
      rim.lineTo(p.dx, p.dy);
    }
    rim.lineTo(shoulderR.dx, shoulderR.dy);
    final cap = Path()..moveTo(shoulderL.dx, shoulderL.dy);
    for (final p in capPts) {
      cap.lineTo(p.dx, p.dy);
    }
    cap.lineTo(shoulderR.dx, shoulderR.dy);

    final craters = <(double, double, double)>[];
    for (var i = 0; i < 9; i++) {
      final y = i < 4 ? 26 + r.nextDouble() * 110 : 60 + r.nextDouble() * (len - 80);
      craters.add((w * (0.25 + r.nextDouble() * 0.5), y, 2.5 + r.nextDouble() * (w * 0.13)));
    }
    // The column is a stack of boulders: a fracture across it every
    // 50-110 px, each boulder with a lit facet on its left shoulder.
    final facets = Path();
    final cracks = Path();
    var y0 = 16 + r.nextDouble() * 10;
    while (y0 < len) {
      final y1 = y0 + 50 + r.nextDouble() * 60;
      final fx = w * (0.18 + r.nextDouble() * 0.2);
      facets
        ..moveTo(5, y0 + 4)
        ..lineTo(w * (0.45 + r.nextDouble() * 0.2), y0 + 2 + r.nextDouble() * 6)
        ..lineTo(fx + w * 0.15, y0 + (y1 - y0) * (0.35 + r.nextDouble() * 0.2))
        ..lineTo(5, y0 + (y1 - y0) * 0.6)
        ..close();
      if (y1 < len - 10) {
        // Inside the outline (sides are inset at most 4.5 px), so no clip needed.
        cracks.moveTo(5, y1 + (r.nextDouble() - 0.5) * 8);
        for (var k = 1; k <= 4; k++) {
          cracks.lineTo(5 + (w - 10) * k / 4, y1 + (r.nextDouble() - 0.5) * 12);
        }
      }
      y0 = y1;
    }
    final shader = Gradient.linear(Offset.zero, Offset(w, 0), [stone.$1, stone.$2, stone.$3], const [0, 0.4, 1]);
    return _Rock._(body, rim, cap, craters, facets, cracks, shader, inset);
  }

  _Rock._(this.body, this.rim, this.capEdge, this.craters, this.facets, this.cracks, this.shader, this.capInset);

  void paint(Canvas canvas, double flash) {
    ThreadArt._rockFill.shader = shader;
    canvas.drawPath(body, ThreadArt._rockFill);
    ThreadArt._rockFill.shader = null;
    ThreadArt._crater.color = const Color(0x14E9EDFF);
    canvas.drawPath(facets, ThreadArt._crater);
    ThreadArt._rim
      ..strokeWidth = 1.6
      ..color = const Color(0x8C050817);
    canvas.drawPath(cracks, ThreadArt._rim);
    for (final (x, y, r) in craters) {
      ThreadArt._crater.color = const Color(0x52050817);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 1.6), ThreadArt._crater);
      ThreadArt._crater.color = const Color(0x1FE9EDFF);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y - r * 0.3), width: r * 1.3, height: r * 0.5), ThreadArt._crater);
    }
    // Lit edge: a cool starlight hairline round the end, the cap itself in
    // ion so the opening reads at a glance (brighter as you clear it).
    ThreadArt._rim
      ..strokeWidth = 1.2
      ..color = const Color(0x4DE9EDFF);
    canvas.drawPath(rim, ThreadArt._rim);
    ThreadArt._rim
      ..strokeWidth = 1.6 + flash * 1.4
      ..color = ThreadArt._ion.withValues(alpha: 0.45 + 0.5 * flash);
    canvas.drawPath(capEdge, ThreadArt._rim);
  }
}

// ── Stars ──────────────────────────────────────────────────────────────────

class _Stars {
  final Size size;
  final List<Float32List> base = [];
  final List<Float32List> out = [];
  // (count, parallax factor, dot size, brightness)
  static const _layers = [(46, 0.05, 1.0, 0.35), (30, 0.13, 1.6, 0.55), (16, 0.28, 2.2, 0.8)];
  static final _paint = Paint()..strokeCap = StrokeCap.round;

  _Stars(this.size, int seed) {
    final r = math.Random(seed);
    for (final (n, _, _, _) in _layers) {
      base.add(Float32List.fromList([for (var i = 0; i < n * 2; i++) r.nextDouble()]));
      out.add(Float32List(n * 2));
    }
  }

  void paint(Canvas canvas, double scroll, double t) {
    final w = size.width, h = size.height;
    for (var l = 0; l < _layers.length; l++) {
      final (n, f, sz, a) = _layers[l];
      final b = base[l], o = out[l];
      for (var i = 0; i < n; i++) {
        o[i * 2] = (b[i * 2] * w - scroll * f) % w;
        o[i * 2 + 1] = b[i * 2 + 1] * h;
      }
      _paint
        ..strokeWidth = sz
        ..color = Color.fromRGBO(233, 237, 255, a * (0.85 + 0.15 * math.sin(t * (1.3 + l))));
      canvas.drawRawPoints(PointMode.points, o, _paint);
    }
  }
}

// ── Effect records ─────────────────────────────────────────────────────────

class _Particle {
  double x, y, vx, vy;
  final double life, size, drag, gravity, spin;
  final Color color;
  final bool hot, shard, smoke;
  double age = 0, rot = 0;
  _Particle(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color,
      {this.drag = 0, this.gravity = 0, this.hot = false, this.shard = false, this.smoke = false, this.spin = 0});
}

class _Ring {
  double x;
  final double y, life, r0, r1;
  final Color color;
  double age = 0;
  _Ring(this.x, this.y, this.color, this.life, this.r0, this.r1);
}

class _Pop {
  double x;
  final double y;
  final String text;
  double age = 0;
  _Pop(this.x, this.y, this.text);
}
