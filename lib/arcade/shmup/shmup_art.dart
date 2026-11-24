import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide Anchor;

import '../../coins/coin_manager.dart';
import '../../cosmetics/catalog.dart';
import '../../game/fx/glow.dart';
import '../../game/render/explosion_art.dart';
import '../../game/render/ship_art.dart';
import '../../game/render/trail_art.dart';
import '../thread/thread_art.dart';
import 'shmup_sim.dart';

/// Rift Runner's drawing (the designer's file). The contract with
/// [ShmupGame]:
///
///   * `ShmupArt(ShmupSim sim)` is a Flame [Component] added to the game; the
///     sim is settable (the game swaps it when the screen is resized before a
///     round starts). It only READS the sim, never changes it.
///   * `onEvent(ShmupEvent e)` is called once per sim event, in order.
///   * `onRestart()`: a new round began, clear any leftover effects.
///   * `static void paintPreview(Canvas, Size, double t)` paints a small live
///     still for the arcade hub card ([t] = seconds, ever increasing).
///   * The component fills the game: `size` = screen px; one sim unit is
///     `size.x / sim.width` px and the field is `sim.height` units tall.
///
/// Look: a dust nebula lit by a red giant just off the right edge (warm
/// umber, sienna, sand), so your ion ship, shots, drones and shield pop
/// against it. Per stage (`level.theme`): 0 "Asteroid Belt" (basalt rock with
/// a sand-lit edge), 1 "Crystal Vein" (darker, malachite bands and a copper
/// edge); other numbers reuse these in turn. The sky is baked once per size
/// and theme; far asteroids and dust streaks are cached pictures scrolled
/// with `sim.travelled`; the rock bands are two paths a frame with a lit
/// edge facing the channel. Enemies share one material (dark hull, flare rim
/// and eye) with a silhouette per kind; hostile shots are ringed flare orbs,
/// yours are streaks in the gun's colour. The boss (`bossStyle` 0 "The
/// Breaker", 1 "The Prism") is a plated shell with two cannon pods and an
/// iris core that opens once both cannons are gone. Colour keeps the app's
/// meanings: flare = danger, ion = you, gold = NOVA, plasma = upgrades,
/// mint = repairs. No per-frame blur or layers: glows are [Glow] sprites.
class ShmupArt extends Component {
  ShmupArt(this.sim);

  ShmupSim sim;
  Vector2 _size = Vector2.zero();
  double _t = 0;
  double _k = 1; // px per sim unit

  // ── Effects ─────────────────────────────────────────────────────────────
  final _bursts = <_Burst>[];
  final _rings = <_Ring>[];
  final _sparks = <_Spark>[];
  final _rng = math.Random(3);
  double _shake = 0;
  double _hurt = 0; // flare edge wash, 1 -> 0
  double _muzzle = 0;
  double _shieldFlash = 0;
  double _iris = 0; // boss core iris, 0 shut -> 1 open
  double _bossBoomCd = 0;
  double _lastScroll = 0;

  // Engine wake (px, newest first).
  static const _trailN = 22;
  final _tx = List<double>.filled(_trailN, 0);
  final _ty = List<double>.filled(_trailN, 0);
  int _trailCount = 0;

  // ── Cached per size/theme ───────────────────────────────────────────────
  Image? _sky;
  Picture? _far;
  Picture? _streaks;
  double _farW = 1;
  Size _bakedSize = Size.zero;
  int _bakedTheme = -1;
  List<Rect> _edgeRects = const [];
  List<Shader> _edgeShaders = const [];

  bool get _reduce => PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  _Look get _look => _Look.of(sim.level.theme);

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _size = size.clone();
  }

  void _bakeIfNeeded() {
    final s = Size(_size.x, _size.y);
    final theme = sim.level.theme % _Look.count;
    if (s == _bakedSize && theme == _bakedTheme && _sky != null) return;
    _sky?.dispose();
    _bakedSize = s;
    _bakedTheme = theme;
    final look = _Look.of(theme);
    final rec = PictureRecorder();
    look.paintSky(Canvas(rec), s);
    _sky = rec.endRecording().toImageSync(s.width.ceil(), s.height.ceil());
    _farW = s.width * 1.6;
    _far = look.farAsteroids(s, _farW);
    _streaks = _Look.dustStreaks(s, _farW, look);
    final e = s.width * 0.09;
    const on = Color(0x70FF4766), off = Color(0x00FF4766);
    _edgeRects = [
      Rect.fromLTWH(0, 0, s.width, e),
      Rect.fromLTWH(0, s.height - e, s.width, e),
      Rect.fromLTWH(0, 0, e, s.height),
      Rect.fromLTWH(s.width - e, 0, e, s.height),
    ];
    _edgeShaders = [
      Gradient.linear(Offset.zero, Offset(0, e), [on, off]),
      Gradient.linear(Offset(0, s.height), Offset(0, s.height - e), [on, off]),
      Gradient.linear(Offset.zero, Offset(e, 0), [on, off]),
      Gradient.linear(Offset(s.width, 0), Offset(s.width - e, 0), [on, off]),
    ];
  }

  // ── Events ──────────────────────────────────────────────────────────────
  ExplosionStyle _style() => explosionStyleFor(CoinManager.instance.selectedExplosion);

  void onEvent(ShmupEvent e) {
    final x = e.x, y = e.y;
    switch (e.kind) {
      case ShmupEventKind.shoot:
        _muzzle = 0.06;
      case ShmupEventKind.enemyHit:
        _spray(x, y, 3, const Color(0xFFBFF6FF), 18);
      case ShmupEventKind.deflect:
        _spray(x, y, 4, const Color(0xFFE9EDFF), 26);
        _rings.add(_Ring(x, y, 0.5, 2.6, 0.18, const Color(0xFFE9EDFF)));
      case ShmupEventKind.enemyKilled:
        final r = switch (e.enemy) {
          EnemyKind.carrier => 8.0,
          EnemyKind.gunship => 6.0,
          EnemyKind.turret => 4.6,
          _ => 3.6,
        };
        _bursts.add(_Burst(x, y, _style(), r * _k * 1.6, big: e.enemy == EnemyKind.carrier));
        _spray(x, y, 6, const Color(0xFFFFB27A), 30);
        _shake = math.max(_shake, e.enemy == EnemyKind.carrier ? 0.5 : 0.15);
      case ShmupEventKind.mineBlast:
        _rings.add(_Ring(x, y, 2, ShmupTuning.blastRadius, 0.35, const Color(0xFFFF4766)));
        _bursts.add(_Burst(x, y, _style(), 5 * _k * 1.6));
        _shake = math.max(_shake, 0.35);
      case ShmupEventKind.darterLock:
        _rings.add(_Ring(x, y, 1, 6, 0.3, const Color(0xFFFF4766)));
      case ShmupEventKind.shipHit:
        _hurt = 1;
        _shake = math.max(_shake, 0.55);
        _spray(x, y, 8, const Color(0xFFFF8A9C), 34);
      case ShmupEventKind.shieldBlock:
        _shieldFlash = 1;
        _rings.add(_Ring(x, y, ShmupTuning.shipR, ShmupTuning.shipR * 2.6, 0.35, const Color(0xFF4DE8FF)));
      case ShmupEventKind.terrainHit:
        _spray(x, y, 7, _look.edge, 30);
      case ShmupEventKind.lifeLost:
        _bursts.add(_Burst(x, y, _style(), 9 * _k * 1.6, big: true));
        _rings.add(_Ring(x, y, 2, 22, 0.55, const Color(0xFFFF4766)));
        _shake = 1;
        _hurt = 1;
        _trailCount = 0;
      case ShmupEventKind.pickup:
        final c = e.pickup == PickupKind.repair ? const Color(0xFF4DFFB0) : const Color(0xFFA07CFF);
        _rings.add(_Ring(x, y, 2, 11, 0.4, c));
        _spray(x, y, 8, c, 26);
      case ShmupEventKind.shard:
        _rings.add(_Ring(x, y, 1, 7, 0.3, const Color(0xFFFFC23D)));
        _spray(x, y, 6, const Color(0xFFFFE08A), 22);
      case ShmupEventKind.bossAppear:
        _shake = math.max(_shake, 0.4);
      case ShmupEventKind.bossPart:
        _bursts.add(_Burst(x, y, _style(), 9 * _k * 1.6, big: true));
        _spray(x, y, 12, const Color(0xFFFFB27A), 40);
        _shake = math.max(_shake, 0.8);
      case ShmupEventKind.bossPhase:
        final b = sim.boss;
        if (b != null) _rings.add(_Ring(b.x, b.y, b.shellR, b.shellR * 1.8, 0.5, const Color(0xFFFF4766)));
        _shake = math.max(_shake, 0.5);
      case ShmupEventKind.midBossDown:
        _bursts.add(_Burst(x, y, _style(), 14 * _k * 1.6, big: true));
        _rings.add(_Ring(x, y, 4, 26, 0.6, const Color(0xFFFFB27A)));
        _shake = 1;
      case ShmupEventKind.bossDown:
        _bursts.add(_Burst(x, y, _style(), 22 * _k * 1.6, big: true));
        _rings.add(_Ring(x, y, 6, 46, 0.8, const Color(0xFFFFB27A)));
        _shake = 1;
      case ShmupEventKind.stageClear:
        _rings.add(_Ring(sim.ship.x, sim.ship.y, 4, 30, 0.7, const Color(0xFF4DE8FF)));
      case ShmupEventKind.enemyShot:
      case ShmupEventKind.warning:
      case ShmupEventKind.stageStart:
      case ShmupEventKind.gameOver:
        break;
    }
  }

  void _spray(double x, double y, int n, Color c, double speed) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final v = speed * (0.4 + _rng.nextDouble() * 0.6);
      _sparks.add(_Spark(x, y, math.cos(a) * v, math.sin(a) * v, 0.25 + _rng.nextDouble() * 0.25, c));
    }
  }

  void onRestart() {
    _bursts.clear();
    _rings.clear();
    _sparks.clear();
    _trailCount = 0;
    _hurt = 0;
    _shake = 0;
    _iris = 0;
    _lastScroll = sim.scrollX;
  }

  // ── Update ──────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    _t += dt;
    if (_size.x == 0) return;
    _k = _size.x / sim.width;
    _shake = math.max(0, _shake - dt * 2.8);
    _hurt = math.max(0, _hurt - dt * 2.2);
    _muzzle = math.max(0, _muzzle - dt);
    _shieldFlash = math.max(0, _shieldFlash - dt * 3);
    for (final b in _bursts) {
      b.age += dt;
    }
    _bursts.removeWhere((b) => b.age > b.burst.life);
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age >= r.life);
    for (final s in _sparks) {
      s.age += dt;
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vx *= 1 - 3 * dt;
      s.vy *= 1 - 3 * dt;
    }
    _sparks.removeWhere((s) => s.age >= s.life);

    final b = sim.boss;
    final open = b != null && b.exposed(b.core) ? 1.0 : 0.0;
    _iris += (open - _iris) * math.min(1, dt * 3);
    if (b != null && b.dying) {
      _bossBoomCd -= dt;
      if (_bossBoomCd <= 0) {
        _bossBoomCd = 0.22;
        final a = _rng.nextDouble() * math.pi * 2;
        final d = b.shellR * _rng.nextDouble();
        _bursts.add(_Burst(b.x + math.cos(a) * d, b.y + math.sin(a) * d, _style(), 5 * _k * 1.6));
        _shake = math.max(_shake, 0.35);
      }
    }

    // Engine wake: points drift left with the world; a new one at the nozzle.
    final scrolled = (sim.scrollX - _lastScroll).clamp(0.0, 20.0);
    _lastScroll = sim.scrollX;
    for (var i = 0; i < _trailCount; i++) {
      _tx[i] -= scrolled * _k + 0.6;
    }
    final showShip = sim.phase != ShmupPhase.over;
    if (showShip) {
      for (var i = math.min(_trailCount, _trailN - 1); i > 0; i--) {
        _tx[i] = _tx[i - 1];
        _ty[i] = _ty[i - 1];
      }
      _tx[0] = (sim.ship.x - ShmupTuning.shipR * 0.9) * _k;
      _ty[0] = sim.ship.y * _k;
      _trailCount = math.min(_trailCount + 1, _trailN);
    } else if (_trailCount > 0) {
      _trailCount--;
    }
  }

  // ── Render ──────────────────────────────────────────────────────────────
  static final _fill = Paint()..isAntiAlias = true;
  static final _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _add = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  static final _img = Paint()..filterQuality = FilterQuality.low;
  static final _wash = Paint()..blendMode = BlendMode.plus;

  Offset _p(double x, double y) => Offset(x * _k, y * _k);

  @override
  void render(Canvas canvas) {
    if (_size.x == 0) return;
    _k = _size.x / sim.width;
    _bakeIfNeeded();
    final look = _look;
    final full = Offset.zero & Size(_size.x, _size.y);
    canvas.drawImageRect(_sky!, Offset.zero & _bakedSize, full, _img);
    _scrollPicture(canvas, _far!, sim.travelled * _k * 0.18);
    if (!_reduce) _scrollPicture(canvas, _streaks!, sim.travelled * _k * 0.75);

    canvas.save();
    if (_shake > 0 && !_reduce) {
      final s = _shake * _shake * _k * 1.2;
      canvas.translate((_rng.nextDouble() * 2 - 1) * s, (_rng.nextDouble() * 2 - 1) * s);
    }
    _terrain(canvas, look);
    _pickups(canvas);
    _enemies(canvas);
    _boss(canvas, look);
    _playerBullets(canvas);
    _ship(canvas);
    _enemyBullets(canvas);
    _effects(canvas);
    canvas.restore();

    if (_hurt > 0.01) {
      _wash.color = Color.fromRGBO(255, 255, 255, (_hurt * 0.85).clamp(0.0, 1.0));
      for (var i = 0; i < 4; i++) {
        _wash.shader = _edgeShaders[i];
        canvas.drawRect(_edgeRects[i], _wash);
      }
      _wash.shader = null;
    }
  }

  void _scrollPicture(Canvas canvas, Picture pic, double px) {
    final off = px % _farW;
    for (final k in [0.0, 1.0]) {
      canvas.save();
      canvas.translate(-off + k * _farW, 0);
      canvas.drawPicture(pic);
      canvas.restore();
    }
  }

  // ── Terrain ─────────────────────────────────────────────────────────────
  void _terrain(Canvas canvas, _Look look) {
    const step = 2.0;
    final w = sim.width + step * 2;
    final h = sim.height;
    final top = Path()..moveTo(-step * _k, 0);
    final bottom = Path()..moveTo(-step * _k, h * _k);
    final topEdge = Path();
    final botEdge = Path();
    final topIn = Path()..moveTo(-step * _k, 0);
    final botIn = Path()..moveTo(-step * _k, h * _k);
    // Sample on a grid fixed to the world so the outline doesn't shimmer.
    final phase = sim.scrollX % step;
    var first = true;
    for (var x = -step - phase; x <= w; x += step) {
      final c = sim.ceilingAt(x), f = h - sim.floorAt(x);
      top.lineTo(x * _k, c * _k);
      bottom.lineTo(x * _k, f * _k);
      topIn.lineTo(x * _k, math.max(0, c - 5) * _k);
      botIn.lineTo(x * _k, math.min(h, f + 5) * _k);
      if (first) {
        topEdge.moveTo(x * _k, c * _k);
        botEdge.moveTo(x * _k, f * _k);
        first = false;
      } else {
        topEdge.lineTo(x * _k, c * _k);
        botEdge.lineTo(x * _k, f * _k);
      }
    }
    for (final p in [top, topIn]) {
      p
        ..lineTo(w * _k, 0)
        ..close();
    }
    for (final p in [bottom, botIn]) {
      p
        ..lineTo(w * _k, h * _k)
        ..close();
    }
    _fill.color = look.rock;
    canvas.drawPath(top, _fill);
    canvas.drawPath(bottom, _fill);
    _fill.color = look.rockDeep;
    canvas.drawPath(topIn, _fill);
    canvas.drawPath(botIn, _fill);

    // Veins (Crystal Vein) or facets (Asteroid Belt), fixed to the world.
    final wx0 = sim.scrollX;
    if (look.veins) {
      _stroke
        ..strokeWidth = math.max(1, _k * 0.5)
        ..color = look.vein;
      canvas.save();
      canvas.translate(0, -2.4 * _k);
      canvas.drawPath(topEdge, _stroke);
      canvas.restore();
      canvas.save();
      canvas.translate(0, 2.4 * _k);
      canvas.drawPath(botEdge, _stroke);
      canvas.restore();
      _stroke.color = look.vein.withValues(alpha: 0.35);
      canvas.save();
      canvas.translate(0, -7 * _k);
      canvas.drawPath(topEdge, _stroke);
      canvas.restore();
      canvas.save();
      canvas.translate(0, 7 * _k);
      canvas.drawPath(botEdge, _stroke);
      canvas.restore();
    }
    _stroke
      ..strokeWidth = math.max(1, _k * 0.35)
      ..color = look.facet;
    final first9 = (wx0 / 9).ceil() * 9.0;
    for (var wx = first9; wx < wx0 + w; wx += 9) {
      final x = wx - wx0;
      final hsh = (wx.round() * 2654435761) & 0xffff;
      final lean = ((hsh & 31) / 31 - 0.5) * 4;
      final c = sim.ceilingAt(x);
      if (c > 4) canvas.drawLine(_p(x, c - 0.6), _p(x + lean, c - math.min(6, c * 0.6)), _stroke);
      final f = h - sim.floorAt(x);
      if (h - f > 4) canvas.drawLine(_p(x, f + 0.6), _p(x - lean, f + math.min(6, (h - f) * 0.6)), _stroke);
    }

    // The lit edge facing the channel: a soft bloom and a crisp line.
    _add
      ..strokeWidth = _k * 2.4
      ..color = look.bloom;
    canvas.drawPath(topEdge, _add);
    canvas.drawPath(botEdge, _add);
    _stroke
      ..strokeWidth = math.max(1.2, _k * 0.45)
      ..color = look.edge;
    canvas.drawPath(topEdge, _stroke);
    canvas.drawPath(botEdge, _stroke);
  }

  // ── Pick-ups ────────────────────────────────────────────────────────────
  void _pickups(Canvas canvas) {
    for (final p in sim.pickups) {
      if (p.dead) continue;
      final c = _p(p.x, p.y + math.sin(p.age * 3) * 1.1);
      if (p.kind == PickupKind.shard) {
        ThreadArt.paintShard(canvas, c, _t + p.x * 0.1);
        continue;
      }
      paintCapsule(canvas, c, _k * 4.4, p.kind, _t);
    }
  }

  /// A power-up capsule: a chamfered diamond in a plasma frame (upgrades), or
  /// a mint one for repairs, with the pick-up's glyph. [r] = half size, px.
  static void paintCapsule(Canvas canvas, Offset c, double r, PickupKind kind, double t) {
    final repair = kind == PickupKind.repair;
    final frame = repair ? const Color(0xFF4DFFB0) : const Color(0xFFA07CFF);
    Glow.draw(canvas, c, r * 3.2, frame.withValues(alpha: 0.35 + 0.1 * math.sin(t * 4)));
    final cut = r * 0.45;
    final body = Path()
      ..moveTo(c.dx - r + cut, c.dy - r)
      ..lineTo(c.dx + r - cut, c.dy - r)
      ..lineTo(c.dx + r, c.dy - r + cut)
      ..lineTo(c.dx + r, c.dy + r - cut)
      ..lineTo(c.dx + r - cut, c.dy + r)
      ..lineTo(c.dx - r + cut, c.dy + r)
      ..lineTo(c.dx - r, c.dy + r - cut)
      ..lineTo(c.dx - r, c.dy - r + cut)
      ..close();
    _fill.color = repair ? const Color(0xF0082A22) : const Color(0xF01E1636);
    canvas.drawPath(body, _fill);
    _stroke
      ..strokeWidth = math.max(1.2, r * 0.13)
      ..color = frame;
    canvas.drawPath(body, _stroke);
    paintGlyph(canvas, c, r * 0.62, kind);
  }

  /// Glyph per pick-up, shared with the HUD's loadout chip.
  static void paintGlyph(Canvas canvas, Offset c, double s, PickupKind kind) {
    final col = glyphColor(kind);
    _stroke
      ..strokeWidth = math.max(1.3, s * 0.22)
      ..color = col;
    switch (kind) {
      case PickupKind.spread:
        for (final a in [-0.42, 0.0, 0.42]) {
          canvas.drawLine(c.translate(-s * 0.7, 0), c.translate(-s * 0.7 + math.cos(a) * s * 1.5, math.sin(a) * s * 1.5), _stroke);
        }
      case PickupKind.laser:
        canvas.drawLine(c.translate(-s * 0.9, 0), c.translate(s * 0.7, 0), _stroke);
        _fill.color = const Color(0xFFFFFFFF);
        canvas.drawCircle(c.translate(s * 0.8, 0), s * 0.2, _fill);
      case PickupKind.homing:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - s * 0.9, c.dy + s * 0.6)
            ..quadraticBezierTo(c.dx - s * 0.1, c.dy - s * 1.1, c.dx + s * 0.8, c.dy - s * 0.1),
          _stroke,
        );
        _fill.color = col;
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + s * 1.0, c.dy)
            ..lineTo(c.dx + s * 0.35, c.dy - s * 0.55)
            ..lineTo(c.dx + s * 0.5, c.dy + s * 0.3)
            ..close(),
          _fill,
        );
      case PickupKind.option:
        _fill.color = col;
        canvas.drawCircle(c, s * 0.42, _fill);
        canvas.drawCircle(c, s * 0.85, _stroke);
      case PickupKind.shield:
        final hex = Path();
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3 + math.pi / 6;
          final p = c.translate(math.cos(a) * s * 0.9, math.sin(a) * s * 0.9);
          i == 0 ? hex.moveTo(p.dx, p.dy) : hex.lineTo(p.dx, p.dy);
        }
        hex.close();
        canvas.drawPath(hex, _stroke);
      case PickupKind.repair:
        _fill.color = col;
        canvas.drawRect(Rect.fromCenter(center: c, width: s * 1.6, height: s * 0.5), _fill);
        canvas.drawRect(Rect.fromCenter(center: c, width: s * 0.5, height: s * 1.6), _fill);
      case PickupKind.shard:
        break;
    }
  }

  static Color glyphColor(PickupKind kind) => switch (kind) {
        PickupKind.spread => const Color(0xFFF4A800),
        PickupKind.laser => const Color(0xFFB8F6FF),
        PickupKind.homing => const Color(0xFFC38BE0),
        PickupKind.option || PickupKind.shield => const Color(0xFF4DE8FF),
        PickupKind.repair => const Color(0xFF4DFFB0),
        PickupKind.shard => const Color(0xFFFFC23D),
      };

  /// Each gun's shot colour (matches the main game's weapons).
  static Color weaponColor(WeaponKind w) => switch (w) {
        WeaponKind.pulse => const Color(0xFF4DE8FF),
        WeaponKind.spread => const Color(0xFFF4A800),
        WeaponKind.laser => const Color(0xFFB8F6FF),
        WeaponKind.homing => const Color(0xFFC38BE0),
      };

  static PickupKind weaponGlyph(WeaponKind w) => switch (w) {
        WeaponKind.pulse => PickupKind.laser,
        WeaponKind.spread => PickupKind.spread,
        WeaponKind.laser => PickupKind.laser,
        WeaponKind.homing => PickupKind.homing,
      };

  // ── Enemies ─────────────────────────────────────────────────────────────
  static const _hull = Color(0xFF241319);
  static const _hullLit = Color(0xFF3A2129);
  static const _flare = Color(0xFFFF4766);

  void _enemies(Canvas canvas) {
    for (final e in sim.enemies) {
      if (e.dead) continue;
      final c = _p(e.x, e.y);
      final s = e.r * _k;
      final hit = (e.flash > 0 ? 1.0 : 0.0);
      switch (e.kind) {
        case EnemyKind.drone:
          _paintKite(canvas, c, s, hit, _t + e.id);
        case EnemyKind.turret:
          _paintTurret(canvas, c, s, e, hit);
        case EnemyKind.darter:
          _paintDarter(canvas, c, s, e, hit);
        case EnemyKind.mine:
          _paintMine(canvas, c, s, e, hit);
        case EnemyKind.gunship:
          _paintGunship(canvas, c, s, e, hit);
        case EnemyKind.carrier:
          _paintCarrier(canvas, c, s, e, hit);
        case EnemyKind.midBoss:
          _paintMidBoss(canvas, c, s, e, hit);
      }
      if ((e.kind == EnemyKind.gunship || e.kind == EnemyKind.carrier) && e.hp < e.maxHp && e.hp > 0) {
        final w = s * 1.8;
        final r = Rect.fromLTWH(c.dx - w / 2, c.dy - s * 1.45, w, math.max(2, _k * 0.6));
        _fill.color = const Color(0xAA050817);
        canvas.drawRect(r.inflate(1), _fill);
        _fill.color = _flare;
        canvas.drawRect(Rect.fromLTWH(r.left, r.top, w * e.hpFraction, r.height), _fill);
      }
    }
  }

  static Color _hullColor(double hit) => Color.lerp(_hull, const Color(0xFFFFFFFF), hit * 0.75)!;

  static void _rimmed(Canvas canvas, Path path, double hit, double w) {
    _fill.color = _hullColor(hit);
    canvas.drawPath(path, _fill);
    _stroke
      ..strokeWidth = w
      ..color = _flare.withValues(alpha: 0.85);
    canvas.drawPath(path, _stroke);
  }

  /// Squadron fighter: a dark arrowhead pointing left with swept fins and a
  /// flare eye at the nose.
  static void _paintKite(Canvas canvas, Offset c, double s, double hit, double t) {
    final p = Path()
      ..moveTo(c.dx - s * 1.25, c.dy)
      ..lineTo(c.dx + s * 0.35, c.dy - s * 0.85)
      ..lineTo(c.dx + s * 1.05, c.dy - s * 1.05)
      ..lineTo(c.dx + s * 0.65, c.dy)
      ..lineTo(c.dx + s * 1.05, c.dy + s * 1.05)
      ..lineTo(c.dx + s * 0.35, c.dy + s * 0.85)
      ..close();
    _rimmed(canvas, p, hit, math.max(1, s * 0.12));
    final eye = c.translate(-s * 0.55, 0);
    Glow.draw(canvas, eye, s * 1.3, _flare.withValues(alpha: 0.7 + 0.2 * math.sin(t * 6)));
    _fill.color = const Color(0xFFFFD0D8);
    canvas.drawCircle(eye, s * 0.16, _fill);
    // engine sparks behind
    Glow.draw(canvas, c.translate(s * 0.85, 0), s * 0.7, const Color(0xFFFF8A4A).withValues(alpha: 0.5));
  }

  void _paintTurret(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final dir = e.anchor == Anchor.ceiling ? -1.0 : 1.0; // which way is "up" (into the channel)
    final base = c.translate(0, s * 0.5 * dir);
    // A squat mount bolted to the rock.
    final mount = Path()
      ..moveTo(base.dx - s * 1.3, base.dy)
      ..lineTo(base.dx - s * 0.9, base.dy - s * 0.7 * dir)
      ..lineTo(base.dx + s * 0.9, base.dy - s * 0.7 * dir)
      ..lineTo(base.dx + s * 1.3, base.dy)
      ..close();
    _fill.color = Color.lerp(_hullLit, const Color(0xFFFFFFFF), hit * 0.6)!;
    canvas.drawPath(mount, _fill);
    final dome = base.translate(0, -s * 0.75 * dir);
    // Barrel tracks the ship.
    final a = math.atan2(sim.ship.y * _k - dome.dy, sim.ship.x * _k - dome.dx);
    _stroke
      ..strokeWidth = s * 0.42
      ..color = const Color(0xFF5A3A42);
    canvas.drawLine(dome, dome + Offset(math.cos(a), math.sin(a)) * s * 1.6, _stroke);
    _fill.color = _hullColor(hit);
    canvas.drawCircle(dome, s * 0.75, _fill);
    _stroke
      ..strokeWidth = math.max(1, s * 0.1)
      ..color = _flare.withValues(alpha: 0.7);
    canvas.drawCircle(dome, s * 0.75, _stroke);
    final ready = (1 - (e.fireCd / 0.6)).clamp(0.0, 1.0);
    Glow.draw(canvas, dome, s * (0.9 + ready), _flare.withValues(alpha: 0.4 + 0.5 * ready));
    _fill.color = const Color(0xFFFFD0D8);
    canvas.drawCircle(dome, s * 0.18, _fill);
  }

  void _paintDarter(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final locking = e.stage == 1;
    final aim = _p(e.aimX, e.aimY);
    final a = locking ? math.atan2(aim.dy - c.dy, aim.dx - c.dx) : math.atan2(e.vy, e.vx == 0 && e.vy == 0 ? -1 : e.vx);
    final d = Offset(math.cos(a), math.sin(a));
    final n = Offset(-d.dy, d.dx);
    if (locking) {
      // The tell: a dashed flare line to where it will dash, a reticle there.
      final from = c + d * s * 1.4;
      final len = (aim - from).distance;
      final dashes = (len / (_k * 3)).floor();
      _stroke
        ..strokeWidth = math.max(1, _k * 0.3)
        ..color = _flare.withValues(alpha: 0.55 + 0.35 * math.sin(_t * 18).abs());
      for (var i = 0; i < dashes; i += 2) {
        canvas.drawLine(from + d * (i * _k * 3), from + d * (math.min(len, (i + 1) * _k * 3)), _stroke);
      }
      final rr = _k * 3;
      canvas.drawCircle(aim, rr, _stroke);
      for (var i = 0; i < 4; i++) {
        final q = i * math.pi / 2;
        final u = Offset(math.cos(q), math.sin(q));
        canvas.drawLine(aim + u * rr * 1.3, aim + u * rr * 1.9, _stroke);
      }
    }
    final p = Path()
      ..moveTo(c.dx + d.dx * s * 1.5, c.dy + d.dy * s * 1.5)
      ..lineTo(c.dx - d.dx * s + n.dx * s * 0.7, c.dy - d.dy * s + n.dy * s * 0.7)
      ..lineTo(c.dx - d.dx * s * 0.5, c.dy - d.dy * s * 0.5)
      ..lineTo(c.dx - d.dx * s - n.dx * s * 0.7, c.dy - d.dy * s - n.dy * s * 0.7)
      ..close();
    _rimmed(canvas, p, hit, math.max(1, s * 0.12));
    Glow.draw(canvas, c - d * s * 0.9, s * (locking ? 1.6 : 1.1), _flare.withValues(alpha: locking ? 0.9 : 0.55));
  }

  void _paintMine(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final rot = e.age * 0.8;
    _stroke
      ..strokeWidth = math.max(1.2, s * 0.22)
      ..color = const Color(0xFF5A3A30);
    for (var i = 0; i < 8; i++) {
      final a = rot + i * math.pi / 4;
      final u = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + u * s * 0.8, c + u * s * 1.45, _stroke);
    }
    _fill.color = _hullColor(hit);
    canvas.drawCircle(c, s * 0.95, _fill);
    _stroke
      ..strokeWidth = math.max(1, s * 0.08)
      ..color = const Color(0xFF6A4438);
    canvas.drawCircle(c, s * 0.95, _stroke);
    // The core blinks faster as the ship gets close.
    final dist = math.sqrt(math.pow(e.x - sim.ship.x, 2) + math.pow(e.y - sim.ship.y, 2));
    final rate = dist < 25 ? 9.0 : 3.0;
    final on = math.sin(_t * rate + e.id) > 0;
    Glow.draw(canvas, c, s * (on ? 2.2 : 1.4), _flare.withValues(alpha: on ? 0.75 : 0.35));
    _fill.color = on ? const Color(0xFFFFD0D8) : _flare;
    canvas.drawCircle(c, s * 0.3, _fill);
  }

  void _paintGunship(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final p = Path()
      ..moveTo(c.dx - s * 1.4, c.dy)
      ..lineTo(c.dx - s * 0.3, c.dy - s * 0.75)
      ..lineTo(c.dx + s * 1.1, c.dy - s * 0.55)
      ..lineTo(c.dx + s * 0.8, c.dy)
      ..lineTo(c.dx + s * 1.1, c.dy + s * 0.55)
      ..lineTo(c.dx - s * 0.3, c.dy + s * 0.75)
      ..close();
    // side pods
    final charge = (1 - (e.fireCd / 0.45)).clamp(0.0, 1.0);
    for (final dy in [-1.0, 1.0]) {
      final pod = Rect.fromCenter(center: c.translate(s * 0.1, dy * s * 0.95), width: s * 1.3, height: s * 0.5);
      _fill.color = Color.lerp(_hullLit, const Color(0xFFFFFFFF), hit * 0.6)!;
      canvas.drawRRect(RRect.fromRectAndRadius(pod, Radius.circular(s * 0.2)), _fill);
      Glow.draw(canvas, pod.centerLeft, s * (0.6 + charge * 1.1), _flare.withValues(alpha: 0.35 + 0.6 * charge));
    }
    _rimmed(canvas, p, hit, math.max(1, s * 0.09));
    _fill.color = const Color(0xFFFFD0D8);
    canvas.drawCircle(c.translate(-s * 0.7, 0), s * 0.14, _fill);
    Glow.draw(canvas, c.translate(-s * 0.7, 0), s * 0.9, _flare.withValues(alpha: 0.6));
  }

  void _paintCarrier(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final w = s * 2.3, h = s * 1.15;
    final hullP = Path()
      ..moveTo(c.dx - w * 0.5, c.dy - h * 0.2)
      ..lineTo(c.dx - w * 0.38, c.dy - h * 0.5)
      ..lineTo(c.dx + w * 0.5, c.dy - h * 0.45)
      ..lineTo(c.dx + w * 0.5, c.dy + h * 0.45)
      ..lineTo(c.dx - w * 0.38, c.dy + h * 0.5)
      ..lineTo(c.dx - w * 0.5, c.dy + h * 0.2)
      ..close();
    _rimmed(canvas, hullP, hit, math.max(1, s * 0.07));
    // armour plates
    _stroke
      ..strokeWidth = math.max(1, s * 0.05)
      ..color = const Color(0xFF4A2A34);
    for (var i = 1; i < 4; i++) {
      final x = c.dx - w * 0.38 + w * 0.88 * i / 4;
      canvas.drawLine(Offset(x, c.dy - h * 0.46), Offset(x, c.dy + h * 0.46), _stroke);
    }
    // the hold: a plasma light (it carries an upgrade)
    final hold = Rect.fromCenter(center: c.translate(w * 0.05, 0), width: w * 0.32, height: h * 0.34);
    Glow.draw(canvas, hold.center, s * 1.3, const Color(0xFFA07CFF).withValues(alpha: 0.45 + 0.15 * math.sin(_t * 3)));
    _fill.color = const Color(0xFFA07CFF);
    canvas.drawRRect(RRect.fromRectAndRadius(hold, Radius.circular(h * 0.08)), _fill);
    // cracks as it weakens
    _stroke
      ..strokeWidth = math.max(1, s * 0.06)
      ..color = const Color(0xFFFF8A4A);
    if (e.hpFraction < 0.66) {
      canvas.drawLine(c.translate(-w * 0.3, -h * 0.4), c.translate(-w * 0.18, -h * 0.05), _stroke);
    }
    if (e.hpFraction < 0.33) {
      canvas.drawLine(c.translate(w * 0.32, h * 0.42), c.translate(w * 0.22, h * 0.08), _stroke);
      Glow.draw(canvas, c.translate(w * 0.27, h * 0.25), s * 0.8, const Color(0xFFFF8A4A).withValues(alpha: 0.5));
    }
    // engine
    Glow.draw(canvas, c.translate(w * 0.52, 0), s * 0.9, const Color(0xFFFF8A4A).withValues(alpha: 0.55));
  }

  /// The mid-boss: a smaller cousin of the stage boss, one cannon.
  void _paintMidBoss(Canvas canvas, Offset c, double s, ShmupEnemy e, double hit) {
    final look = _look;
    final heat = e.phase == 2 ? 0.5 + 0.5 * math.sin(_t * 6) : 0.0;
    _paintShell(canvas, c, s, 6, look, hit, 0.6 + 0.4 * heat, e.age * 0.2);
    // the cannon at the front
    final cn = c.translate(-s * 0.85, 0);
    _fill.color = Color.lerp(_hullLit, const Color(0xFFFFFFFF), hit * 0.6)!;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: cn, width: s * 0.8, height: s * 0.5), Radius.circular(s * 0.12)), _fill);
    Glow.draw(canvas, cn.translate(-s * 0.4, 0), s * 0.8, _flare.withValues(alpha: 0.6 + 0.3 * heat));
    // eye
    Glow.draw(canvas, c, s * 0.9, look.core.withValues(alpha: 0.7));
    _fill.color = const Color(0xFFFFE6D8);
    canvas.drawCircle(c, s * 0.18, _fill);
  }

  /// A plated round shell: [n] armour plates with seams (flare for the
  /// Breaker, copper for the Prism) and a lit rim.
  static void _paintShell(Canvas canvas, Offset c, double r, int n, _Look look, double hit, double seam, double rot) {
    _fill.color = Color.lerp(look.shellDeep, const Color(0xFFFFFFFF), hit * 0.5)!;
    canvas.drawCircle(c, r, _fill);
    for (var i = 0; i < n; i++) {
      final a0 = rot + i * math.pi * 2 / n + 0.06;
      final a1 = a0 + math.pi * 2 / n - 0.12;
      final p = Path()
        ..moveTo(c.dx + math.cos(a0) * r * 0.97, c.dy + math.sin(a0) * r * 0.97)
        ..arcTo(Rect.fromCircle(center: c, radius: r * 0.97), a0, a1 - a0, false)
        ..lineTo(c.dx + math.cos(a1) * r * 0.55, c.dy + math.sin(a1) * r * 0.55)
        ..arcTo(Rect.fromCircle(center: c, radius: r * 0.55), a1, a0 - a1, false)
        ..close();
      _fill.color = Color.lerp(look.shell, const Color(0xFFFFFFFF), hit * 0.6)!;
      canvas.drawPath(p, _fill);
      if (look.veins) {
        // crystal facet highlight
        _stroke
          ..strokeWidth = math.max(1, r * 0.03)
          ..color = look.vein;
        canvas.drawLine(
            Offset(c.dx + math.cos(a0 + 0.1) * r * 0.62, c.dy + math.sin(a0 + 0.1) * r * 0.62),
            Offset(c.dx + math.cos(a1 - 0.1) * r * 0.9, c.dy + math.sin(a1 - 0.1) * r * 0.9),
            _stroke);
      }
    }
    _add
      ..strokeWidth = math.max(1, r * 0.035)
      ..color = look.seam.withValues(alpha: (0.35 + 0.55 * seam).clamp(0.0, 1.0));
    for (var i = 0; i < n; i++) {
      final a = rot + i * math.pi * 2 / n;
      canvas.drawLine(Offset(c.dx + math.cos(a) * r * 0.56, c.dy + math.sin(a) * r * 0.56),
          Offset(c.dx + math.cos(a) * r * 0.96, c.dy + math.sin(a) * r * 0.96), _add);
    }
    _stroke
      ..strokeWidth = math.max(1, r * 0.025)
      ..color = look.edge.withValues(alpha: 0.6);
    canvas.drawCircle(c, r, _stroke);
  }

  // ── Boss ────────────────────────────────────────────────────────────────
  void _boss(Canvas canvas, _Look look) {
    final b = sim.boss;
    if (b == null) return;
    final c = _p(b.x, b.y);
    final r = b.shellR * _k;
    final fade = b.dying ? (1 - b.dyingFor / ShmupTuning.clearSeconds).clamp(0.0, 1.0) : 1.0;
    final bl = _Look.forBoss(b.style);
    Glow.draw(canvas, c, r * 2.4, bl.core.withValues(alpha: 0.18 * fade));
    if (b.dying) {
      // Plates fly off.
      final k = (b.dyingFor / ShmupTuning.clearSeconds).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1 + k * 0.25);
      canvas.translate(-c.dx, -c.dy);
      _paintShellFading(canvas, c, r, bl, fade, k);
      canvas.restore();
      return;
    }
    final phase3 = b.phase >= 3 ? 0.5 + 0.5 * math.sin(_t * 9) : 0.0;
    final seam = b.phase == 1 ? 0.25 : (b.phase == 2 ? 0.6 : 0.8 + 0.2 * phase3);
    final hitShell = 0.0;
    _paintShell(canvas, c, r, 8, bl, hitShell, seam, b.age * 0.05);
    // Cannon pods (upper / lower).
    for (final part in [b.upper, b.lower]) {
      final pc = _p(b.x + part.dx, b.y + part.dy);
      final pr = part.r * _k;
      final hit = part.flash > 0 ? 1.0 : 0.0;
      if (part.alive) {
        final pod = Path()
          ..moveTo(pc.dx - pr * 1.5, pc.dy - pr * 0.55)
          ..lineTo(pc.dx + pr * 0.9, pc.dy - pr * 0.85)
          ..lineTo(pc.dx + pr * 0.9, pc.dy + pr * 0.85)
          ..lineTo(pc.dx - pr * 1.5, pc.dy + pr * 0.55)
          ..close();
        _rimmed(canvas, pod, hit, math.max(1, pr * 0.1));
        final ready = (1 - (b.fireCd / 0.5)).clamp(0.0, 1.0);
        Glow.draw(canvas, pc.translate(-pr * 1.5, 0), pr * (0.7 + ready), _flare.withValues(alpha: 0.45 + 0.5 * ready));
        _fill.color = const Color(0xFFFFD0D8);
        canvas.drawCircle(pc.translate(-pr * 1.4, 0), pr * 0.16, _fill);
        // its health, as a thin flare arc
        _stroke
          ..strokeWidth = math.max(1.2, pr * 0.07)
          ..color = _flare.withValues(alpha: 0.55);
        canvas.drawArc(Rect.fromCircle(center: pc, radius: pr * 1.35), -math.pi / 2, math.pi * 2 * part.hp / part.maxHp, false, _stroke);
      } else {
        // A smoking stump with an ember glow.
        _fill.color = const Color(0xFF2A1A16);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: pc.translate(pr * 0.2, 0), width: pr * 1.1, height: pr * 1.1), Radius.circular(pr * 0.2)), _fill);
        Glow.draw(canvas, pc, pr * (1 + 0.2 * math.sin(_t * 7 + part.dy)), const Color(0xFFFF8A4A).withValues(alpha: 0.4));
        _stroke
          ..strokeWidth = math.max(1, pr * 0.08)
          ..color = const Color(0xFFFF8A4A);
        canvas.drawLine(pc.translate(-pr * 0.4, -pr * 0.3), pc.translate(pr * 0.1, pr * 0.2), _stroke);
      }
    }
    // Core: an iris of six plates over a hot eye; opens once both cannons are gone.
    final core = b.core;
    final cc = _p(b.x + core.dx, b.y + core.dy);
    final cr = core.r * _k;
    final hot = core.flash > 0 ? 1.0 : 0.0;
    Glow.draw(canvas, cc, cr * (1.6 + _iris * 1.4 + phase3 * 0.4), bl.core.withValues(alpha: 0.35 + 0.55 * _iris));
    _fill.color = Color.lerp(bl.core, const Color(0xFFFFFFFF), 0.3 + hot * 0.6)!;
    canvas.drawCircle(cc, cr * (0.35 + 0.25 * _iris), _fill);
    final open = _iris;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + b.age * 0.3;
      final tip = cc + Offset(math.cos(a + 1.05), math.sin(a + 1.05)) * cr * (0.05 + 0.85 * open);
      final p = Path()
        ..moveTo(cc.dx + math.cos(a) * cr, cc.dy + math.sin(a) * cr)
        ..lineTo(cc.dx + math.cos(a + 1.05) * cr, cc.dy + math.sin(a + 1.05) * cr)
        ..lineTo(tip.dx, tip.dy)
        ..close();
      _fill.color = bl.shell;
      canvas.drawPath(p, _fill);
      _stroke
        ..strokeWidth = math.max(1, cr * 0.05)
        ..color = bl.seam.withValues(alpha: 0.4 + 0.5 * open);
      canvas.drawPath(p, _stroke);
    }
    _stroke
      ..strokeWidth = math.max(1.2, cr * 0.08)
      ..color = bl.edge.withValues(alpha: 0.7);
    canvas.drawCircle(cc, cr, _stroke);
  }

  void _paintShellFading(Canvas canvas, Offset c, double r, _Look look, double fade, double k) {
    for (var i = 0; i < 8; i++) {
      final a0 = i * math.pi / 4 + 0.06;
      final a1 = a0 + math.pi / 4 - 0.12;
      final mid = (a0 + a1) / 2;
      final off = Offset(math.cos(mid), math.sin(mid)) * r * k * (1.2 + (i % 3) * 0.4);
      final p = Path()
        ..moveTo(c.dx + math.cos(a0) * r, c.dy + math.sin(a0) * r)
        ..arcTo(Rect.fromCircle(center: c, radius: r), a0, a1 - a0, false)
        ..lineTo(c.dx + math.cos(a1) * r * 0.55, c.dy + math.sin(a1) * r * 0.55)
        ..arcTo(Rect.fromCircle(center: c, radius: r * 0.55), a1, a0 - a1, false)
        ..close();
      canvas.save();
      canvas.translate(off.dx, off.dy);
      _fill.color = look.shell.withValues(alpha: fade);
      canvas.drawPath(p, _fill);
      canvas.restore();
    }
    Glow.draw(canvas, c, r * (0.8 + k), look.core.withValues(alpha: 0.9 * fade), hot: true);
  }

  // ── Shots ───────────────────────────────────────────────────────────────
  void _playerBullets(Canvas canvas) {
    for (final b in sim.playerBullets) {
      if (b.dead) continue;
      final w = WeaponKind.values[b.style.clamp(0, WeaponKind.values.length - 1)];
      final col = weaponColor(w);
      final head = _p(b.x, b.y);
      final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final d = sp == 0 ? const Offset(1, 0) : Offset(b.vx / sp, b.vy / sp);
      final len = switch (w) {
        WeaponKind.laser => 11.0,
        WeaponKind.homing => 4.0,
        _ => 6.0,
      } *
          _k;
      final width = (w == WeaponKind.laser ? 1.1 : (w == WeaponKind.homing ? 1.3 : 0.9)) * _k;
      _add
        ..strokeWidth = width * 2.8
        ..color = col.withValues(alpha: 0.6);
      canvas.drawLine(head - d * len, head, _add);
      Glow.draw(canvas, head, width * 2.6, col.withValues(alpha: 0.7));
      _add
        ..strokeWidth = width
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9);
      canvas.drawLine(head - d * len * 0.75, head, _add);
      if (w == WeaponKind.homing) {
        Glow.draw(canvas, head, _k * 2.4, col.withValues(alpha: 0.8), hot: true);
      }
    }
  }

  void _enemyBullets(Canvas canvas) {
    for (final b in sim.enemyBullets) {
      if (b.dead) continue;
      final c = _p(b.x, b.y);
      final r = b.r * _k * (b.style == 2 ? 1.25 : 1.0);
      Glow.draw(canvas, c, r * 3.2, _flare.withValues(alpha: b.style == 1 ? 0.75 : 0.55));
      _stroke
        ..strokeWidth = math.max(1.2, r * 0.32)
        ..color = b.style == 2 ? const Color(0xFFFF7AB0) : _flare;
      canvas.drawCircle(c, r, _stroke);
      _fill.color = const Color(0xFFFFE0E6);
      canvas.drawCircle(c, r * 0.42, _fill);
    }
  }

  // ── Ship ────────────────────────────────────────────────────────────────
  void _ship(Canvas canvas) {
    if (sim.phase == ShmupPhase.over) return;
    final s = sim.ship;
    final pal = shipPaletteFor(CoinManager.instance.selectedSkin);
    final th = thrusterSpecFor(CoinManager.instance.selectedThruster);
    final engine = th.color ?? pal.engine;
    TrailArt.paint(canvas, _tx, _ty, _trailCount, _trailN, engine, th.trail, _t);
    // Wingman drones.
    for (final d in s.drones) {
      final c = _p(d.x, d.y);
      _stroke
        ..strokeWidth = 1
        ..color = const Color(0x334DE8FF);
      canvas.drawLine(c, _p(s.x, s.y), _stroke);
      Glow.draw(canvas, c, _k * 3.6, const Color(0xFF4DE8FF).withValues(alpha: 0.6));
      _fill.color = const Color(0xFFDDF9FF);
      canvas.drawCircle(c, _k * 1.2, _fill);
      _stroke
        ..strokeWidth = math.max(1, _k * 0.3)
        ..color = const Color(0xFF4DE8FF);
      canvas.drawCircle(c, _k * 1.9, _stroke);
    }
    final c = _p(s.x, s.y);
    if (sim.phase == ShmupPhase.ready) {
      // "This is you": a soft ion ring breathing round the ship.
      final f = (_t % 1.4) / 1.4;
      _stroke
        ..strokeWidth = math.max(1, _k * 0.4)
        ..color = const Color(0xFF4DE8FF).withValues(alpha: 0.6 * (1 - f));
      canvas.drawCircle(c, _k * ShmupTuning.shipR * (1.3 + f * 1.2), _stroke);
    }
    final blink = s.invuln > 0 && (_t * 14).floor().isEven;
    if (!blink) {
      if (s.hurtFlash > 0) Glow.draw(canvas, c, _k * 8, _flare.withValues(alpha: (s.hurtFlash * 2).clamp(0.0, 0.8)));
      _drawShip(canvas, c, _k * ShmupTuning.shipR, pal, engine, _t);
      if (_muzzle > 0) {
        Glow.draw(canvas, c.translate(_k * ShmupTuning.shipR * 1.05, 0), _k * 2.6, weaponColor(s.weapon).withValues(alpha: 0.85), hot: true);
      }
    }
    if (s.shield) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      ShieldArt.paint(canvas, _k * (ShmupTuning.shipR + 2.2), shieldSpecFor(CoinManager.instance.selectedShieldSkin),
          time: _t, flash: _shieldFlash > 0.5);
      canvas.restore();
    }
  }

  /// The equipped ship pointing right, wingspan about 2.2 x [r] px.
  static void _drawShip(Canvas canvas, Offset at, double r, ShipPalette pal, Color engine, double t) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(math.pi / 2);
    canvas.scale(r * 2.2 / 42);
    ShipArt.paint(canvas, pal, time: t, thrust: 0.7 + 0.3 * math.sin(t * 9).abs(), engine: engine);
    canvas.restore();
  }

  // ── Effects ─────────────────────────────────────────────────────────────
  void _effects(Canvas canvas) {
    for (final b in _bursts) {
      canvas.save();
      canvas.translate(b.x * _k, b.y * _k);
      b.burst.paint(canvas, b.age, const Color(0xFFFF8A4A));
      canvas.restore();
    }
    for (final r in _rings) {
      final f = r.age / r.life;
      _add
        ..strokeWidth = math.max(1, _k * 0.6 * (1 - f) + 0.5)
        ..color = r.color.withValues(alpha: 0.8 * (1 - f));
      canvas.drawCircle(_p(r.x, r.y), (r.r0 + (r.r1 - r.r0) * (1 - (1 - f) * (1 - f))) * _k, _add);
    }
    for (final s in _sparks) {
      final f = s.age / s.life;
      _add
        ..strokeWidth = math.max(1, _k * 0.35)
        ..color = s.color.withValues(alpha: 1 - f);
      final p = _p(s.x, s.y);
      canvas.drawLine(p, p - Offset(s.vx, s.vy) * (_k * 0.02), _add);
    }
  }

  // ── Hub preview ─────────────────────────────────────────────────────────
  static final _previewSky = <Size, Image>{};
  static final _previewFar = <Size, Picture>{};

  /// A small live window for the arcade hub card: the dust nebula, sand-lit
  /// rock scrolling past top and bottom, a squadron crossing, the equipped
  /// ship weaving with its wake and firing, and a NOVA shard.
  static void paintPreview(Canvas canvas, Size s, double t) {
    final look = _Look.of(0);
    final sky = _previewSky.putIfAbsent(s, () {
      final rec = PictureRecorder();
      look.paintSky(Canvas(rec), s);
      return rec.endRecording().toImageSync(s.width.ceil(), s.height.ceil());
    });
    canvas.drawImageRect(sky, Offset.zero & s, Offset.zero & s, _img);
    final far = _previewFar.putIfAbsent(s, () => look.farAsteroids(s, s.width * 1.6));
    final off = (t * 6) % (s.width * 1.6);
    for (final k in [0.0, 1.0]) {
      canvas.save();
      canvas.translate(-off + k * s.width * 1.6, 0);
      canvas.drawPicture(far);
      canvas.restore();
    }
    // Rock bands.
    final top = Path()..moveTo(0, 0);
    final bot = Path()..moveTo(0, s.height);
    final te = Path();
    final be = Path();
    for (var x = 0.0; x <= s.width + 6; x += 6) {
      final wx = x + t * 30;
      final ct = s.height * (0.13 + 0.06 * math.sin(wx * 0.031) + 0.03 * math.sin(wx * 0.09));
      final cb = s.height * (0.86 - 0.06 * math.sin(wx * 0.027 + 2) - 0.03 * math.sin(wx * 0.11));
      top.lineTo(x, ct);
      bot.lineTo(x, cb);
      if (x == 0) {
        te.moveTo(x, ct);
        be.moveTo(x, cb);
      } else {
        te.lineTo(x, ct);
        be.lineTo(x, cb);
      }
    }
    top
      ..lineTo(s.width + 6, 0)
      ..close();
    bot
      ..lineTo(s.width + 6, s.height)
      ..close();
    _fill.color = look.rock;
    canvas.drawPath(top, _fill);
    canvas.drawPath(bot, _fill);
    _add
      ..strokeWidth = 4
      ..color = look.bloom;
    canvas.drawPath(te, _add);
    canvas.drawPath(be, _add);
    _stroke
      ..strokeWidth = 1.4
      ..color = look.edge;
    canvas.drawPath(te, _stroke);
    canvas.drawPath(be, _stroke);
    // A squadron on a sine path, crossing.
    final u = s.height / 40;
    for (var i = 0; i < 4; i++) {
      final x = s.width * 1.1 - ((t * 26 + i * 16) % (s.width * 1.3));
      final y = s.height * 0.42 + math.sin(x * 0.045) * s.height * 0.12;
      _paintKite(canvas, Offset(x, y), u * 1.15, 0, t + i);
    }
    // A shard drifting.
    final sx = s.width * 1.05 - ((t * 18) % (s.width * 1.2));
    canvas.save();
    canvas.translate(sx, s.height * 0.66);
    canvas.scale(0.75);
    ThreadArt.paintShard(canvas, Offset.zero, t);
    canvas.restore();
    // The ship weaving, its wake and its shots.
    final pal = shipPaletteFor(CoinManager.instance.selectedSkin);
    final th = thrusterSpecFor(CoinManager.instance.selectedThruster);
    final engine = th.color ?? pal.engine;
    final ship = Offset(s.width * 0.22, s.height * 0.5 + math.sin(t * 1.6) * s.height * 0.12);
    _add
      ..strokeWidth = u * 1.4
      ..color = engine.withValues(alpha: 0.35);
    final wake = Path()..moveTo(ship.dx - u * 3, ship.dy);
    for (var i = 1; i <= 8; i++) {
      wake.lineTo(ship.dx - u * 3 - i * u * 3, s.height * 0.5 + math.sin((t - i * 0.06) * 1.6) * s.height * 0.12);
    }
    canvas.drawPath(wake, _add);
    for (var i = 0; i < 3; i++) {
      final x = ship.dx + u * 5 + ((t * s.width * 1.2 + i * s.width * 0.25) % (s.width * 0.8));
      _add
        ..strokeWidth = u * 0.9
        ..color = const Color(0x664DE8FF);
      canvas.drawLine(Offset(x - u * 4, ship.dy), Offset(x, ship.dy), _add);
    }
    _drawShip(canvas, ship, u * 4.2, pal, engine, t);
  }
}

/// A stage look: sky, rock and boss materials.
class _Look {
  final int id;
  final Color skyTop, skyMid, skyBottom, sun, dustDeep, dustMid, dustLight, far;
  final Color rock, rockDeep, edge, bloom, facet, vein;
  final bool veins;
  final Color shell, shellDeep, seam, core;
  const _Look({
    required this.id,
    required this.skyTop,
    required this.skyMid,
    required this.skyBottom,
    required this.sun,
    required this.dustDeep,
    required this.dustMid,
    required this.dustLight,
    required this.far,
    required this.rock,
    required this.rockDeep,
    required this.edge,
    required this.bloom,
    required this.facet,
    required this.vein,
    required this.veins,
    required this.shell,
    required this.shellDeep,
    required this.seam,
    required this.core,
  });

  static const count = 2;

  /// Asteroid Belt: basalt with a sand-lit edge; the Breaker in basalt with
  /// flare seams and a flare-hot core.
  static const belt = _Look(
    id: 0,
    skyTop: Color(0xFF0F0806),
    skyMid: Color(0xFF22120B),
    skyBottom: Color(0xFF150B07),
    sun: Color(0xFFC8602A),
    dustDeep: Color(0xFF4A2513),
    dustMid: Color(0xFF8A4520),
    dustLight: Color(0xFFD08447),
    far: Color(0xFF3A2116),
    rock: Color(0xFF21140F),
    rockDeep: Color(0xFF0C0706),
    edge: Color(0xFFE9B98A),
    bloom: Color(0x40FF9A5A),
    facet: Color(0xFF3A2519),
    vein: Color(0x00000000),
    veins: false,
    shell: Color(0xFF2E1D18),
    shellDeep: Color(0xFF1C1110),
    seam: Color(0xFFFF4766),
    core: Color(0xFFFF4766),
  );

  /// Crystal Vein: deeper and darker, malachite bands, a copper edge; the
  /// Prism in faceted green crystal with copper seams and a copper heart
  /// (orange, never NOVA gold).
  static const vein_ = _Look(
    id: 1,
    skyTop: Color(0xFF0B0605),
    skyMid: Color(0xFF1A0E0A),
    skyBottom: Color(0xFF0E0806),
    sun: Color(0xFFB0502A),
    dustDeep: Color(0xFF3A1C10),
    dustMid: Color(0xFF6E3518),
    dustLight: Color(0xFFB06A3A),
    far: Color(0xFF2A1A12),
    rock: Color(0xFF16120E),
    rockDeep: Color(0xFF080605),
    edge: Color(0xFFE08A55),
    bloom: Color(0x40E08A55),
    facet: Color(0xFF1F6B4F),
    vein: Color(0x9939A57A),
    veins: true,
    shell: Color(0xFF1F4A3C),
    shellDeep: Color(0xFF0F241D),
    seam: Color(0xFFE08A55),
    core: Color(0xFFFF9A4A),
  );

  static _Look of(int theme) => theme % count == 1 ? vein_ : belt;
  static _Look forBoss(int style) => style % count == 1 ? vein_ : belt;

  /// Warm black, the red giant's glow off the right edge, slow dust clouds
  /// (soft radial gradients, no blur) and warm stars.
  void paintSky(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.linear(Offset.zero, Offset(0, s.height), [skyTop, skyMid, skyBottom], const [0, 0.45, 1]),
    );
    final sunC = Offset(s.width * 1.1, s.height * 0.45);
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.radial(sunC, s.width * 1.3, [sun.withValues(alpha: 0.32), sun.withValues(alpha: 0.1), sun.withValues(alpha: 0)], const [0, 0.45, 1]),
    );
    final rnd = math.Random(7 + id);
    for (var i = 0; i < 7; i++) {
      final col = [dustDeep, dustMid, dustLight][i % 3];
      final cc = Offset(rnd.nextDouble() * s.width, s.height * (0.15 + rnd.nextDouble() * 0.7));
      final rr = s.width * (0.25 + rnd.nextDouble() * 0.35);
      final a = i % 3 == 2 ? 0.16 : 0.34;
      c.save();
      c.translate(cc.dx, cc.dy);
      c.scale(1.6, 0.6);
      c.drawCircle(
        Offset.zero,
        rr,
        Paint()..shader = Gradient.radial(Offset.zero, rr, [col.withValues(alpha: a), col.withValues(alpha: 0)], const [0, 1]),
      );
      c.restore();
    }
    if (id == 1) {
      // a faint malachite haze deep in the vein
      final cc = Offset(s.width * 0.3, s.height * 0.6);
      c.drawCircle(
        cc,
        s.width * 0.6,
        Paint()..shader = Gradient.radial(cc, s.width * 0.6, const [Color(0x1A39A57A), Color(0x0039A57A)], const [0, 1]),
      );
    }
    final star = Paint();
    for (var i = 0; i < 110; i++) {
      star.color = Color.fromRGBO(255, 232, 210, 0.15 + rnd.nextDouble() * 0.5);
      c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height), 0.4 + rnd.nextDouble() * 0.8, star);
    }
  }

  /// Far asteroids: hazy, low-contrast lumps with a hairline lit rim. They
  /// never collide, and look it.
  Picture farAsteroids(Size s, double w) {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    final rnd = math.Random(19 + id);
    final body = Paint()..color = far.withValues(alpha: 0.75);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = dustLight.withValues(alpha: 0.28);
    final n = (w / (s.width * 0.22)).ceil();
    for (var i = 0; i < n; i++) {
      final cx = (i + rnd.nextDouble() * 0.6) * w / n;
      final cy = s.height * (0.2 + rnd.nextDouble() * 0.6);
      final r = s.width * (0.018 + rnd.nextDouble() * 0.05);
      final path = Path();
      const k = 9;
      final pts = <Offset>[];
      for (var j = 0; j < k; j++) {
        final a = j * math.pi * 2 / k;
        final rr = r * (0.75 + rnd.nextDouble() * 0.35);
        pts.add(Offset(cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.8));
      }
      path.addPolygon(pts, true);
      c.drawPath(path, body);
      c.drawPath(Path()..addPolygon([pts[7], pts[8], pts[0], pts[1]], false), rim);
    }
    return rec.endRecording();
  }

  /// Faint horizontal dust streaks drifting left: the speed of the run.
  static Picture dustStreaks(Size s, double w, _Look look) {
    final rec = PictureRecorder();
    final c = Canvas(rec);
    final rnd = math.Random(5);
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;
    for (var i = 0; i < 34; i++) {
      final x = rnd.nextDouble() * w, y = s.height * (0.12 + rnd.nextDouble() * 0.76);
      final len = s.width * (0.06 + rnd.nextDouble() * 0.16);
      p.color = look.dustLight.withValues(alpha: 0.06 + rnd.nextDouble() * 0.1);
      c.drawLine(Offset(x, y), Offset(x + len, y), p);
    }
    return rec.endRecording();
  }
}

class _Burst {
  final double x, y;
  final ExplosionBurst burst;
  double age = 0;
  _Burst(this.x, this.y, ExplosionStyle style, double radiusPx, {bool big = false})
      : burst = ExplosionBurst(style: style, radius: radiusPx, big: big);
}

class _Ring {
  final double x, y, r0, r1, life;
  final Color color;
  double age = 0;
  _Ring(this.x, this.y, this.r0, this.r1, this.life, this.color);
}

class _Spark {
  double x, y, vx, vy;
  final double life;
  final Color color;
  double age = 0;
  _Spark(this.x, this.y, this.vx, this.vy, this.life, this.color);
}
