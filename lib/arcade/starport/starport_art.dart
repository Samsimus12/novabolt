import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../game/fx/glow.dart';
import '../../ui/theme/type.dart' show NbFonts;
import 'starport_game.dart';
import 'starport_sim.dart';
import 'starport_types.dart';

/// Boarding Call's drawing (the designer's file).
///
/// Contract with [StarportGame] (starport_game.dart):
///   * `StarportArt(StarportGame game)`: a Flame [Component] the game adds
///     to itself in onLoad. It draws everything on the canvas in game px
///     (the canvas is the whole screen; the Flutter HUD/overlays sit on top,
///     in the top [StarportGame.hudHeight] px plus the safe area).
///   * [onEvent] is called once per sim event AT THE MOMENT IT HAPPENS
///     VISUALLY. Used here for particles, pops, the bump "!", the undo
///     rewind, the level-clear sweep and the end states.
///   * [onRestart] is called when a new run starts: clear leftover effects.
///   * It only READS the game (the visual mirror: `visParked`, `visBays`,
///     `visQueue`, `flights`, `hops`, `departures`, `bumpOffset`,
///     `blockerGlow`, `noBayPulse`, `queueSlide`, and the layout rects);
///     never the sim's live state for drawing.
///   * `static void paintPreview(Canvas, Size, double t)`: the arcade hub
///     card's live window.
///
/// Look: the app's own night-station language, like the other arcade
/// games. A dark station interior with a starfield window behind the HUD and
/// the berths, a navy deck, smoked-glass berths and walkway with hairline
/// chamfered edges, and a dark hangar floor whose launch edges are marked in
/// ion (your way out). Light comes only from energy: ship rims, roof
/// symbols, engines, free bays. Ships are top-down; the pointed nose and
/// canopy are the only arrow, and each of the six colors has a symbol on a
/// dark roof disc (circle, star, square, diamond, hexagon, cross), drawn
/// screen-upright, so the game is playable on shape alone. The same symbol is
/// on every passenger's badge. Meanings as everywhere in the app: flare =
/// blocked / danger, ion = free bays, power and your actions, gold = the
/// clean bonus.
class StarportArt extends Component {
  StarportArt(this.game);
  final StarportGame game;

  double _t = 0;

  // ── Palette ───────────────────────────────────────────────────────────────
  static const deck = Color(0xFF0A1130);
  static const deckLow = Color(0xFF050817);
  static const floor = Color(0xFF0B1336);
  static const glass = Color(0xB80C1438);
  static const line = Color(0x1FE9EDFF);
  static const lineStrong = Color(0x3DE9EDFF);
  static const ink = Color(0xFFE9EDFF); // text: starlight
  static const ink2 = Color(0xFFB9C1E6);
  static const muted = Color(0xFF8E97C7);
  static const hazard = Color(0xFF4DE8FF); // launch edges: ion
  static const blue = Color(0xFF4DE8FF); // ion
  static const flare = Color(0xFFFF4766);
  static const mint = Color(0xFF4DE8FF);

  /// The six ship / passenger colors (categorical).
  /// Luminous on the dark station, and told apart by symbol as well as hue.
  static const palette = <Color>[
    Color(0xFFFF6B78), // 0 coral, circle
    Color(0xFFFFB547), // 1 amber, star
    Color(0xFF5BE38A), // 2 green, square
    Color(0xFF4DA8FF), // 3 blue, diamond
    Color(0xFFB08CFF), // 4 violet, hexagon
    Color(0xFFE9EDFF), // 5 pearl, cross
  ];
  static const names = <String>['coral', 'amber', 'green', 'blue', 'violet', 'pearl'];
  static Color colorOf(int c) => palette[c % palette.length];

  /// "the green shuttle" (for the bump caption).
  static String shipName(StarShip s) => 'the ${names[s.color % names.length]} ${s.kind == ShipKind.liner ? 'liner' : 'shuttle'}';

  // ── Effects ───────────────────────────────────────────────────────────────
  final _rings = <_Ring>[];
  final _sparks = <_Spark>[];
  final _pops = <_Pop>[];
  final _rng = math.Random(9);
  _BumpMark? _bump;
  int _bumpCaptions = 0;
  _Caption? _caption;
  _Rewind? _rewind;
  double _sweep = -1; // level-clear sweep, 0..1 while running
  double _levelIn = 0; // 1 -> 0 as a new hangar settles
  double _gridlock = 0; // 0 -> 1 once gridlocked
  double _powerOut = 0; // 0 -> 1 once the power is out
  bool _ended = false;
  final _trails = <int, List<Offset>>{};

  // The bays a frame ago (shipId per bay), for the undo rewind.
  List<int?> _lastBays = const [];

  bool get _reduce => PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  // ── Events ────────────────────────────────────────────────────────────────
  void onEvent(StarportEvent e) {
    switch (e) {
      case StarLevelStarted():
        _levelIn = 1;
        _gridlock = 0;
        _powerOut = 0;
        _ended = false;
        _sweep = -1;
        _rewind = null;
        _bump = null;
      case StarLaunched(:final shipId):
        final f = game.flights.where((f) => f.ship.id == shipId).toList();
        if (f.isNotEmpty) {
          final p = f.last.path.first;
          _rings.add(_Ring(p, game.cellSize * 0.4, game.cellSize * 1.3, 0.35, const Color(0xFF7FE4FF)));
        }
      case StarBumped(:final shipId, :final blockerId):
        StarShip? ship, blocker;
        for (final s in game.visParked) {
          if (s.id == shipId) ship = s;
          if (s.id == blockerId) blocker = s;
        }
        if (ship != null) {
          _bump = _BumpMark(ship, 0);
          if (blocker != null && _bumpCaptions < 3) {
            _bumpCaptions++;
            _caption = _Caption('Blocked by ${shipName(blocker)}', 0);
          }
        }
      case StarNoBay():
        break;
      case StarBoarded(:final bay):
        if (bay < game.bayRects.length) {
          final c = game.bayRects[bay].center;
          _spray(c, 4, const Color(0xFFBFF3FF), game.cellSize * 0.9);
        }
      case StarDeparted(:final bay):
        if (bay < game.bayRects.length) {
          final r = game.bayRects[bay];
          _pops.add(_Pop('+1', r.topCenter + Offset(0, r.height * 0.15), mint, 0));
          _spray(r.center, 8, const Color(0xFFFFFFFF), game.cellSize * 1.2);
        }
      case StarLevelCleared():
        if (!_reduce) _sweep = 0;
        for (var i = 0; i < 14; i++) {
          final r = game.hangarRect;
          _spray(Offset(r.left + _rng.nextDouble() * r.width, r.top + _rng.nextDouble() * r.height), 1, palette[i % 6], game.cellSize);
        }
      case StarUndone(:final shipId):
        _startRewind(shipId);
      case StarGridlock():
        _ended = true;
        _gridlock = 0.001;
      case StarPowerOut():
        _ended = true;
        _powerOut = 0.001;
    }
  }

  void _startRewind(int shipId) {
    StarShip? ship;
    for (final s in game.visParked) {
      if (s.id == shipId) ship = s;
    }
    if (ship == null || _reduce) return;
    var from = Offset(game.stationRect.center.dx, game.stationRect.top - game.cellSize);
    for (var i = 0; i < _lastBays.length && i < game.bayRects.length; i++) {
      if (_lastBays[i] == shipId) from = game.bayRects[i].center;
    }
    final rect = game.shipRect(ship);
    final reach = ship.length * game.cellSize / 2 + 6;
    final out = switch (ship.facing) {
      Facing.right => Offset(game.hangarRect.right + reach, rect.center.dy),
      Facing.left => Offset(game.hangarRect.left - reach, rect.center.dy),
      Facing.down => Offset(rect.center.dx, game.hangarRect.bottom + reach),
      Facing.up => Offset(rect.center.dx, game.hangarRect.top - reach),
    };
    _rewind = _Rewind(ship, [from, out, rect.center], 0);
    _rings.add(_Ring(rect.center, game.cellSize * 0.3, game.cellSize * 1.6, 0.45, blue));
  }

  void _spray(Offset c, int n, Color col, double speed) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final v = speed * (0.5 + _rng.nextDouble() * 0.8);
      _sparks.add(_Spark(c, Offset(math.cos(a), math.sin(a)) * v, 0.35 + _rng.nextDouble() * 0.25, col));
    }
  }

  void onRestart() {
    _rings.clear();
    _sparks.clear();
    _pops.clear();
    _bump = null;
    _caption = null;
    _rewind = null;
    _sweep = -1;
    _gridlock = 0;
    _powerOut = 0;
    _ended = false;
    _bumpCaptions = 0;
    _trails.clear();
    _levelIn = 1;
  }

  // ── Update ────────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    _t += dt;
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age >= r.life);
    for (final s in _sparks) {
      s.age += dt;
      s.p += s.v * dt;
      s.v *= math.max(0, 1 - 3 * dt);
    }
    _sparks.removeWhere((s) => s.age >= s.life);
    for (final p in _pops) {
      p.age += dt;
    }
    _pops.removeWhere((p) => p.age >= 0.9);
    final b = _bump;
    if (b != null) {
      b.age += dt;
      if (b.age > 0.7) _bump = null;
    }
    final c = _caption;
    if (c != null) {
      c.age += dt;
      if (c.age > 2.2) _caption = null;
    }
    final rw = _rewind;
    if (rw != null) {
      rw.t += dt;
      if (rw.t >= _Rewind.duration) _rewind = null;
    }
    if (_sweep >= 0) {
      _sweep += dt / 0.6;
      if (_sweep > 1) _sweep = -1;
    }
    _levelIn = math.max(0, _levelIn - dt / 0.35);
    if (_gridlock > 0) _gridlock = math.min(1, _gridlock + dt / 0.5);
    if (_powerOut > 0) _powerOut = math.min(1, _powerOut + dt / 0.8);

    // Engine wakes of the ships in flight (screen px, newest first).
    final live = <int>{};
    for (final f in game.flights) {
      live.add(f.ship.id);
      final tr = _trails.putIfAbsent(f.ship.id, () => []);
      tr.insert(0, f.position);
      if (tr.length > 9) tr.removeLast();
    }
    _trails.removeWhere((k, _) => !live.contains(k));
    _lastBays = [for (final v in game.visBays) v?.ship.id];
  }

  // ── Render ────────────────────────────────────────────────────────────────
  static final _fill = Paint()..isAntiAlias = true;
  static final _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _img = Paint()..filterQuality = FilterQuality.medium;

  Image? _bg;
  Object? _bgKey;

  @override
  void render(Canvas canvas) {
    if (!game.hasLayout || !game.laidOut) return;
    final g = game;
    final key = Object.hash(g.size.x, g.size.y, g.stationRect, g.gateRect, g.hangarRect, g.bayRects.length);
    if (_bg == null || key != _bgKey) {
      _bg?.dispose();
      _bgKey = key;
      final rec = PictureRecorder();
      _paintBackdrop(Canvas(rec), Size(g.size.x, g.size.y), g);
      _bg = rec.endRecording().toImageSync(g.size.x.ceil(), g.size.y.ceil());
    }
    canvas.drawImage(_bg!, Offset.zero, _img);

    _paintBays(canvas);
    _paintQueue(canvas);
    _paintHangar(canvas);
    _paintDepartures(canvas);
    _paintFlights(canvas);
    _paintRewind(canvas);
    _paintHops(canvas);
    _paintEffects(canvas);

    if (_powerOut > 0) {
      _fill.color = const Color(0xFF0A1022).withValues(alpha: 0.42 * _powerOut);
      canvas.drawRect(Offset.zero & Size(g.size.x, g.size.y), _fill);
    }
  }

  /// The static scene: a starfield window, the navy deck, the glass
  /// walkway and gangways, and the hangar floor with ion launch marks.
  static void _paintBackdrop(Canvas c, Size s, StarportGame g) {
    final windowBottom = g.stationRect.bottom + 2;
    _paintSky(c, Rect.fromLTWH(0, 0, s.width, windowBottom));
    // window frame: dark mullions with a hairline
    final mull = Paint()..color = const Color(0xFF050817);
    for (final x in [s.width / 3, s.width * 2 / 3]) {
      c.drawRect(Rect.fromLTWH(x - 2.5, 0, 5, windowBottom), mull);
    }
    // deck
    c.drawRect(
      Rect.fromLTRB(0, windowBottom, s.width, s.height),
      Paint()..shader = Gradient.linear(Offset(0, windowBottom), Offset(0, s.height), const [deck, deckLow]),
    );
    c.drawRect(Rect.fromLTWH(0, windowBottom - 2, s.width, 3), Paint()..color = const Color(0xFF050817));
    c.drawLine(Offset(0, windowBottom + 1), Offset(s.width, windowBottom + 1), Paint()..color = lineStrong);
    // deck plate seams
    final seam = Paint()..color = const Color(0x0FE9EDFF);
    for (var y = windowBottom + 40.0; y < s.height; y += 56) {
      c.drawLine(Offset(0, y), Offset(s.width, y), seam);
    }

    // Walkway (the gate): smoked glass with a hairline and an ion bezel.
    final gate = g.gateRect;
    final gp = _chamfer(gate, 10);
    c.drawPath(gp, Paint()..color = glass);
    c.drawPath(
        gp,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = lineStrong);
    c.drawRect(Rect.fromLTWH(gate.left + 10, gate.top, gate.width * 0.2, 2),
        Paint()..shader = Gradient.linear(Offset(gate.left + 10, 0), Offset(gate.left + 10 + gate.width * 0.2, 0), const [Color(0xFF4DE8FF), Color(0x004DE8FF)]));
    // gate sign at the left end: an ion arch
    final sign = Rect.fromLTWH(gate.left + 6, gate.top + 8, 26, gate.height - 16);
    c.drawPath(_chamfer(sign, 4, all: true), Paint()..color = const Color(0xFF050817));
    final arch = Path()
      ..moveTo(sign.center.dx - 7, sign.center.dy + 9)
      ..lineTo(sign.center.dx - 7, sign.center.dy - 3)
      ..arcToPoint(Offset(sign.center.dx + 7, sign.center.dy - 3), radius: const Radius.circular(7))
      ..lineTo(sign.center.dx + 7, sign.center.dy + 9);
    c.drawPath(
        arch,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xFF4DE8FF));

    // Gangways from the walkway up to each berth.
    for (final b in g.bayRects) {
      final gw = Rect.fromLTRB(b.center.dx - 6, b.bottom, b.center.dx + 6, gate.top + 2);
      c.drawRect(gw, Paint()..color = const Color(0xFF0E1740));
      c.drawLine(gw.topLeft, gw.bottomLeft, Paint()..color = lineStrong);
      c.drawLine(gw.topRight, gw.bottomRight, Paint()..color = lineStrong);
    }

    // Hangar floor, grid and the ion launch marks on every edge cell.
    final h = g.hangarRect;
    final cs = g.cellSize;
    final apron = h.inflate(math.max(8, cs * 0.16));
    c.drawPath(_chamfer(apron, 12), Paint()..color = const Color(0xFF070D26));
    c.drawPath(
        _chamfer(apron, 12),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = lineStrong);
    c.drawRect(h, Paint()..color = floor);
    final gridP = Paint()
      ..color = line
      ..strokeWidth = 1;
    final cols = (h.width / cs).round(), rows = (h.height / cs).round();
    for (var i = 0; i <= cols; i++) {
      c.drawLine(Offset(h.left + i * cs, h.top), Offset(h.left + i * cs, h.bottom), gridP);
    }
    for (var j = 0; j <= rows; j++) {
      c.drawLine(Offset(h.left, h.top + j * cs), Offset(h.right, h.top + j * cs), gridP);
    }
    final dash = Paint()..color = hazard.withValues(alpha: 0.45);
    final dw = cs * 0.34, dt = math.max(2.0, cs * 0.05);
    final gap = (apron.left - h.left).abs();
    for (var i = 0; i < cols; i++) {
      final x = h.left + (i + 0.5) * cs;
      c.drawRect(Rect.fromCenter(center: Offset(x, h.top - gap / 2), width: dw, height: dt), dash);
      c.drawRect(Rect.fromCenter(center: Offset(x, h.bottom + gap / 2), width: dw, height: dt), dash);
    }
    for (var j = 0; j < rows; j++) {
      final y = h.top + (j + 0.5) * cs;
      c.drawRect(Rect.fromCenter(center: Offset(h.left - gap / 2, y), width: dt, height: dw), dash);
      c.drawRect(Rect.fromCenter(center: Offset(h.right + gap / 2, y), width: dt, height: dw), dash);
    }
  }

  /// Space through the station's window: the app's night sky (a deep
  /// gradient, a plasma and an ion haze, stars) over a dark planet limb with
  /// a thin ion atmosphere.
  static void _paintSky(Canvas c, Rect r) {
    c.drawRect(
      r,
      Paint()..shader = Gradient.linear(r.topLeft, r.bottomLeft, const [Color(0xFF050817), Color(0xFF0B1438), Color(0xFF101C4A)], const [0, 0.6, 1]),
    );
    for (final (dx, dy, k, col) in const [(0.2, 0.3, 0.55, Color(0x305B3BD6)), (0.82, 0.55, 0.5, Color(0x281597C9))]) {
      final cc = Offset(r.left + r.width * dx, r.top + r.height * dy);
      c.drawCircle(cc, r.width * k, Paint()..shader = Gradient.radial(cc, r.width * k, [col, col.withValues(alpha: 0)], const [0, 1]));
    }
    final rnd = math.Random(5);
    final star = Paint();
    for (var i = 0; i < 70; i++) {
      star.color = Color.fromRGBO(233, 237, 255, 0.25 + rnd.nextDouble() * 0.6);
      c.drawCircle(Offset(r.left + rnd.nextDouble() * r.width, r.top + rnd.nextDouble() * r.height * 0.85), 0.4 + rnd.nextDouble() * 0.8, star);
    }
    final pc = Offset(r.center.dx, r.bottom + r.width * 2.2);
    final pr = r.width * 2.38;
    c.drawCircle(pc, pr, Paint()..color = const Color(0xFF081032));
    c.drawCircle(
        pc,
        pr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0x994DE8FF));
    c.drawCircle(
        pc,
        pr + 3,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0x1A4DE8FF));
  }

  // ── Bays ──────────────────────────────────────────────────────────────────
  void _paintBays(Canvas canvas) {
    final g = game;
    final pulse = g.noBayPulse;
    for (var i = 0; i < g.bayRects.length; i++) {
      final r = g.bayRects[i];
      final bay = i < g.visBays.length ? g.visBays[i] : null;
      final cut = math.min(10.0, r.width * 0.16);
      final berth = _chamfer(r, cut);
      _fill.color = glass;
      canvas.drawPath(berth, _fill);
      var edge = lineStrong;
      if (pulse > 0) edge = Color.lerp(line, hazard, pulse)!;
      if (_gridlock > 0) edge = Color.lerp(edge, flare, _gridlock)!;
      _stroke
        ..strokeWidth = _gridlock > 0 || pulse > 0 ? 2 : 1
        ..color = edge;
      canvas.drawPath(berth, _stroke);
      // the docking clamp strip and the number
      _fill.color = bay == null && !_ended ? hazard.withValues(alpha: 0.7) : const Color(0x33E9EDFF);
      canvas.drawRect(Rect.fromLTWH(r.left + 8, r.bottom - 6, r.width - 16, 2), _fill);
      _label(canvas, '${i + 1}', Offset(r.left + 6, r.top + 4), 11, muted, bold: true);
      if (_gridlock > 0) {
        _fill.color = flare.withValues(alpha: 0.10 * _gridlock);
        canvas.drawPath(berth, _fill);
      }
      if (bay == null) {
        if (!_ended) {
          Glow.draw(canvas, r.center, r.width * 0.55, const Color(0xFF4DE8FF).withValues(alpha: 0.28 + 0.06 * math.sin(_t * 2.4 + i)));
          _labelCentered(canvas, 'Free', r.center + const Offset(0, 2), 12, blue);
        }
        continue;
      }
      final s = 1 + 0.12 * bay.pop;
      final (len, wid) = _dockSize(r, bay.ship);
      paintShip(canvas, r.center + const Offset(0, -3), -math.pi / 2, len * s, wid * s, bay.ship.color, kind: bay.ship.kind);
      _seatPips(canvas, r, bay.ship.seats, bay.filled, bay.ship.color);
    }
  }

  /// A docked ship's size in a berth (nose-up).
  (double, double) _dockSize(Rect r, StarShip ship) {
    final wid = math.min(r.width * 0.36, r.height * 0.3);
    final len = math.min(r.height * (ship.kind == ShipKind.liner ? 0.74 : 0.58), wid * (ship.kind == ShipKind.liner ? 3.0 : 2.1));
    return (len, wid);
  }

  void _seatPips(Canvas canvas, Rect r, int seats, int filled, int color) {
    final col = colorOf(color);
    final d = math.min(6.0, (r.width - 14) / seats - 2);
    final x0 = r.center.dx - (seats * (d + 2) - 2) / 2 + d / 2;
    final y = r.bottom - 13;
    for (var k = 0; k < seats; k++) {
      final c = Offset(x0 + k * (d + 2), y);
      _fill.color = k < filled ? col : const Color(0x33E9EDFF);
      canvas.drawCircle(c, d / 2, _fill);
      if (k < filled) Glow.draw(canvas, c, d * 1.4, col.withValues(alpha: 0.5));
    }
  }

  // ── Queue ─────────────────────────────────────────────────────────────────
  void _paintQueue(Canvas canvas) {
    final g = game;
    final slide = g.queueSlide * g.queueStep;
    final shown = math.min(g.visQueue.length, StarportGame.queueVisible);
    final size = g.queueTokenSize;
    for (var i = shown - 1; i >= 0; i--) {
      final c = g.queueTokenCenter(i) + Offset(slide, 0);
      final front = i == 0;
      // a little step bounce while the line shuffles up
      final bob = g.queueSlide > 0 && !_reduce ? -math.sin(math.pi * (1 - g.queueSlide)) * 2 : 0.0;
      if (front) {
        Glow.draw(canvas, c, size * 0.9, const Color(0xFF4DE8FF).withValues(alpha: 0.35 + 0.1 * math.sin(_t * 3)));
        _stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF4DE8FF);
        canvas.drawCircle(c, size * 0.62, _stroke);
      }
      paintPassenger(canvas, c + Offset(0, bob), size * (front ? 0.95 : 0.85), g.visQueue[i]);
    }
    if (g.queueOverflow > 0) {
      final r = Rect.fromLTWH(g.queueRect.right + 6, g.gateRect.top + 13, g.gateRect.right - g.queueRect.right - 12, g.gateRect.height - 26);
      _fill.color = const Color(0xFF050817);
      canvas.drawPath(_chamfer(r, 5, all: true), _fill);
      _stroke
        ..strokeWidth = 1
        ..color = lineStrong;
      canvas.drawPath(_chamfer(r, 5, all: true), _stroke);
      _labelCentered(canvas, '+${g.queueOverflow}', r.center, 13, ink2, bold: true);
    }
  }

  /// A passenger: a rounded figure in their color with the color's
  /// symbol on a white badge. [size] is the token's height in px.
  static void paintPassenger(Canvas canvas, Offset c, double size, int color) {
    final col = colorOf(color);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, size * 0.16), width: size * 0.58, height: size * 0.56), Radius.circular(size * 0.24));
    _fill.color = Color.lerp(col, const Color(0xFF0A1130), 0.3)!;
    canvas.drawRRect(body, _fill);
    _stroke
      ..strokeWidth = 1
      ..color = col;
    canvas.drawRRect(body, _stroke);
    final head = c + Offset(0, -size * 0.27);
    _fill.color = col;
    canvas.drawCircle(head, size * 0.19, _fill);
    final badge = c + Offset(0, size * 0.18);
    _fill.color = const Color(0xFF050817);
    canvas.drawCircle(badge, size * 0.17, _fill);
    paintSymbol(canvas, badge, size * 0.1, color);
  }

  // ── Hangar ────────────────────────────────────────────────────────────────
  void _paintHangar(Canvas canvas) {
    final g = game;
    final hidden = _rewind?.ship.id;
    final settle = _reduce ? 0.0 : _levelIn;
    for (final s in g.visParked) {
      if (s.id == hidden) continue;
      var rect = g.shipRect(s).shift(g.bumpOffset(s));
      final glow = g.blockerGlow(s.id);
      if (glow > 0 && !_reduce) rect = rect.shift(Offset(math.sin(_t * 70) * 1.6 * glow, 0));
      final len = (s.facing.horizontal ? rect.width : rect.height) - g.cellSize * 0.12;
      final wid = (s.facing.horizontal ? rect.height : rect.width) * 0.66;
      final c = rect.center + Offset(0, -settle * g.cellSize * 0.4);
      if (glow > 0) {
        final o = RRect.fromRectAndRadius(rect.deflate(2), Radius.circular(g.cellSize * 0.22));
        _stroke
          ..strokeWidth = 3
          ..color = flare.withValues(alpha: glow);
        canvas.drawRRect(o, _stroke);
        _fill.color = flare.withValues(alpha: 0.08 * glow);
        canvas.drawRRect(o, _fill);
      }
      paintShip(canvas, c, facingAngle(s.facing), len, wid, s.color, kind: s.kind, alpha: 1 - settle);
    }
    // The bump: a flare "!" at the nose of the ship that couldn't get out.
    final b = _bump;
    if (b != null) {
      final s = b.ship;
      final rect = g.shipRect(s);
      final nose = rect.center + Offset(s.facing.dc * (rect.width / 2), s.facing.dr * (rect.height / 2));
      final k = (1 - b.age / 0.7).clamp(0.0, 1.0);
      final r = g.cellSize * 0.18;
      _fill.color = flare.withValues(alpha: k);
      canvas.drawCircle(nose, r, _fill);
      _labelCentered(canvas, '!', nose + const Offset(0, -0.5), r * 1.5, const Color(0xFFFFFFFF).withValues(alpha: k), bold: true);
    }
    // Level clear: an ion light sweeps the empty hangar.
    if (_sweep >= 0) {
      final h = g.hangarRect;
      final x = h.left - h.width * 0.3 + (h.width * 1.6) * _sweep;
      canvas.save();
      canvas.clipRect(h);
      canvas.drawRect(
        Rect.fromLTRB(x - h.width * 0.25, h.top, x + h.width * 0.05, h.bottom),
        Paint()
          ..shader = Gradient.linear(Offset(x - h.width * 0.25, 0), Offset(x + h.width * 0.05, 0), const [Color(0x004DE8FF), Color(0x554DE8FF), Color(0x004DE8FF)], const [0, 0.8, 1]),
      );
      canvas.restore();
    }
    final cap = _caption;
    if (cap != null) {
      final k = cap.age < 0.2 ? cap.age / 0.2 : (cap.age > 1.8 ? (2.2 - cap.age) / 0.4 : 1.0);
      _captionChip(canvas, cap.text, Offset(g.hangarRect.center.dx, g.hangarRect.bottom - g.cellSize * 0.5), k.clamp(0.0, 1.0));
    }
  }

  void _captionChip(Canvas canvas, String text, Offset center, double alpha) {
    final p = _para(text, 13, const Color(0xFFFFFFFF), bold: true);
    final w = p.maxIntrinsicWidth + 24, h = 28.0;
    final r = Rect.fromCenter(center: center, width: w, height: h);
    _fill.color = const Color(0xF0050817).withValues(alpha: 0.94 * alpha);
    canvas.drawPath(_chamfer(r, 7, all: true), _fill);
    _stroke
      ..strokeWidth = 1
      ..color = flare.withValues(alpha: 0.6 * alpha);
    canvas.drawPath(_chamfer(r, 7, all: true), _stroke);
    canvas.save();
    canvas.translate(0, 0);
    final pp = _para(text, 13, const Color(0xFFFFFFFF).withValues(alpha: alpha), bold: true);
    canvas.drawParagraph(pp, Offset(r.left + 12, r.center.dy - pp.height / 2));
    canvas.restore();
  }

  // ── Flights, departures, rewind, hops ─────────────────────────────────────
  void _paintFlights(Canvas canvas) {
    final g = game;
    for (final f in g.flights) {
      final tr = _trails[f.ship.id];
      if (tr != null && tr.length > 1 && !_reduce) {
        for (var i = 1; i < tr.length; i++) {
          final k = 1 - i / tr.length;
          _stroke
            ..strokeWidth = g.cellSize * 0.28 * k
            ..color = const Color(0xFF7FE4FF).withValues(alpha: 0.45 * k);
          canvas.drawLine(tr[i - 1], tr[i], _stroke);
        }
      }
      // Ease into the berth's nose-up pose and size over the last third.
      final p = f.progress;
      final k = ((p - 0.66) / 0.34).clamp(0.0, 1.0);
      final bay = _bayOf(f);
      final hangLen = f.ship.length * g.cellSize - g.cellSize * 0.12;
      final hangWid = g.cellSize * 0.66;
      var len = hangLen * (1 - 0.4 * p), wid = hangWid * (1 - 0.4 * p);
      var angle = f.angle;
      if (bay != null) {
        final (dl, dw) = _dockSize(bay, f.ship);
        len = _lerp(len, dl, k);
        wid = _lerp(wid, dw, k);
        angle = _lerpAngle(angle, -math.pi / 2, k);
      }
      Glow.draw(canvas, f.position, g.cellSize * 0.9, const Color(0xFF7FE4FF).withValues(alpha: 0.25));
      paintShip(canvas, f.position, angle, len, wid, f.ship.color, kind: f.ship.kind, lift: 1);
    }
  }

  Rect? _bayOf(FlyingShip f) {
    final end = f.path.last;
    for (final r in game.bayRects) {
      if ((r.center - end).distance < 1) return r;
    }
    return null;
  }

  void _paintDepartures(Canvas canvas) {
    final g = game;
    for (final d in g.departures) {
      final k = d.progress * d.progress;
      final r = d.bayRect;
      final start = r.center + const Offset(0, -3);
      final c = start + Offset(0, -k * (r.bottom + g.cellSize));
      // contrail
      if (!_reduce) {
        _stroke
          ..strokeWidth = r.width * 0.18
          ..color = const Color(0xFFBFF3FF).withValues(alpha: 0.45 * (1 - d.progress * 0.6));
        canvas.drawLine(start + Offset(0, r.height * 0.2), c, _stroke);
      }
      Glow.draw(canvas, c + Offset(0, r.height * 0.3), r.width * 0.5, const Color(0xFF7FE4FF).withValues(alpha: 0.6 * (1 - d.progress)));
      final (len, wid) = _dockSize(r, d.ship);
      paintShip(canvas, c, -math.pi / 2, len * (1 + 0.15 * k), wid * (1 + 0.15 * k), d.ship.color, kind: d.ship.kind, lift: 1, alpha: 1 - d.progress * 0.5);
    }
  }

  void _paintRewind(Canvas canvas) {
    final rw = _rewind;
    if (rw == null) return;
    final g = game;
    final x = (rw.t / _Rewind.duration).clamp(0.0, 1.0);
    final p = x * x * (3 - 2 * x);
    final (pos, _) = _along(rw.path, p);
    final rect = g.shipRect(rw.ship);
    final len = (rw.ship.facing.horizontal ? rect.width : rect.height) - g.cellSize * 0.12;
    final wid = (rw.ship.facing.horizontal ? rect.height : rect.width) * 0.66;
    // It backs in: the nose keeps pointing the way it will leave.
    final a = _lerpAngle(-math.pi / 2, facingAngle(rw.ship.facing), (p * 1.6).clamp(0.0, 1.0));
    final s = 0.6 + 0.4 * p;
    Glow.draw(canvas, pos, g.cellSize, blue.withValues(alpha: 0.25 * (1 - p)));
    paintShip(canvas, pos, a, len * s, wid * s, rw.ship.color, kind: rw.ship.kind, lift: 1 - p);
  }

  void _paintHops(Canvas canvas) {
    final g = game;
    for (final h in g.hops) {
      final k = h.progress * h.progress;
      final p = Offset.lerp(h.from, h.to, k)!;
      final lift = math.sin(math.pi * h.progress) * g.queueTokenSize * 0.6;
      paintPassenger(canvas, p - Offset(0, lift), g.queueTokenSize * (0.9 - 0.35 * k), h.color);
    }
  }

  void _paintEffects(Canvas canvas) {
    for (final r in _rings) {
      final f = r.age / r.life;
      _stroke
        ..strokeWidth = 2.2 * (1 - f) + 0.6
        ..color = r.color.withValues(alpha: 0.75 * (1 - f));
      canvas.drawCircle(r.c, r.r0 + (r.r1 - r.r0) * (1 - (1 - f) * (1 - f)), _stroke);
    }
    for (final s in _sparks) {
      final f = s.age / s.life;
      _fill.color = s.color.withValues(alpha: 1 - f);
      canvas.drawCircle(s.p, 2.2 * (1 - f) + 0.8, _fill);
    }
    for (final p in _pops) {
      final f = p.age / 0.9;
      final c = p.at + Offset(0, -f * 22);
      final r = Rect.fromCenter(center: c, width: 30, height: 20);
      _fill.color = p.color.withValues(alpha: 1 - f * f);
      canvas.drawPath(_chamfer(r, 5, all: true), _fill);
      _labelCentered(canvas, p.text, c, 13, const Color(0xFF050817).withValues(alpha: 1 - f * f), bold: true);
    }
  }

  // ── Ships and symbols (shared with the hub preview) ───────────────────────

  /// A top-down ship centered at [c], pointing along [angle] (0 = right),
  /// [len] x [wid] px, in color [color]. The nose and canopy are the only
  /// arrow; the roof symbol is drawn screen-upright. [lift] 0..1 raises it
  /// (bigger, softer shadow).
  static void paintShip(Canvas canvas, Offset c, double angle, double len, double wid, int color,
      {ShipKind kind = ShipKind.shuttle, double lift = 0, double alpha = 1}) {
    if (alpha <= 0) return;
    final col = colorOf(color);
    final body = Color.lerp(col, const Color(0xFF0A1130), 0.42)!;
    final dark = Color.lerp(col, const Color(0xFF050817), 0.62)!;
    final noseLen = math.min(wid * 0.7, len * 0.32);
    final halfL = len / 2, halfW = wid / 2;
    // shadow
    canvas.save();
    canvas.translate(c.dx + 2 + lift * 4, c.dy + 3 + lift * 7);
    canvas.rotate(angle);
    _fill.color = const Color(0xFF000000).withValues(alpha: (0.38 - lift * 0.12) * alpha);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(-halfL, -halfW, halfL - noseLen * 0.4, halfW), Radius.circular(halfW * 0.9)), _fill);
    canvas.restore();

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    // fins at the tail
    _fill.color = dark.withValues(alpha: alpha);
    canvas.drawPath(
      Path()
        ..moveTo(-halfL + 2, -halfW)
        ..lineTo(-halfL - wid * 0.08, -halfW - wid * 0.18)
        ..lineTo(-halfL + wid * 0.55, -halfW)
        ..close(),
      _fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-halfL + 2, halfW)
        ..lineTo(-halfL - wid * 0.08, halfW + wid * 0.18)
        ..lineTo(-halfL + wid * 0.55, halfW)
        ..close(),
      _fill,
    );
    // hull with a pointed nose
    final hull = Path()
      ..moveTo(-halfL + halfW * 0.6, -halfW)
      ..lineTo(halfL - noseLen, -halfW)
      ..quadraticBezierTo(halfL - noseLen * 0.25, -halfW * 0.7, halfL, 0)
      ..quadraticBezierTo(halfL - noseLen * 0.25, halfW * 0.7, halfL - noseLen, halfW)
      ..lineTo(-halfL + halfW * 0.6, halfW)
      ..quadraticBezierTo(-halfL, halfW, -halfL, halfW * 0.4)
      ..lineTo(-halfL, -halfW * 0.4)
      ..quadraticBezierTo(-halfL, -halfW, -halfL + halfW * 0.6, -halfW)
      ..close();
    _fill.color = body.withValues(alpha: alpha);
    canvas.drawPath(hull, _fill);
    // the luminous rim: the color you read at a glance
    _stroke
      ..strokeWidth = math.max(1.4, wid * 0.07)
      ..color = col.withValues(alpha: alpha);
    canvas.drawPath(hull, _stroke);
    // a lit panel line along one side
    _fill.color = col.withValues(alpha: 0.45 * alpha);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(-halfL + wid * 0.3, -halfW + wid * 0.12, halfL - noseLen * 1.1, -halfW + wid * 0.24), Radius.circular(wid * 0.06)),
        _fill);
    // canopy at the nose
    _fill.color = const Color(0xFFBFF3FF).withValues(alpha: 0.85 * alpha);
    canvas.drawPath(
      Path()
        ..moveTo(halfL - noseLen * 1.15, -halfW * 0.5)
        ..lineTo(halfL - noseLen * 0.55, -halfW * 0.34)
        ..quadraticBezierTo(halfL - noseLen * 0.2, 0, halfL - noseLen * 0.55, halfW * 0.34)
        ..lineTo(halfL - noseLen * 1.15, halfW * 0.5)
        ..close(),
      _fill,
    );
    // nozzle
    _fill.color = const Color(0xFF050817).withValues(alpha: alpha);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-halfL - wid * 0.07, -halfW * 0.45, wid * 0.12, wid * 0.45), Radius.circular(wid * 0.04)), _fill);
    if (lift > 0.3) {
      Glow.draw(canvas, Offset(-halfL - wid * 0.2, 0), wid * 0.6, const Color(0xFF7FE4FF).withValues(alpha: 0.7 * lift * alpha), hot: true);
    }
    // the roof disc
    final along = kind == ShipKind.liner ? -len * 0.08 : -len * 0.05;
    _fill.color = const Color(0xFF050817).withValues(alpha: alpha);
    final discR = wid * 0.3;
    canvas.drawCircle(Offset(along, 0), discR, _fill);
    _stroke
      ..strokeWidth = 1
      ..color = col.withValues(alpha: 0.5 * alpha);
    canvas.drawCircle(Offset(along, 0), discR, _stroke);
    canvas.restore();
    // the symbol, upright on screen, glowing like the rest of the energy
    final disc = c + Offset(math.cos(angle) * along, math.sin(angle) * along);
    Glow.draw(canvas, disc, discR * 1.6, col.withValues(alpha: 0.35 * alpha));
    paintSymbol(canvas, disc, discR * 0.58, color, alpha: alpha);
  }

  /// The color's symbol centered at [c], radius [s] px.
  static void paintSymbol(Canvas canvas, Offset c, double s, int color, {double alpha = 1}) {
    final i = color % palette.length;
    _fill.color = palette[i].withValues(alpha: alpha);
    switch (i) {
      case 0: // circle
        canvas.drawCircle(c, s * 0.8, _fill);
      case 1: // star
        final p = Path();
        for (var k = 0; k < 10; k++) {
          final a = -math.pi / 2 + k * math.pi / 5;
          final r = k.isEven ? s : s * 0.45;
          final q = c + Offset(math.cos(a) * r, math.sin(a) * r);
          k == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(p..close(), _fill);
      case 2: // square
        canvas.drawRect(Rect.fromCenter(center: c, width: s * 1.4, height: s * 1.4), _fill);
      case 3: // diamond
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - s)
            ..lineTo(c.dx + s * 0.85, c.dy)
            ..lineTo(c.dx, c.dy + s)
            ..lineTo(c.dx - s * 0.85, c.dy)
            ..close(),
          _fill,
        );
      case 4: // hexagon
        final p = Path();
        for (var k = 0; k < 6; k++) {
          final a = k * math.pi / 3;
          final q = c + Offset(math.cos(a) * s * 0.92, math.sin(a) * s * 0.92);
          k == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
        }
        canvas.drawPath(p..close(), _fill);
      default: // cross
        final w = s * 0.36;
        canvas.drawRect(Rect.fromCenter(center: c, width: s * 1.7, height: w * 2), _fill);
        canvas.drawRect(Rect.fromCenter(center: c, width: w * 2, height: s * 1.7), _fill);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static Path _chamfer(Rect r, double cut, {bool all = false}) {
    final p = Path()..moveTo(r.left + cut, r.top);
    p.lineTo(r.right - (all ? cut : 0), r.top);
    if (all) p.lineTo(r.right, r.top + cut);
    p.lineTo(r.right, r.bottom - cut);
    p.lineTo(r.right - cut, r.bottom);
    p.lineTo(r.left + (all ? cut : 0), r.bottom);
    if (all) p.lineTo(r.left, r.bottom - cut);
    p.lineTo(r.left, r.top + cut);
    return p..close();
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static double _lerpAngle(double a, double b, double t) {
    var d = (b - a) % (math.pi * 2);
    if (d > math.pi) d -= math.pi * 2;
    if (d < -math.pi) d += math.pi * 2;
    return a + d * t;
  }

  static (Offset, double) _along(List<Offset> path, double p) {
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

  // Text: paragraphs cached by content, size, color and weight.
  static final _paras = <String, Paragraph>{};

  static Paragraph _para(String text, double size, Color color, {bool bold = false}) {
    final key = '$text|$size|${color.toARGB32()}|$bold';
    final hit = _paras[key];
    if (hit != null) return hit;
    if (_paras.length > 200) _paras.clear();
    final b = ParagraphBuilder(ParagraphStyle(fontFamily: NbFonts.ui, fontSize: size))
      ..pushStyle(TextStyle(color: color, fontSize: size, fontFamily: NbFonts.ui, fontWeight: bold ? FontWeight.w700 : FontWeight.w600))
      ..addText(text);
    final p = b.build()..layout(const ParagraphConstraints(width: 400));
    return _paras[key] = p;
  }

  static void _label(Canvas canvas, String text, Offset topLeft, double size, Color color, {bool bold = false}) {
    canvas.drawParagraph(_para(text, size, color, bold: bold), topLeft);
  }

  static void _labelCentered(Canvas canvas, String text, Offset center, double size, Color color, {bool bold = false}) {
    final p = _para(text, size, color, bold: bold);
    canvas.drawParagraph(p, center - Offset(p.maxIntrinsicWidth / 2, p.height / 2));
  }

  // ── Hub preview ───────────────────────────────────────────────────────────

  /// The arcade hub card: a bright slice of the station. Three berths under
  /// the window, a little jam in the hangar, and every 3 s one shuttle slides
  /// out, flies up to a berth and a passenger steps aboard.
  static void paintPreview(Canvas canvas, Size s, double t) {
    final win = Rect.fromLTWH(0, 0, s.width, s.height * 0.42);
    _paintSky(canvas, win);
    canvas.drawRect(Rect.fromLTRB(0, win.bottom, s.width, s.height), Paint()..color = deck);
    canvas.drawRect(Rect.fromLTWH(0, win.bottom - 2, s.width, 3), Paint()..color = const Color(0xFF050817));
    // three berths
    final bw = s.width * 0.17, bh = win.height * 0.72;
    final cycle = (t % 3.0) / 3.0;
    final berths = <Rect>[for (var i = 0; i < 3; i++) Rect.fromLTWH(s.width * (0.06 + i * 0.2), win.bottom - bh - 4, bw, bh)];
    for (var i = 0; i < 3; i++) {
      final r = berths[i];
      _fill.color = glass;
      canvas.drawPath(_chamfer(r, 6), _fill);
      _stroke
        ..strokeWidth = 1
        ..color = lineStrong;
      canvas.drawPath(_chamfer(r, 6), _stroke);
      _fill.color = hazard;
      canvas.drawRect(Rect.fromLTWH(r.left + 5, r.bottom - 5, r.width - 10, 2), _fill);
    }
    final wid = bw * 0.36;
    paintShip(canvas, berths[0].center, -math.pi / 2, wid * 2.1, wid, 0);
    paintShip(canvas, berths[1].center, -math.pi / 2, wid * 2.1, wid, 2);
    // hangar slice on the right
    final cell = s.height * 0.22;
    final h = Rect.fromLTWH(s.width * 0.64, s.height * 0.12, cell * 3, cell * 3.6);
    canvas.drawRect(h.inflate(4), Paint()..color = const Color(0xFF070D26));
    canvas.drawRect(h, Paint()..color = floor);
    final gp = Paint()..color = line;
    for (var i = 0; i <= 3; i++) {
      canvas.drawLine(Offset(h.left + i * cell, h.top), Offset(h.left + i * cell, h.bottom), gp);
    }
    final cw = cell * 0.66, cl = cell * 1.88;
    paintShip(canvas, Offset(h.left + cell, h.top + cell * 0.5), math.pi, cl, cw, 4);
    paintShip(canvas, Offset(h.left + cell * 2.5, h.top + cell), math.pi / 2, cl, cw, 5);
    paintShip(canvas, Offset(h.left + cell * 0.5, h.top + cell * 2), -math.pi / 2, cl, cw, 1);
    paintShip(canvas, Offset(h.left + cell * 2, h.top + cell * 3.1), 0, cl, cw, 3);
    // the launch: an amber shuttle slides up out of the slice and arcs to berth 3
    final start = Offset(h.left + cell * 1.5, h.top + cell * 2.2);
    final out = Offset(h.left + cell * 1.5, h.top - cell * 0.6);
    final end = berths[2].center;
    final p = (cycle / 0.45).clamp(0.0, 1.0);
    final e = p * p * (3 - 2 * p);
    final pos = e < 0.5 ? Offset.lerp(start, out, e * 2)! : Offset.lerp(out, end, (e - 0.5) * 2)!;
    final dir = e < 0.5 ? -math.pi / 2 : math.atan2(end.dy - out.dy, end.dx - out.dx);
    final k = ((e - 0.6) / 0.4).clamp(0.0, 1.0);
    final ang = _lerpAngle(dir, -math.pi / 2, k);
    if (p > 0 && p < 1) Glow.draw(canvas, pos, cell * 0.7, const Color(0xFF7FE4FF).withValues(alpha: 0.35));
    paintShip(canvas, pos, ang, _lerp(cl, wid * 2.1, e), _lerp(cw, wid, e), 1, lift: p < 1 ? 1 : 0);
    // a passenger walks to berth 3 once it has docked
    final w = ((cycle - 0.55) / 0.3).clamp(0.0, 1.0);
    if (w > 0 && w < 1) {
      final from = Offset(berths[2].center.dx, s.height * 0.86);
      final pp = Offset.lerp(from, berths[2].center, w * w)! - Offset(0, math.sin(math.pi * w) * 6);
      paintPassenger(canvas, pp, s.height * 0.16 * (1 - 0.3 * w), 1);
    }
    // the queue along the bottom left
    for (var i = 0; i < 5; i++) {
      paintPassenger(canvas, Offset(s.width * (0.08 + i * 0.1), s.height * 0.84), s.height * 0.15, [1, 0, 3, 2, 4][i]);
    }
  }
}

class _Ring {
  final Offset c;
  final double r0, r1, life;
  final Color color;
  double age = 0;
  _Ring(this.c, this.r0, this.r1, this.life, this.color);
}

class _Spark {
  Offset p, v;
  final double life;
  final Color color;
  double age = 0;
  _Spark(this.p, this.v, this.life, this.color);
}

class _Pop {
  final String text;
  final Offset at;
  final Color color;
  double age;
  _Pop(this.text, this.at, this.color, this.age);
}

class _BumpMark {
  final StarShip ship;
  double age;
  _BumpMark(this.ship, this.age);
}

class _Caption {
  final String text;
  double age;
  _Caption(this.text, this.age);
}

class _Rewind {
  static const double duration = 0.32;
  final StarShip ship;
  final List<Offset> path;
  double t;
  _Rewind(this.ship, this.path, this.t);
}
