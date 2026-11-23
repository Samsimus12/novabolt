import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../../cosmetics/catalog.dart';
import '../../game/fx/glow.dart';
import '../../game/render/explosion_art.dart';
import '../../game/render/ship_art.dart';
import '../arcade_manager.dart';
import '../thread/thread_art.dart';
import 'assault_enemies.dart';
import 'assault_sim.dart';
import 'assault_types.dart';
import 'assault_weapons.dart';

/// Ground Assault's drawing (the designer's file). The contract with
/// [AssaultGame]:
///   * `AssaultArt(AssaultSim sim)` is one Flame [Component] added to the game.
///   * `sim` is a public field (assignable if the game ever rebuilds the sim).
///   * `layout({required Rect viewRect, required double tilePx})` is called
///     on load and on every resize. Everything is drawn inside [viewRect]
///     (the top of the screen, full width, 13 tiles tall), clipped to it.
///   * `onEvent(AssaultEvent)` is called for every sim event after the step;
///     `onRestart()` when "play again" is hit.
///   * Read-only access to the sim each frame. World -> screen:
///     `viewRect.left + (x - cameraX) * tilePx`, `viewRect.top + y * tilePx`.
///
/// Look ("dusk planet"): a baked violet-to-wine sky with a ringed gas giant,
/// two parallax ridges (cached pictures), basalt ground with a sunset-lit
/// lip on every walkable top, salvaged hull-plate platforms, flare crystal
/// spikes. Colour keeps the app's meanings: flare = what hurts you, ion =
/// you, gold = NOVA, plasma = upgrades. The pilot wears the equipped ship's
/// colours; the exit is the equipped ship; explosions use the equipped
/// explosion style. Characters are drawn in a 40-units-per-tile design space.
class AssaultArt extends Component {
  AssaultSim sim;
  AssaultArt(this.sim);

  Rect _view = Rect.zero;
  double _tp = 0;

  double _t = 0; // seconds, always running
  final _rng = math.Random();

  // ── Effects ─────────────────────────────────────────────────────────────
  final _bursts = <_Burst>[];
  final _parts = <_Part>[];
  final _rings = <_Ring>[];
  final _pops = <_Pop>[];
  final _beaconLit = <int, double>{}; // checkpoint index → seconds since lit
  double _shake = 0;
  double _hurt = 0; // red edge wash, 1 → 0
  double _muzzle = 0;
  double _runPhase = 0;
  double _bossFlash = 0;
  double _lastPilotX = 0;

  // ── Cached per-size assets ──────────────────────────────────────────────
  Image? _sky;
  Size _skySize = Size.zero;
  Picture? _far;
  Picture? _near;
  double _ridgeW = 1;
  List<Rect> _edgeRects = const [];
  List<Shader> _edgeShaders = const [];

  void layout({required Rect viewRect, required double tilePx}) {
    final resized = viewRect != _view || tilePx != _tp;
    _view = viewRect;
    _tp = tilePx;
    if (resized && viewRect.width > 0) _bake();
  }

  void _bake() {
    _sky?.dispose();
    final s = _view.size;
    final rec = PictureRecorder();
    paintSky(Canvas(rec), s);
    _sky = rec.endRecording().toImageSync(s.width.ceil(), s.height.ceil());
    _skySize = s;
    _ridgeW = s.width * 1.6;
    final e = _tp * 1.6;
    final v = _view;
    const on = Color(0x66FF4766), off = Color(0x00FF4766);
    _edgeRects = [
      Rect.fromLTWH(v.left, v.top, v.width, e),
      Rect.fromLTWH(v.left, v.bottom - e, v.width, e),
      Rect.fromLTWH(v.left, v.top, e, v.height),
      Rect.fromLTWH(v.right - e, v.top, e, v.height),
    ];
    _edgeShaders = [
      Gradient.linear(v.topLeft, v.topLeft.translate(0, e), [on, off]),
      Gradient.linear(v.bottomLeft, v.bottomLeft.translate(0, -e), [on, off]),
      Gradient.linear(v.topLeft, v.topLeft.translate(e, 0), [on, off]),
      Gradient.linear(v.topRight, v.topRight.translate(-e, 0), [on, off]),
    ];
    _far = _ridgePicture(s, _ridgeW, s.height * 0.69, s.height * 0.11, s.width / 11, const Color(0xFF2B1638), 3, false);
    _near = _ridgePicture(s, _ridgeW, s.height * 0.775, s.height * 0.075, s.width / 18, const Color(0xFF1C1029), 8, true);
  }

  void onEvent(AssaultEvent e) {
    final x = e.x, y = e.y;
    switch (e.kind) {
      case AssaultEventKind.jump:
        _dust(x, y, 5);
      case AssaultEventKind.land:
        _dust(x, y, 6);
      case AssaultEventKind.shoot:
        _muzzle = 0.07;
      case AssaultEventKind.enemyHit:
        for (var i = 0; i < 4; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          _parts.add(_Part(x, y, math.cos(a) * 5, math.sin(a) * 5, 0.22, 0.06, const Color(0xFFFFE6C4), hot: true));
        }
      case AssaultEventKind.enemyKilled:
        final boss = e.detail == 'boss';
        _bursts.add(_Burst(x, y, _style(), boss ? 1.4 : (e.detail == 'turret' ? 0.7 : 0.55), big: boss));
        _shake = math.max(_shake, boss ? 1.0 : 0.25);
        _debris(x, y, boss ? 18 : 6, const Color(0xFF5B2C6B));
      case AssaultEventKind.explosion:
        final r = double.tryParse(e.detail ?? '') ?? 1.2;
        _bursts.add(_Burst(x, y, ExplosionStyle.standard, r * 0.55));
        _rings.add(_Ring(x, y, const Color(0xFFFF9A4A), 0.4, 0.2, r));
        _shake = math.max(_shake, math.min(0.6, 0.18 * r));
      case AssaultEventKind.pilotHurt:
        _hurt = 1;
        _shake = math.max(_shake, 0.35);
      case AssaultEventKind.lifeLost:
        _bursts.add(_Burst(x, y, _style(), 0.7));
        _debris(x, y, 10, _palette.hull);
        _hurt = 1;
        _shake = 0.7;
      case AssaultEventKind.respawn:
        _rings.add(_Ring(x, y - 0.7, _ion, 0.5, 0.3, 1.6));
        _parts.add(_Part(x, y - 0.7, 0, 0, 0.35, 0.9, _ion, hot: true));
      case AssaultEventKind.pickupWeapon:
        _rings.add(_Ring(x, y, _plasma, 0.45, 0.2, 1.4));
        _sparks(x, y, 12, _plasma);
        _pops.add(_Pop(x, y - 0.6, _weaponName(e.detail), _plasma));
      case AssaultEventKind.pickupShard:
        _rings.add(_Ring(x, y, _gold, 0.4, 0.15, 0.9));
        _sparks(x, y, 12, _gold);
        _pops.add(_Pop(x, y - 0.5, '+${ArcadeManager.coinsPerBonus}', _gold));
      case AssaultEventKind.checkpoint:
        final i = sim.checkpoints.indexWhere((k) => (k.x - x).abs() < 0.6);
        if (i >= 0) _beaconLit[i] = 0;
        _rings.add(_Ring(x, y - 1.2, _ion, 0.6, 0.2, 2.2));
        _pops.add(_Pop(x, y - 2.6, 'Checkpoint', _ion));
      case AssaultEventKind.bossStart:
        _shake = 0.6;
        _bossFlash = 1;
      case AssaultEventKind.bossDown:
        _shake = 1;
        _bossFlash = 1;
      case AssaultEventKind.cleared:
        _rings.add(_Ring(x, y - 1, _ion, 0.7, 0.4, 3));
      case AssaultEventKind.gameOver:
        break;
    }
  }

  void onRestart() {
    _bursts.clear();
    _parts.clear();
    _rings.clear();
    _pops.clear();
    _beaconLit.clear();
    _shake = 0;
    _hurt = 0;
    _bossFlash = 0;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────
  static const _ion = Color(0xFF4DE8FF);
  static const _gold = Color(0xFFFFC23D);
  static const _plasma = Color(0xFFA07CFF);
  static const _flare = Color(0xFFFF4766);
  static const _ember = Color(0xFFFF7A45);

  ShipPalette get _palette => shipPaletteFor(CoinManager.instance.selectedSkin);
  ThrusterSpec get _thruster => thrusterSpecFor(CoinManager.instance.selectedThruster);
  ExplosionStyle _style() => explosionStyleFor(CoinManager.instance.selectedExplosion);

  static String _weaponName(String? id) => switch (id) {
        'spread' => 'Spread',
        'laser' => 'Laser',
        'rockets' => 'Rockets',
        _ => 'Blaster',
      };

  void _dust(double x, double y, int n) {
    for (var i = 0; i < n; i++) {
      final dir = i.isEven ? 1 : -1;
      _parts.add(_Part(x + dir * 0.1, y - 0.05, dir * (1 + _rng.nextDouble() * 2), -0.6 - _rng.nextDouble(), 0.4,
          0.12 + _rng.nextDouble() * 0.08, const Color(0xFFB0786A), smoke: true, drag: 3));
    }
  }

  void _sparks(double x, double y, int n, Color c) {
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2 + _rng.nextDouble() * 0.4;
      final sp = 3 + _rng.nextDouble() * 4;
      _parts.add(_Part(x, y, math.cos(a) * sp, math.sin(a) * sp, 0.45, 0.07, c, hot: true, drag: 4));
    }
  }

  void _debris(double x, double y, int n, Color c) {
    for (var i = 0; i < n; i++) {
      final a = -math.pi * (0.1 + 0.8 * _rng.nextDouble());
      final sp = 4 + _rng.nextDouble() * 7;
      _parts.add(_Part(x, y, math.cos(a) * sp, math.sin(a) * sp, 0.9 + _rng.nextDouble() * 0.4, 0.08 + _rng.nextDouble() * 0.08,
          c, chip: true, gravity: 30, spin: (_rng.nextDouble() - 0.5) * 16));
    }
  }

  // ── Update ──────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_shake > 0) _shake = math.max(0, _shake - dt * 2.6);
    if (_hurt > 0) _hurt = math.max(0, _hurt - dt * 2.4);
    if (_muzzle > 0) _muzzle -= dt;
    if (_bossFlash > 0) _bossFlash = math.max(0, _bossFlash - dt * 1.6);
    final p = sim.pilot;
    if (p.onGround) _runPhase += (p.x - _lastPilotX).abs() * 2.2;
    _lastPilotX = p.x;
    _beaconLit.updateAll((_, v) => v + dt);

    for (final b in _bursts) {
      b.age += dt;
    }
    _bursts.removeWhere((b) => b.age > b.burst.life);
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age >= r.life);
    for (final pp in _pops) {
      pp.age += dt;
    }
    _pops.removeWhere((pp) => pp.age >= 0.9);
    for (final q in _parts) {
      q.age += dt;
      final k = math.max(0.0, 1 - q.drag * dt);
      q.vx *= k;
      q.vy = q.vy * k + q.gravity * dt;
      q.x += q.vx * dt;
      q.y += q.vy * dt;
      q.rot += q.spin * dt;
    }
    _parts.removeWhere((q) => q.age >= q.life);

    // Rocket smoke.
    for (final b in sim.bullets) {
      if (b is AssaultRocket && !b.dead && _rng.nextDouble() < dt * 40) {
        _parts.add(_Part(b.x - b.vx * 0.02, b.y - b.vy * 0.02, (_rng.nextDouble() - 0.5) * 0.6, -0.4, 0.5, 0.1,
            const Color(0xFF8E97C7), smoke: true, drag: 1));
      }
    }
    // The wreck smokes at the start of the stage.
    if (sim.cameraX < 12 && _rng.nextDouble() < dt * 6) {
      _parts.add(_Part(1.3 + _rng.nextDouble() * 0.4, 10.4, 0.25 + _rng.nextDouble() * 0.2, -0.9 - _rng.nextDouble() * 0.4, 3.2,
          0.18 + _rng.nextDouble() * 0.1, const Color(0xFF6E5A78), smoke: true));
    }
  }

  // ── Render ──────────────────────────────────────────────────────────────
  double _sx(double x) => _view.left + (x - sim.cameraX) * _tp;
  double _sy(double y) => _view.top + y * _tp;

  @override
  void render(Canvas canvas) {
    if (_tp == 0 || _sky == null) return;
    canvas.save();
    canvas.clipRect(_view);
    canvas.drawImageRect(_sky!, Offset.zero & _skySize, _view, _imgPaint);
    _paintRidge(canvas, _far!, 0.1);
    _paintRidge(canvas, _near!, 0.28);

    canvas.save();
    if (_shake > 0) {
      final s = _shake * _shake * _tp * 0.22;
      canvas.translate((_rng.nextDouble() * 2 - 1) * s, (_rng.nextDouble() * 2 - 1) * s);
    }

    _paintWreck(canvas);
    _paintSmoke(canvas);
    _paintTiles(canvas);
    _paintCheckpoints(canvas);
    _paintShip(canvas);
    _paintPickups(canvas);
    _paintEnemies(canvas);
    _paintPilot(canvas);
    _paintBullets(canvas);
    _paintEffects(canvas);

    canvas.restore();

    // Red glow creeping in from the edges when hurt, and as the boss
    // arrives / falls. Gradient shaders are cached per size; the paint's
    // alpha fades them.
    final wash = math.max(_hurt * 0.9, _bossFlash * 0.6);
    if (wash > 0.01 && _edgeShaders.isNotEmpty) {
      _wash.color = Color.fromRGBO(255, 255, 255, wash.clamp(0.0, 1.0));
      for (var i = 0; i < 4; i++) {
        _wash.shader = _edgeShaders[i];
        canvas.drawRect(_edgeRects[i], _wash);
      }
      _wash.shader = null;
    }
    canvas.restore();
  }

  static final _imgPaint = Paint()..filterQuality = FilterQuality.low;
  static final _wash = Paint()..blendMode = BlendMode.plus;

  void _paintRidge(Canvas canvas, Picture pic, double factor) {
    final off = (sim.cameraX * _tp * factor) % _ridgeW;
    for (final k in [0.0, 1.0]) {
      canvas.save();
      canvas.translate(_view.left - off + k * _ridgeW, _view.top);
      canvas.drawPicture(pic);
      canvas.restore();
    }
  }

  // ── Sky and ridges (baked) ──────────────────────────────────────────────
  /// The dusk sky: gradient, stars in the upper half, a horizon haze, a
  /// ringed gas giant low on the left and a small moon. Shared with the
  /// arcade hub's preview.
  static void paintSky(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.linear(Offset.zero, Offset(0, s.height), const [
          Color(0xFF0A0C29),
          Color(0xFF24143F),
          Color(0xFF4A1E3E),
          Color(0xFF6B2B45),
        ], const [0, 0.45, 0.72, 1]),
    );
    final rnd = math.Random(4);
    final star = Paint();
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * s.width, y = rnd.nextDouble() * s.height * 0.55;
      star.color = Color.fromRGBO(233, 237, 255, 0.25 + rnd.nextDouble() * 0.55);
      c.drawCircle(Offset(x, y), 0.5 + rnd.nextDouble() * 0.8, star);
    }
    // Horizon haze.
    final hz = Offset(s.width * 0.5, s.height * 0.78);
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.radial(hz, s.width * 0.75, const [Color(0x40FF6A5A), Color(0x14FF6A5A), Color(0x00FF6A5A)], const [0, 0.5, 1]),
    );
    // Gas giant.
    final gc = Offset(s.width * 0.2, s.height * 0.47);
    final gr = s.height * 0.085;
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: gc, radius: gr)));
    c.drawCircle(gc, gr, Paint()..color = const Color(0xFF3A2A6E));
    final band = Paint();
    for (final (off, col) in const [
      (-0.85, Color(0xFF4B3A86)),
      (-0.45, Color(0xFF2E2160)),
      (0.05, Color(0xFF55408F)),
      (0.5, Color(0xFF2A1D55)),
      (0.85, Color(0xFF3E2E75)),
    ]) {
      band.color = col;
      c.drawRect(Rect.fromLTWH(gc.dx - gr, gc.dy + off * gr, gr * 2, gr * 0.22), band);
    }
    c.drawCircle(
      gc.translate(gr * 0.45, gr * 0.35),
      gr * 1.05,
      Paint()
        ..shader = Gradient.radial(gc.translate(gr * 0.45, gr * 0.35), gr * 1.05, const [Color(0xB0080619), Color(0x00080619)], const [0.2, 1]),
    );
    c.restore();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final (k, a) in const [(0.0, 0.45), (3.0, 0.25), (6.0, 0.14)]) {
      ring.color = const Color(0xFFC9A0FF).withValues(alpha: a);
      c.drawOval(Rect.fromCenter(center: gc, width: gr * 3.5 + k * 2, height: gr * 0.42 + k * 0.6), ring);
    }
    // Moon.
    final mc = Offset(s.width * 0.66, s.height * 0.33);
    c.drawCircle(mc, s.height * 0.012, Paint()..color = const Color(0xFF8E7AB8));
    c.drawCircle(mc.translate(s.height * 0.005, 0), s.height * 0.012, Paint()..color = const Color(0xFF1A1236));
  }

  static Picture _ridgePicture(Size s, double w, double base, double amp, double step, Color col, int seed, bool spires) {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    final r = math.Random(seed);
    final n = (w / step).ceil();
    final hs = List<double>.generate(n, (_) => base - r.nextDouble() * amp);
    final path = Path()..moveTo(0, s.height);
    final glints = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final x = i * w / n;
      final h = hs[i % n]; // wraps: the last point matches the first
      path.lineTo(x, h);
      if (spires && i < n && r.nextDouble() < 0.32) {
        final tip = Offset(x + step * 0.3, h - amp * (0.9 + r.nextDouble()));
        path
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(x + step * 0.45, h);
        glints.add(tip);
      }
    }
    path
      ..lineTo(w, s.height)
      ..close();
    c.drawPath(path, Paint()..color = col);
    if (spires) {
      final g = Paint()
        ..strokeWidth = 1
        ..color = const Color(0x664DE8FF);
      for (final tip in glints) {
        c.drawLine(tip.translate(0, 3), tip.translate(0, amp * 0.6), g);
      }
    }
    return rec.endRecording();
  }

  // ── Terrain ─────────────────────────────────────────────────────────────
  static final _fill = Paint();
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static const _rockTop = Color(0xFF3A2238);
  static const _rockDeep = Color(0xFF170E20);

  bool _solid(int c, int r) => r >= 0 && r < sim.level.height && c >= 0 && c < sim.level.width && sim.level.tiles[r][c] == AssaultTile.solid;
  bool _plat(int c, int r) => r >= 0 && r < sim.level.height && c >= 0 && c < sim.level.width && sim.level.tiles[r][c] == AssaultTile.platform;

  void _paintTiles(Canvas canvas) {
    final lv = sim.level;
    final c0 = math.max(0, sim.cameraX.floor() - 1);
    final c1 = math.min(lv.width - 1, (sim.cameraX + AssaultTuning.viewTiles).ceil() + 1);
    final t = _tp;
    for (var col = c0; col <= c1; col++) {
      final x = _sx(col.toDouble());
      for (var row = 0; row < lv.height; row++) {
        final y = _sy(row.toDouble());
        switch (lv.tiles[row][col]) {
          case AssaultTile.empty:
            break;
          case AssaultTile.solid:
            var depth = 0;
            while (depth < 3 && _solid(col, row - depth - 1)) {
              depth++;
            }
            _fill.color = Color.lerp(_rockTop, _rockDeep, depth / 3)!;
            canvas.drawRect(Rect.fromLTWH(x - 0.5, y - 0.5, t + 1, t + 1), _fill);
            // Craters and strata, fixed per tile.
            final h = (col * 73856093) ^ (row * 19349663);
            final cx = x + t * (0.2 + ((h >> 3) & 15) / 15 * 0.6);
            final cy = y + t * (0.3 + ((h >> 7) & 15) / 15 * 0.5);
            final cr = t * (0.05 + ((h >> 11) & 7) / 7 * 0.06);
            _fill.color = const Color(0x660A0612);
            canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: cr * 2, height: cr * 1.4), _fill);
            if ((h & 3) == 0) {
              _stroke
                ..strokeWidth = 1
                ..color = const Color(0x33E0915A);
              canvas.drawLine(Offset(x + t * 0.15, y + t * 0.7), Offset(x + t * 0.55, y + t * 0.62), _stroke);
            }
            if (!_solid(col, row - 1)) {
              // Sunset-lit lip: a warm band, a bright hairline and tufts.
              _fill.color = const Color(0xFF6E3A3E);
              canvas.drawRect(Rect.fromLTWH(x - 0.5, y, t + 1, t * 0.14), _fill);
              _fill.color = const Color(0xFFE0915A);
              canvas.drawRect(Rect.fromLTWH(x - 0.5, y, t + 1, math.max(1.5, t * 0.05)), _fill);
              for (var k = 0; k < 2; k++) {
                final tx = x + t * (0.15 + ((h >> (13 + k * 3)) & 7) / 7 * 0.7);
                canvas.drawPath(
                  Path()
                    ..moveTo(tx - t * 0.05, y)
                    ..lineTo(tx, y - t * 0.1)
                    ..lineTo(tx + t * 0.06, y),
                  _fill,
                );
              }
            }
            if (!_solid(col - 1, row)) {
              _fill.color = const Color(0x998A4A48);
              canvas.drawRect(Rect.fromLTWH(x, y, math.max(1.5, t * 0.05), t), _fill);
            }
            if (!_solid(col + 1, row)) {
              _fill.color = const Color(0x660A0612);
              canvas.drawRect(Rect.fromLTWH(x + t * 0.94, y, t * 0.06, t), _fill);
            }
          case AssaultTile.platform:
            // Salvaged hull plate on struts: a different material from rock.
            _fill.color = const Color(0xFF2B3156);
            canvas.drawRect(Rect.fromLTWH(x, y, t, t * 0.2), _fill);
            _fill.color = const Color(0xFF9AA6E0);
            canvas.drawRect(Rect.fromLTWH(x, y, t, math.max(1.5, t * 0.045)), _fill);
            _fill.color = const Color(0xFF1C2140);
            canvas.drawRect(Rect.fromLTWH(x, y + t * 0.2, t, t * 0.05), _fill);
            if (!_plat(col - 1, row) || !_plat(col + 1, row)) {
              final sxp = !_plat(col - 1, row) ? x + t * 0.2 : x + t * 0.8;
              _stroke
                ..strokeWidth = t * 0.08
                ..color = const Color(0xFF2B3156);
              canvas.drawLine(Offset(sxp, y + t * 0.24), Offset(sxp - t * 0.1, y + t * 0.5), _stroke);
            }
            // rivets
            _fill.color = const Color(0x809AA6E0);
            canvas.drawCircle(Offset(x + t * 0.5, y + t * 0.11), t * 0.025, _fill);
          case AssaultTile.spikes:
            // Flare-tipped crystal shards.
            for (final (o, hgt) in const [(0.22, 0.42), (0.5, 0.55), (0.78, 0.4)]) {
              final bx = x + t * o;
              final path = Path()
                ..moveTo(bx - t * 0.13, y + t)
                ..lineTo(bx, y + t * (1 - hgt))
                ..lineTo(bx + t * 0.13, y + t)
                ..close();
              _fill.color = const Color(0xFF7A1F3A);
              canvas.drawPath(path, _fill);
              _fill.color = _flare;
              canvas.drawPath(
                Path()
                  ..moveTo(bx - t * 0.05, y + t * (1 - hgt * 0.55))
                  ..lineTo(bx, y + t * (1 - hgt))
                  ..lineTo(bx + t * 0.05, y + t * (1 - hgt * 0.55))
                  ..close(),
                _fill,
              );
            }
            Glow.draw(canvas, Offset(x + t * 0.5, y + t * 0.6), t * 0.5, _flare.withValues(alpha: 0.25 + 0.1 * math.sin(_t * 4 + col)));
        }
      }
    }
  }

  // The lander you crash-landed in, nose in the dirt at the start.
  void _paintWreck(Canvas canvas) {
    if (sim.cameraX > 6) return;
    final t = _tp;
    final c = Offset(_sx(1.4), _sy(11) - t * 0.15);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(0.55);
    canvas.scale(t * 1.25 / 40);
    ShipArt.paint(canvas, _palette, time: _t, thrust: 0, engines: false);
    canvas.restore();
    // Sparks from the hull, embers in the dirt.
    if ((_t * 3).floor() % 4 == 0) {
      Glow.draw(canvas, c.translate(-t * 0.3, -t * 0.4), t * 0.25, _ember.withValues(alpha: 0.9), hot: true);
    }
    Glow.draw(canvas, c.translate(t * 0.2, t * 0.1), t * 0.6, _ember.withValues(alpha: 0.35 + 0.1 * math.sin(_t * 7)));
  }

  void _paintSmoke(Canvas canvas) {
    for (final q in _parts) {
      if (!q.smoke) continue;
      final f = q.age / q.life;
      _fill.color = q.color.withValues(alpha: 0.28 * (1 - f));
      canvas.drawCircle(Offset(_sx(q.x), _sy(q.y)), _tp * q.size * (1 + f * 2), _fill);
    }
  }

  // ── Checkpoints, ship, pickups ──────────────────────────────────────────
  void _paintCheckpoints(Canvas canvas) {
    final t = _tp;
    for (var i = 0; i < sim.checkpoints.length; i++) {
      final k = sim.checkpoints[i];
      final x = _sx(k.x);
      if (x < _view.left - t * 2 || x > _view.right + t * 2) continue;
      final foot = _sy(k.y);
      final lit = k.reached;
      // Pylon: a tapered mast on a footing.
      _fill.color = const Color(0xFF2B3156);
      canvas.drawPath(
        Path()
          ..moveTo(x - t * 0.28, foot)
          ..lineTo(x - t * 0.08, foot - t * 1.5)
          ..lineTo(x + t * 0.08, foot - t * 1.5)
          ..lineTo(x + t * 0.28, foot)
          ..close(),
        _fill,
      );
      _fill.color = const Color(0xFF9AA6E0);
      canvas.drawRect(Rect.fromLTWH(x - t * 0.3, foot - t * 0.12, t * 0.6, t * 0.12), _fill);
      final tip = Offset(x, foot - t * 1.6);
      if (lit) {
        final age = _beaconLit[i] ?? 9;
        // Beam into the sky, brightest as it lights.
        final burst = math.max(0.0, 1 - age / 0.8);
        final beamW = t * (0.12 + 0.25 * burst);
        canvas.drawRect(
          Rect.fromLTRB(x - beamW, _view.top, x + beamW, tip.dy),
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = Gradient.linear(Offset(x, _view.top), tip, [_ion.withValues(alpha: 0), _ion.withValues(alpha: 0.35 + 0.5 * burst)]),
        );
        Glow.draw(canvas, tip, t * (0.55 + 0.6 * burst), _ion.withValues(alpha: 0.9));
        Glow.draw(canvas, tip, t * 0.16, const Color(0xFFFFFFFF), hot: true);
      } else {
        final blink = (_t * 1.4).floor().isEven;
        Glow.draw(canvas, tip, t * 0.3, const Color(0xFF8E97C7).withValues(alpha: blink ? 0.7 : 0.25));
        _fill.color = const Color(0xFF8E97C7);
        canvas.drawCircle(tip, t * 0.06, _fill);
      }
    }
  }

  void _paintShip(Canvas canvas) {
    final t = _tp;
    final x = _sx(sim.exitX);
    if (x < _view.left - t * 3 || x > _view.right + t * 3) return;
    final foot = _sy(sim.exitY);
    final cleared = sim.phase == AssaultPhase.cleared;
    final lift = cleared ? math.pow(math.max(0, sim.phaseTime - 0.35), 2) * t * 9 : 0.0;
    final scale = t * 2.4 / 42;
    final c = Offset(x, foot - t * 1.25 - lift);
    // Landing pad and struts.
    _fill.color = const Color(0xFF2B3156);
    canvas.drawRect(Rect.fromLTWH(x - t * 1.3, foot - t * 0.12, t * 2.6, t * 0.12), _fill);
    for (var k = -1; k <= 1; k += 2) {
      final bx = x + k * t * 0.9;
      Glow.draw(canvas, Offset(bx, foot - t * 0.06), t * 0.3, _ion.withValues(alpha: 0.5 + 0.4 * math.sin(_t * 4 + k)));
    }
    if (!cleared) {
      _stroke
        ..strokeWidth = t * 0.07
        ..color = const Color(0xFF545C8A);
      canvas.drawLine(Offset(x - t * 0.5, foot - t * 0.15), Offset(x - t * 0.35, foot - t * 0.75), _stroke);
      canvas.drawLine(Offset(x + t * 0.5, foot - t * 0.15), Offset(x + t * 0.35, foot - t * 0.75), _stroke);
      // "Board" chevrons over it.
      final a = 0.45 + 0.35 * math.sin(_t * 4);
      _stroke
        ..strokeWidth = t * 0.08
        ..color = _ion.withValues(alpha: a);
      for (var k = 0; k < 2; k++) {
        final y = foot - t * (3.1 + k * 0.32) + math.sin(_t * 3) * t * 0.08;
        canvas.drawPath(
          Path()
            ..moveTo(x - t * 0.25, y - t * 0.15)
            ..lineTo(x, y + t * 0.1)
            ..lineTo(x + t * 0.25, y - t * 0.15),
          _stroke..style = PaintingStyle.stroke,
        );
      }
    }
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(scale);
    ShipArt.paint(canvas, _palette, time: _t, thrust: cleared ? 1.0 : 0.15, engine: _thruster.color);
    canvas.restore();
    if (cleared) {
      Glow.draw(canvas, Offset(x, c.dy + t * 1.2), t * (1.2 + 0.2 * math.sin(_t * 20)), (_thruster.color ?? _palette.engine).withValues(alpha: 0.7));
    }
  }

  void _paintPickups(Canvas canvas) {
    final t = _tp;
    for (final p in sim.pickups) {
      if (p.taken) continue;
      final x = _sx(p.x);
      if (x < _view.left - t || x > _view.right + t) continue;
      final y = _sy(p.y) + math.sin(_t * 3 + p.x) * t * 0.06;
      if (p.kind == PickupKind.shard) {
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(t / 40);
        ThreadArt.paintShard(canvas, Offset.zero, _t + p.x);
        canvas.restore();
      } else {
        paintCapsule(canvas, Offset(x, y), t, p.weapon ?? WeaponKind.spread, _t);
      }
    }
  }

  /// A weapon capsule: a plasma chamfered pod with the weapon's glyph.
  static void paintCapsule(Canvas canvas, Offset c, double t, WeaponKind w, double time) {
    Glow.draw(canvas, c, t * 0.9, _plasma.withValues(alpha: 0.4 + 0.15 * math.sin(time * 5)));
    final r = t * 0.36;
    final cut = r * 0.4;
    final pod = Path()
      ..moveTo(c.dx - r + cut, c.dy - r)
      ..lineTo(c.dx + r, c.dy - r)
      ..lineTo(c.dx + r, c.dy + r - cut)
      ..lineTo(c.dx + r - cut, c.dy + r)
      ..lineTo(c.dx - r, c.dy + r)
      ..lineTo(c.dx - r, c.dy - r + cut)
      ..close();
    _fill.color = const Color(0xF0140C33);
    canvas.drawPath(pod, _fill);
    _stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, t * 0.045)
      ..color = _plasma;
    canvas.drawPath(pod, _stroke);
    paintWeaponGlyph(canvas, c, r * 0.62, w, weaponColor(w));
  }

  /// Weapon glyphs, shared with the HUD's weapon chip.
  static void paintWeaponGlyph(Canvas canvas, Offset c, double s, WeaponKind w, Color col) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.4, s * 0.22)
      ..color = col;
    switch (w) {
      case WeaponKind.blaster:
        canvas.drawLine(c.translate(-s * 0.8, 0), c.translate(s * 0.6, 0), p);
        canvas.drawCircle(c.translate(s * 0.75, 0), s * 0.2, p..style = PaintingStyle.fill);
      case WeaponKind.spread:
        for (final a in [-0.55, -0.27, 0.0, 0.27, 0.55]) {
          canvas.drawLine(c.translate(-s * 0.7, s * 0.6), c.translate(-s * 0.7 + math.sin(a + 0.8) * s * 1.6, s * 0.6 - math.cos(a + 0.8) * s * 1.6), p);
        }
      case WeaponKind.laser:
        canvas.drawLine(c.translate(-s, 0), c.translate(s, 0), p..strokeWidth = math.max(1.6, s * 0.3));
        canvas.drawLine(c.translate(-s * 0.4, -s * 0.45), c.translate(-s * 0.4, s * 0.45), p..strokeWidth = math.max(1, s * 0.14));
      case WeaponKind.rockets:
        final body = Path()
          ..moveTo(c.dx + s, c.dy)
          ..lineTo(c.dx + s * 0.35, c.dy - s * 0.35)
          ..lineTo(c.dx - s * 0.6, c.dy - s * 0.35)
          ..lineTo(c.dx - s * 0.6, c.dy + s * 0.35)
          ..lineTo(c.dx + s * 0.35, c.dy + s * 0.35)
          ..close();
        canvas.drawPath(body, p..style = PaintingStyle.fill);
        canvas.drawLine(c.translate(-s * 0.6, 0), c.translate(-s * 1.0, -s * 0.45), p..style = PaintingStyle.stroke);
        canvas.drawLine(c.translate(-s * 0.6, 0), c.translate(-s * 1.0, s * 0.45), p);
    }
  }

  static Color weaponColor(WeaponKind w) => switch (w) {
        WeaponKind.blaster => _ion,
        WeaponKind.spread => const Color(0xFFF4A800),
        WeaponKind.laser => const Color(0xFFB8F6FF),
        WeaponKind.rockets => const Color(0xFFFF8C00),
      };

  // ── Enemies ─────────────────────────────────────────────────────────────
  void _paintEnemies(Canvas canvas) {
    final t = _tp;
    for (final e in sim.enemies) {
      if (e.dead) continue;
      final x = _sx(e.x);
      if (x < _view.left - t * 3 || x > _view.right + t * 3) continue;
      final ce = e is AssaultCombatEnemy ? e : null;
      final flash = ce == null ? 0.0 : (ce.hitFlash / 0.1).clamp(0.0, 1.0);
      final tele = ce?.telegraph ?? 0;
      final facing = ce?.facing ?? -1;
      final anim = ce?.animTime ?? _t;
      final state = ce?.state ?? '';
      final foot = Offset(x, _sy(e.y));
      switch (e.kind) {
        case 'grunt':
          paintGrunt(canvas, foot, t, facing, anim, state, tele, flash, (ce?.vx ?? 0).abs() > 0.1);
        case 'runner':
          _paintRunner(canvas, foot, t, facing, anim, state, tele, flash);
        case 'turret':
          final tu = e is AssaultTurret ? e : null;
          _paintTurret(canvas, foot, t, tu?.angle ?? math.pi, state, tele, flash);
        case 'flyer':
          _paintFlyer(canvas, Offset(x, _sy(e.centerY)), t, facing, anim, state, tele, flash);
        case 'boss':
          final b = e is AssaultBoss ? e : null;
          // Hit constantly, so a softer flash keeps its colours readable.
          _paintWarden(canvas, foot, t, facing, anim, state, tele, flash * 0.5, b?.phase ?? 1, e.hp / e.maxHp);
      }
    }
  }

  static Color _lit(Color c, double flash) => flash <= 0 ? c : Color.lerp(c, const Color(0xFFFFFFFF), flash * 0.55)!;

  static const _shell = Color(0xFF5B2C6B);
  static const _shellLit = Color(0xFF8A4596);
  static const _shellDark = Color(0xFF3D1F4A);

  static final _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;

  static void _rimmed(Canvas canvas, Path path, Color fill, double flash, double w) {
    _fill.color = _lit(fill, flash);
    canvas.drawPath(path, _fill);
    _rim
      ..strokeWidth = w
      ..color = _flare.withValues(alpha: 0.8);
    canvas.drawPath(path, _rim);
  }

  /// The grunt: a hunched carapace biped with an arm cannon. Its muzzle
  /// charges (flare) while aiming. Shared with the hub preview.
  static void paintGrunt(Canvas canvas, Offset foot, double t, int facing, double anim, String state, double tele,
      double flash, bool walking) {
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    canvas.scale(t / 40 * facing, t / 40);
    final step = walking ? math.sin(anim * 9) : 0.0;
    final bob = walking ? step.abs() * 1.5 : math.sin(anim * 2) * 0.6;
    // legs
    _fill.color = _lit(_shellDark, flash);
    for (final (lx, ph) in [(-6.0, step), (5.0, -step)]) {
      canvas.drawPath(
        Path()
          ..moveTo(lx - 2, -18)
          ..lineTo(lx + 4, -18)
          ..lineTo(lx + 4 + ph * 4, 0)
          ..lineTo(lx - 4 + ph * 4, 0)
          ..close(),
        _fill,
      );
    }
    canvas.translate(0, -bob);
    final body = Path()
      ..moveTo(-12, -44)
      ..lineTo(8, -50)
      ..lineTo(15, -36)
      ..lineTo(12, -18)
      ..lineTo(-12, -18)
      ..lineTo(-15, -30)
      ..close();
    _rimmed(canvas, body, _shell, flash, 1.4);
    _fill.color = _lit(_shellLit, flash);
    canvas.drawPath(
      Path()
        ..moveTo(-12, -44)
        ..lineTo(8, -50)
        ..lineTo(12, -42)
        ..lineTo(-12, -37)
        ..close(),
      _fill,
    );
    // eye slit
    _fill.color = _flare;
    canvas.drawRect(const Rect.fromLTWH(1, -43, 9, 3), _fill);
    Glow.draw(canvas, const Offset(5, -41.5), 7, _flare.withValues(alpha: 0.6));
    // cannon arm
    _fill.color = _lit(const Color(0xFF26142F), flash);
    canvas.drawPath(
      Path()
        ..moveTo(4, -33)
        ..lineTo(24, -35)
        ..lineTo(24, -28)
        ..lineTo(4, -26)
        ..close(),
      _fill,
    );
    final aiming = state == 'aim';
    final m = const Offset(24, -31.5);
    Glow.draw(canvas, m, 4 + (aiming ? tele * 12 : 0), _ember.withValues(alpha: aiming ? 0.5 + 0.5 * tele : 0.5), hot: aiming && tele > 0.7);
    canvas.restore();
  }

  void _paintRunner(Canvas canvas, Offset foot, double t, int facing, double anim, String state, double tele, double flash) {
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    canvas.scale(t / 40 * facing, t / 40);
    final charging = state == 'charge';
    final crouch = state == 'alert' ? tele * 5 : 0.0;
    final gait = charging ? anim * 22 : anim * 3;
    // motion streaks
    if (charging) {
      _stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ember.withValues(alpha: 0.5);
      for (final y in [-30.0, -22.0, -14.0]) {
        canvas.drawLine(Offset(-18, y), Offset(-34 - (y.abs() % 7) * 2, y), _stroke);
      }
    }
    // legs (four, scuttling)
    _stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _lit(_shellDark, flash);
    for (var i = 0; i < 4; i++) {
      final lx = -12.0 + i * 7.5;
      final s = math.sin(gait + i * 1.6);
      canvas.drawLine(Offset(lx, -12 + crouch), Offset(lx + s * 5, 0), _stroke);
    }
    canvas.translate(0, crouch);
    final body = Path()
      ..moveTo(-16, -14)
      ..lineTo(-10, -30)
      ..lineTo(4, -34)
      ..lineTo(18, -22)
      ..lineTo(16, -12)
      ..close();
    _rimmed(canvas, body, _shell, flash, 1.4);
    // back spikes
    _fill.color = _lit(_shellLit, flash);
    for (final sx in [-9.0, -2.0, 5.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(sx - 3, -31 + (sx + 9) * 0.1)
          ..lineTo(sx - 1, -40 + (sx + 9) * 0.3)
          ..lineTo(sx + 3, -32),
        _fill,
      );
    }
    // eye: flares as it winds up to charge
    final eye = 0.5 + 0.5 * (state == 'alert' ? tele : 1);
    Glow.draw(canvas, const Offset(13, -22), 5 + 7 * eye, _flare.withValues(alpha: 0.4 + 0.5 * eye));
    _fill.color = _flare;
    canvas.drawCircle(const Offset(13, -22), 2.2, _fill);
    // stripes
    _stroke
      ..strokeWidth = 2
      ..color = _ember.withValues(alpha: 0.8);
    canvas.drawLine(const Offset(-6, -28), const Offset(-2, -16), _stroke);
    canvas.drawLine(const Offset(1, -30), const Offset(5, -17), _stroke);
    canvas.restore();
  }

  void _paintTurret(Canvas canvas, Offset foot, double t, double angle, String state, double tele, double flash) {
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    canvas.scale(t / 40);
    // rock collar it's dug into
    _fill.color = const Color(0xFF3A2238);
    canvas.drawPath(
      Path()
        ..moveTo(-20, 0)
        ..lineTo(-16, -9)
        ..lineTo(16, -9)
        ..lineTo(20, 0)
        ..close(),
      _fill,
    );
    // barrel (rotates)
    canvas.save();
    canvas.translate(0, -18);
    canvas.rotate(angle);
    _fill.color = _lit(const Color(0xFF26142F), flash);
    canvas.drawRect(const Rect.fromLTWH(0, -3.5, 22, 7), _fill);
    _fill.color = _lit(_shellLit, flash);
    canvas.drawRect(const Rect.fromLTWH(18, -4.5, 5, 9), _fill);
    final charging = state == 'charge';
    final firing = state == 'burst';
    Glow.draw(canvas, const Offset(24, 0), 5 + (charging ? tele * 14 : (firing ? 12 : 0)),
        _ember.withValues(alpha: charging ? 0.4 + 0.6 * tele : (firing ? 0.9 : 0.35)), hot: firing);
    canvas.restore();
    // dome
    final dome = Path()..addArc(Rect.fromCircle(center: const Offset(0, -9), radius: 15), math.pi, math.pi);
    dome.close();
    _rimmed(canvas, dome, _shell, flash, 1.4);
    _fill.color = _flare;
    canvas.drawCircle(const Offset(0, -16), 2.4, _fill);
    Glow.draw(canvas, const Offset(0, -16), 8, _flare.withValues(alpha: 0.5 + 0.3 * tele));
    canvas.restore();
  }

  void _paintFlyer(Canvas canvas, Offset c, double t, int facing, double anim, String state, double tele, double flash) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(t / 40 * facing, t / 40);
    final swoop = state == 'swoop';
    Glow.draw(canvas, const Offset(0, 10), 16, _flare.withValues(alpha: 0.35 + 0.3 * (swoop ? 1 : tele)));
    // rotor arms
    _stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _lit(_shellLit, flash);
    final flap = math.sin(anim * 30) * 2;
    canvas.drawLine(const Offset(-10, -4), Offset(-22, -9 + flap), _stroke);
    canvas.drawLine(const Offset(10, -4), Offset(22, -9 - flap), _stroke);
    // pods
    for (final sx in [-14.0, 14.0]) {
      final pod = Path()..addOval(Rect.fromCenter(center: Offset(sx, 1), width: 11, height: 10));
      _rimmed(canvas, pod, _shellDark, flash, 1.1);
    }
    final body = Path()..addOval(Rect.fromCenter(center: Offset.zero, width: 24, height: 15));
    _rimmed(canvas, body, _shell, flash, 1.4);
    // eye flares as it commits to a swoop
    final eye = swoop ? 1.0 : tele;
    Glow.draw(canvas, const Offset(4, 1), 6 + 8 * eye, _flare.withValues(alpha: 0.6 + 0.4 * eye), hot: eye > 0.8);
    _fill.color = _flare;
    canvas.drawCircle(const Offset(4, 1), 3, _fill);
    canvas.restore();
  }

  /// The Warden: a 3x3-tile walker. Plates crack in phase 2, the core is
  /// bare and blazing in phase 3. It rears back as a slam winds up, a
  /// shoulder cannon glows before volleys, its antenna glows to summon.
  void _paintWarden(Canvas canvas, Offset foot, double t, int facing, double anim, String state, double tele, double flash,
      int phase, double hpFrac) {
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    final roar = state == 'roar';
    if (roar) canvas.translate(math.sin(anim * 60) * t * 0.05, 0);
    canvas.scale(t / 40 * facing, t / 40);
    final walking = state == 'walk';
    final step = walking ? math.sin(anim * 4) : 0.0;
    // legs (two thick pistons)
    for (final (lx, ph) in [(-26.0, step), (22.0, -step)]) {
      final lift = math.max(0.0, ph) * 6;
      _fill.color = _lit(_shellDark, flash);
      canvas.drawPath(
        Path()
          ..moveTo(lx - 9, -46)
          ..lineTo(lx + 9, -46)
          ..lineTo(lx + 11, -8 - lift)
          ..lineTo(lx - 11, -8 - lift)
          ..close(),
        _fill,
      );
      _fill.color = _lit(const Color(0xFF26142F), flash);
      canvas.drawRect(Rect.fromLTRB(lx - 15, -9 - lift, lx + 15, -lift), _fill);
    }
    // torso: rears back while a slam winds up, slams forward after
    final rear = state == 'slamWind' ? tele : (state == 'slam' ? -0.6 : 0.0);
    canvas.save();
    canvas.translate(0, -50);
    canvas.rotate(-rear * 0.22);
    final torso = Path()
      ..moveTo(-44, -10)
      ..lineTo(-30, -62)
      ..lineTo(26, -66)
      ..lineTo(46, -30)
      ..lineTo(40, 4)
      ..lineTo(-40, 4)
      ..close();
    _rimmed(canvas, torso, _shell, flash, 2);
    // armour plates
    _fill.color = _lit(_shellLit, flash);
    final plates = [
      Path()
        ..moveTo(-30, -62)
        ..lineTo(26, -66)
        ..lineTo(32, -52)
        ..lineTo(-34, -48)
        ..close(),
      Path()
        ..moveTo(-42, -2)
        ..lineTo(-36, -36)
        ..lineTo(-22, -36)
        ..lineTo(-26, -2)
        ..close(),
    ];
    for (final pl in plates) {
      canvas.drawPath(pl, _fill);
    }
    if (phase >= 2) {
      // cracks
      _stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ember.withValues(alpha: 0.85);
      canvas.drawPath(
        Path()
          ..moveTo(-12, -60)
          ..lineTo(-6, -52)
          ..lineTo(-10, -44)
          ..lineTo(-2, -36),
        _stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(18, -64)
          ..lineTo(14, -54)
          ..lineTo(22, -46),
        _stroke,
      );
    }
    // core: brighter each phase, pulsing; blazing during wind-ups
    final coreR = 10.0 + phase * 2;
    final pulse = 0.5 + 0.5 * math.sin(anim * (3 + phase * 2));
    final hot = math.max(tele, roar ? 1.0 : 0.0);
    _fill.color = const Color(0xFF26142F);
    canvas.drawCircle(const Offset(4, -24), coreR + 3, _fill);
    Glow.draw(canvas, const Offset(4, -24), coreR * (1.6 + pulse * 0.4 + hot), _flare.withValues(alpha: 0.5 + 0.2 * phase / 3 + 0.3 * hot));
    _fill.color = Color.lerp(_flare, const Color(0xFFFFE0D6), phase == 3 ? 0.5 * pulse : 0.15)!;
    canvas.drawCircle(const Offset(4, -24), coreR, _fill);
    // visor
    _fill.color = _flare;
    canvas.drawRect(const Rect.fromLTWH(14, -58, 16, 4), _fill);
    Glow.draw(canvas, const Offset(22, -56), 10, _flare.withValues(alpha: 0.7));
    // shoulder cannon (volleys come from here)
    _fill.color = _lit(const Color(0xFF26142F), flash);
    canvas.drawRect(const Rect.fromLTWH(18, -76, 30, 10), _fill);
    final volley = state == 'volleyWind' ? tele : (state == 'volley' ? 1.0 : 0.0);
    Glow.draw(canvas, const Offset(50, -71), 6 + 16 * volley, _ember.withValues(alpha: 0.4 + 0.6 * volley), hot: volley > 0.8);
    // antenna (summons drones)
    final summon = state == 'summonWind' ? tele : 0.0;
    _stroke
      ..strokeWidth = 2.4
      ..color = _lit(_shellLit, flash);
    canvas.drawLine(const Offset(-20, -62), const Offset(-28, -84), _stroke);
    Glow.draw(canvas, const Offset(-28, -86), 5 + 14 * summon, _flare.withValues(alpha: 0.5 + 0.5 * summon), hot: summon > 0.7);
    // fists (raised over the head as the slam winds up)
    final raise = state == 'slamWind' ? tele : 0.0;
    for (final fx in [-46.0, 46.0]) {
      final fy = -16 - raise * 58;
      _fill.color = _lit(_shellDark, flash);
      canvas.drawRect(Rect.fromCenter(center: Offset(fx, fy), width: 16, height: 18), _fill);
      _rim
        ..strokeWidth = 1.4
        ..color = _flare.withValues(alpha: 0.7);
      canvas.drawRect(Rect.fromCenter(center: Offset(fx, fy), width: 16, height: 18), _rim);
    }
    canvas.restore();
    // Floor warning under it while a slam winds up.
    if (state == 'slamWind') {
      Glow.drawOval(canvas, Rect.fromCenter(center: const Offset(0, -2), width: 220 * (0.4 + tele * 0.6), height: 14),
          _flare.withValues(alpha: 0.3 + 0.4 * tele));
    }
    canvas.restore();
  }

  // ── Pilot ───────────────────────────────────────────────────────────────
  void _paintPilot(Canvas canvas) {
    final p = sim.pilot;
    if (!p.alive) return;
    if (sim.phase == AssaultPhase.cleared && sim.phaseTime > 0.25) return; // boarded
    if (p.invulnerable > 0 && (sim.time * 14).floor().isOdd) return;
    final pose = !p.onGround
        ? PilotPose.jump
        : p.crouching
            ? PilotPose.crouch
            : (p.vx.abs() > 0.5 ? PilotPose.run : PilotPose.idle);
    paintPilot(
      canvas,
      Offset(_sx(p.x), _sy(p.y)),
      _tp,
      _palette,
      _thruster.color ?? _palette.engine,
      facing: p.facing,
      aim: p.aim,
      pose: pose,
      run: _runPhase,
      time: _t,
      rising: p.vy < 0,
      muzzle: _muzzle > 0 ? weaponColor(p.weapon) : null,
    );
  }

  /// The pilot in the equipped ship's colours: helmet with an ion visor,
  /// backpack thruster, a gun arm on 8 directions. Shared with the hub.
  static void paintPilot(Canvas canvas, Offset foot, double t, ShipPalette pal, Color engine,
      {required int facing,
      required AimDir aim,
      required PilotPose pose,
      double run = 0,
      double time = 0,
      bool rising = false,
      Color? muzzle}) {
    canvas.save();
    canvas.translate(foot.dx, foot.dy);
    canvas.scale(t / 40 * facing, t / 40);
    final crouch = pose == PilotPose.crouch;
    final h = crouch ? 36.0 : 56.0;
    final bob = pose == PilotPose.idle ? math.sin(time * 2.5) * 0.6 : (pose == PilotPose.run ? math.sin(run * 2).abs() * 1.5 : 0.0);
    final suit = pal.hull;
    final limb = pal.wing;
    final accent = pal.accent;

    // Thruster flame while rising.
    if (pose == PilotPose.jump && rising) {
      Glow.draw(canvas, Offset(-9, -h * 0.42), 12, engine.withValues(alpha: 0.75));
      _fill.color = const Color(0xFFE9FCFF);
      canvas.drawPath(
        Path()
          ..moveTo(-12, -h * 0.5)
          ..lineTo(-6, -h * 0.5)
          ..lineTo(-9, -h * 0.5 + 12 + math.sin(time * 40) * 2),
        _fill,
      );
    }
    // Legs.
    _fill.color = limb;
    if (pose == PilotPose.run) {
      for (final ph in [0.0, math.pi]) {
        final s = math.sin(run + ph);
        final knee = Offset(s * 5, -12 + (math.cos(run + ph)).abs() * -2);
        final footP = Offset(s * 9, 0 - math.max(0.0, math.cos(run + ph)) * 4);
        _stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..color = ph == 0 ? limb : Color.lerp(limb, const Color(0xFF000000), 0.25)!;
        canvas.drawLine(Offset(0, -22 - bob), knee, _stroke);
        canvas.drawLine(knee, footP, _stroke);
      }
    } else if (pose == PilotPose.jump) {
      _stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = limb;
      canvas.drawLine(const Offset(-1, -22), const Offset(6, -12), _stroke);
      canvas.drawLine(const Offset(6, -12), const Offset(1, -5), _stroke);
      _stroke.color = Color.lerp(limb, const Color(0xFF000000), 0.25)!;
      canvas.drawLine(const Offset(-3, -22), const Offset(-6, -10), _stroke);
      canvas.drawLine(const Offset(-6, -10), const Offset(-2, -3), _stroke);
    } else {
      _stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = limb;
      final kneeY = crouch ? -8.0 : -12.0;
      canvas.drawLine(Offset(-3, crouch ? -14 : -22), Offset(crouch ? 4 : -3, kneeY), _stroke);
      canvas.drawLine(Offset(crouch ? 4 : -3, kneeY), const Offset(-4, -1), _stroke);
      canvas.drawLine(Offset(3, crouch ? -14 : -22), Offset(crouch ? 9 : 4, kneeY), _stroke);
      canvas.drawLine(Offset(crouch ? 9 : 4, kneeY), const Offset(5, -1), _stroke);
    }
    canvas.translate(0, -bob - (crouch ? -2 : 0));
    final top = -h;
    // Backpack.
    _fill.color = const Color(0xFF8E97C7);
    canvas.drawRRect(RRect.fromLTRBR(-13, top + 14, -5, top + 32, const Radius.circular(2)), _fill);
    // Torso.
    _fill.color = suit;
    canvas.drawRRect(RRect.fromLTRBR(-8, top + 14, 8, crouch ? -12 : -20, const Radius.circular(3)), _fill);
    _fill.color = accent;
    canvas.drawRect(Rect.fromLTRB(-8, top + 24, 8, top + 27), _fill);
    // Helmet + visor.
    _fill.color = suit;
    canvas.drawOval(Rect.fromLTRB(-8, top, 9, top + 16), _fill);
    _fill.color = const Color(0xFF4DE8FF);
    canvas.drawPath(
      Path()
        ..moveTo(1, top + 4)
        ..lineTo(9, top + 5)
        ..lineTo(8, top + 11)
        ..lineTo(1, top + 10)
        ..close(),
      _fill,
    );
    Glow.draw(canvas, Offset(5, top + 7.5), 7, const Color(0xFF4DE8FF).withValues(alpha: 0.55));
    // Gun arm on the aim direction (mirrored space: x flips with facing).
    final a = math.atan2(aim.dy, aim.dx * facing);
    final sh = Offset(2, top + 19);
    final end = sh + Offset(math.cos(a), math.sin(a)) * 19;
    _stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFF2B3156);
    canvas.drawLine(sh, end, _stroke);
    _stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF9AA6E0);
    canvas.drawLine(sh, end, _stroke);
    if (muzzle != null) {
      Glow.draw(canvas, end + Offset(math.cos(a), math.sin(a)) * 3, 10, muzzle.withValues(alpha: 0.9), hot: true);
    }
    canvas.restore();
  }

  // ── Bullets ─────────────────────────────────────────────────────────────
  static final _line = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  void _paintBullets(Canvas canvas) {
    final t = _tp;
    for (final b in sim.bullets) {
      if (b.dead) continue;
      final c = Offset(_sx(b.x), _sy(b.y));
      if (c.dx < _view.left - t || c.dx > _view.right + t) continue;
      final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final dir = sp > 0.01 ? Offset(b.vx / sp, b.vy / sp) : const Offset(1, 0);
      if (b.fromPlayer) {
        switch (b.weapon) {
          case WeaponKind.rockets:
            canvas.save();
            canvas.translate(c.dx, c.dy);
            canvas.rotate(math.atan2(dir.dy, dir.dx));
            Glow.draw(canvas, Offset(-t * 0.25, 0), t * 0.4, const Color(0xFFFF8C00).withValues(alpha: 0.8));
            _fill.color = const Color(0xFFE9EDFF);
            canvas.drawRRect(RRect.fromLTRBR(-t * 0.2, -t * 0.07, t * 0.2, t * 0.07, Radius.circular(t * 0.07)), _fill);
            _fill.color = const Color(0xFFFF8C00);
            canvas.drawRect(Rect.fromLTWH(t * 0.08, -t * 0.07, t * 0.12, t * 0.14), _fill);
            canvas.restore();
          case WeaponKind.laser:
            _streak(canvas, c, dir, t * 1.1, t * 0.12, weaponColor(WeaponKind.laser));
          case WeaponKind.spread:
            _streak(canvas, c, dir, t * 0.42, t * 0.09, weaponColor(WeaponKind.spread));
          case WeaponKind.blaster:
          case null:
            _streak(canvas, c, dir, t * 0.55, t * 0.1, _ion);
        }
      } else if (b.radius >= 0.3 && b.vy == 0) {
        // Boss slam shockwave: a burning wave rolling along the floor.
        final r = b.radius * t;
        final floor = c.dy + t * 0.35;
        Glow.drawOval(canvas, Rect.fromCenter(center: Offset(c.dx, floor - r * 0.6), width: r * 3.2, height: r * 2.6), _flare.withValues(alpha: 0.6));
        final lead = dir.dx.sign;
        _fill.color = const Color(0xFFFF7A45);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - lead * r * 1.4, floor)
            ..quadraticBezierTo(c.dx - lead * r * 0.4, floor - r * 2.4, c.dx + lead * r * 0.7, floor - r * 1.1)
            ..lineTo(c.dx + lead * r * 1.1, floor)
            ..close(),
          _fill,
        );
        _fill.color = const Color(0xFFFFE0C4);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - lead * r * 0.4, floor)
            ..quadraticBezierTo(c.dx, floor - r * 1.4, c.dx + lead * r * 0.6, floor - r * 0.6)
            ..lineTo(c.dx + lead * r * 0.7, floor)
            ..close(),
          _fill,
        );
        if (_rng.nextDouble() < 0.3) {
          _parts.add(_Part(b.x - lead * 0.2, b.y + 0.3, -lead * 1.5, -3 - _rng.nextDouble() * 2, 0.4, 0.07, _ember,
              chip: true, gravity: 20));
        }
      } else {
        // Hostile orb: ringed, hot core (threat reads by shape too).
        final r = math.max(3.0, b.radius * t);
        Glow.draw(canvas, c, r * 3.2, _ember.withValues(alpha: 0.7));
        _stroke
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, r * 0.35)
          ..color = _ember;
        canvas.drawCircle(c, r, _stroke);
        _fill.color = const Color(0xFFFFF1D6);
        canvas.drawCircle(c, r * 0.45, _fill);
      }
    }
  }

  static void _streak(Canvas canvas, Offset head, Offset dir, double len, double w, Color col) {
    final tail = head - dir * len;
    _line
      ..strokeWidth = w * 2.4
      ..color = col.withValues(alpha: 0.35);
    canvas.drawLine(tail, head, _line);
    _line
      ..strokeWidth = w
      ..color = col;
    canvas.drawLine(tail + (head - tail) * 0.25, head, _line);
    _line
      ..strokeWidth = w * 0.45
      ..color = const Color(0xFFFFFFFF);
    canvas.drawLine(tail + (head - tail) * 0.6, head, _line);
  }

  // ── Effects ─────────────────────────────────────────────────────────────
  static final _ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  void _paintEffects(Canvas canvas) {
    final t = _tp;
    for (final b in _bursts) {
      canvas.save();
      canvas.translate(_sx(b.x), _sy(b.y));
      b.burst.paint(canvas, b.age, const Color(0xFFFF7A45));
      canvas.restore();
    }
    for (final r in _rings) {
      final f = r.age / r.life;
      _ringPaint
        ..strokeWidth = (1 - f) * t * 0.12 + 0.5
        ..color = r.color.withValues(alpha: 0.85 * (1 - f));
      canvas.drawCircle(Offset(_sx(r.x), _sy(r.y)), t * (r.r0 + (r.r1 - r.r0) * (1 - (1 - f) * (1 - f))), _ringPaint);
    }
    for (final q in _parts) {
      if (q.smoke) continue;
      final f = q.age / q.life;
      final c = Offset(_sx(q.x), _sy(q.y));
      if (q.chip) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(q.rot);
        final s = q.size * t;
        _fill.color = q.color.withValues(alpha: (1 - f * f).clamp(0, 1));
        canvas.drawPath(
          Path()
            ..moveTo(-s, -s * 0.6)
            ..lineTo(s, -s * 0.2)
            ..lineTo(-s * 0.3, s * 0.8)
            ..close(),
          _fill,
        );
        canvas.restore();
      } else {
        Glow.draw(canvas, c, q.size * t * 2.6 * (1 - f * 0.5), q.color.withValues(alpha: 1 - f), hot: q.hot);
      }
    }
    for (final p in _pops) {
      _paintPop(canvas, p);
    }
  }

  static final Map<String, Paragraph> _popText = {};
  static final _layer = Paint();

  void _paintPop(Canvas canvas, _Pop p) {
    final key = '${p.text}|${p.color.toARGB32()}';
    final para = _popText.putIfAbsent(key, () {
      final b = ParagraphBuilder(ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(TextStyle(
          color: p.color,
          fontSize: 16,
          fontFamily: 'ChakraPetch',
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: Color(0xCC050817), blurRadius: 4)],
        ))
        ..addText(p.text);
      return b.build()..layout(const ParagraphConstraints(width: 140));
    });
    final f = p.age / 0.9;
    final x = _sx(p.x), y = _sy(p.y) - _tp * 0.6 * (1 - (1 - f) * (1 - f));
    final a = f < 0.65 ? 1.0 : 1 - (f - 0.65) / 0.35;
    _layer.color = Color.fromRGBO(0, 0, 0, a);
    canvas.saveLayer(Rect.fromLTWH(x - 70, y - 14, 140, 28), _layer);
    canvas.drawParagraph(para, Offset(x - 70, y - 11));
    canvas.restore();
  }

  // ── Hub preview ─────────────────────────────────────────────────────────
  static final _previewSky = <Size, Image>{};
  static final _previewRidge = <Size, Picture>{};

  /// A live window for the arcade hub's card: the dusk sky, a ridge, a strip
  /// of ground, the pilot running and firing at a grunt, the ship waiting.
  static void paintPreview(Canvas canvas, Size s, double t) {
    final sky = _previewSky.putIfAbsent(s, () {
      final rec = PictureRecorder();
      paintSky(Canvas(rec), Size(s.width, s.height * 1.35));
      return rec.endRecording().toImageSync(s.width.ceil(), (s.height * 1.35).ceil());
    });
    canvas.drawImageRect(sky, Rect.fromLTWH(0, s.height * 0.2, s.width, s.height * 1.15), Offset.zero & s, _imgPaint);
    final ridge = _previewRidge.putIfAbsent(s, () => _ridgePicture(s, s.width * 1.6, s.height * 0.68, s.height * 0.1, s.width / 14, const Color(0xFF1C1029), 8, true));
    final off = (t * 8) % (s.width * 1.6);
    for (final k in [0.0, 1.0]) {
      canvas.save();
      canvas.translate(-off + k * s.width * 1.6, 0);
      canvas.drawPicture(ridge);
      canvas.restore();
    }
    final tile = s.height / 4.2;
    final ground = s.height - tile * 0.9;
    // ground strip with the lit lip, scrolling
    _fill.color = _rockTop;
    canvas.drawRect(Rect.fromLTRB(0, ground, s.width, s.height), _fill);
    _fill.color = const Color(0xFF6E3A3E);
    canvas.drawRect(Rect.fromLTRB(0, ground, s.width, ground + tile * 0.14), _fill);
    _fill.color = const Color(0xFFE0915A);
    canvas.drawRect(Rect.fromLTRB(0, ground, s.width, ground + 2), _fill);
    final scroll = (t * tile * 2.5) % tile;
    _fill.color = const Color(0x660A0612);
    for (var x = -scroll; x < s.width; x += tile) {
      canvas.drawOval(Rect.fromCenter(center: Offset(x + tile * 0.4, ground + tile * 0.5), width: tile * 0.16, height: tile * 0.1), _fill);
    }
    // pilot running right, firing; a grunt ahead; shots in flight
    final pal = shipPaletteFor(CoinManager.instance.selectedSkin);
    final th = thrusterSpecFor(CoinManager.instance.selectedThruster);
    final px = s.width * 0.26;
    paintPilot(canvas, Offset(px, ground), tile, pal, th.color ?? pal.engine,
        facing: 1, aim: AimDir.right, pose: PilotPose.run, run: t * 12, time: t, muzzle: (t * 6).floor().isEven ? _ion : null);
    final gx = s.width * 0.74;
    paintGrunt(canvas, Offset(gx, ground), tile, -1, t, 'aim', (t * 0.8) % 1, ((t * 6) % 1) < 0.15 ? 1 : 0, false);
    for (var i = 0; i < 3; i++) {
      final f = ((t * 2.2) + i / 3) % 1;
      final x = px + tile * 0.6 + (gx - px - tile * 0.9) * f;
      _streak(canvas, Offset(x, ground - tile * 0.95), const Offset(1, 0), tile * 0.5, tile * 0.09, _ion);
    }
    // the ship waiting on the right
    canvas.save();
    canvas.translate(s.width * 0.93, ground - tile * 1.1);
    canvas.scale(tile * 1.9 / 42);
    ShipArt.paint(canvas, pal, time: t, thrust: 0.12, engine: th.color);
    canvas.restore();
  }
}

enum PilotPose { idle, run, jump, crouch }

class _Burst {
  final double x, y;
  final ExplosionBurst burst;
  double age = 0;
  _Burst(this.x, this.y, ExplosionStyle style, double radiusTiles, {bool big = false})
      : burst = ExplosionBurst(style: style, radius: 40 * radiusTiles, big: big);
}

class _Part {
  double x, y, vx, vy; // tiles
  final double life, size, drag, gravity, spin;
  final Color color;
  final bool hot, smoke, chip;
  double age = 0, rot = 0;
  _Part(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color,
      {this.hot = false, this.smoke = false, this.chip = false, this.drag = 0, this.gravity = 0, this.spin = 0});
}

class _Ring {
  final double x, y, life, r0, r1; // tiles
  final Color color;
  double age = 0;
  _Ring(this.x, this.y, this.color, this.life, this.r0, this.r1);
}

class _Pop {
  final double x, y;
  final String text;
  final Color color;
  double age = 0;
  _Pop(this.x, this.y, this.text, this.color);
}
