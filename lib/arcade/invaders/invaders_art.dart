import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';

import '../../coins/coin_manager.dart';
import '../../cosmetics/catalog.dart';
import '../../game/fx/glow.dart';
import '../../game/render/explosion_art.dart';
import '../../game/render/ship_art.dart';
import '../thread/thread_art.dart';
import 'invaders_sim.dart';

/// Swarm Siege's drawing (the designer's file). Contract with the game:
///   * `InvadersArt(InvadersSim sim)` and a settable [sim] (the game swaps
///     the sim when the screen is resized before a round starts),
///   * [onEvent] is called once per [InvadersEvent]; [onRestart] clears
///     leftover effects,
///   * the component fills the game (`size` = screen px); one sim unit is
///     `size.x / sim.width` px; it only READS the sim.
///
/// Look ("polar night over a frozen moon"): a baked teal-black sky with two
/// aurora bands and the moon's icy horizon; the swarm in obsidian chitin
/// with flare rims and eyes that pulse on every march step, each kind its
/// own creature (all flip between two poses per step):
///   * elite = armored crab, guard = mantis, grunt = beetle;
///   * armored = a plated isopod: three steel plates; once `cracked` the
///     middle plate is gone and its flare core shows, the rest are crazed;
///     `hurt` flashes the plates (not the screen);
///   * diver = a wasp: wings folded in formation, spread and buzzing in the
///     wind-up (flare eye charging), swept back and pointed along its path
///     while diving (ember trail), open and gliding on the way back; a
///     dashed ghost marks its empty slot;
///   * splitter = a twin-lobed pod with a glowing seam (it will split
///     there); its minis are single lobes with one eye;
///   * shielder = a warden with a frost crest and two emitter arms; frost
///     tethers run to the neighbors it covers, each wrapped in a hex ward
///     that flares when it absorbs a shot.
/// The brood carrier (boss waves): a segmented hive hull sliding along the
/// top, gun pods that charge visibly before each shell, a launch maw that
/// opens for every drone, cracks and embers as it weakens, a rim (not
/// body) flash on hits; it settles in from above when it appears. Its
/// health bar is in the HUD. Drones: small buzzing darts pointed along
/// their path.
/// Crystalline ice bunkers drawn cell by cell; the gold hive barge; your
/// equipped ship on an ion rail with shot pips, its equipped shield when
/// shielded, and a mount per gun (twin wing cannons, spread fins, a laser
/// lance, a rapid triple barrel, homing pods), all in plasma. Shots: ion
/// streaks up (spread angled, laser a tall beam, missiles little darts with
/// curving exhaust); ember ringed orbs down, and the carrier's big shells
/// with a spiked outer ring. Capsules: GUNS are plasma cartridges (tall
/// cut-corner frames), UTILITIES (shield, slow field, smart bomb) are ion
/// orbs with turning notches, so the two read apart at a glance. The slow
/// field frosts the whole field (cold tint, drifting flakes, glazed aliens);
/// the smart bomb is one soft ion ring and a brief low wash (one flash,
/// alpha under 0.35). Explosions in the equipped style. Everything is drawn
/// in sim units (one canvas scale); glows are cached sprites.
class InvadersArt extends Component {
  InvadersArt(this.sim);

  InvadersSim sim;
  Vector2 get size => _size;
  Vector2 _size = Vector2.zero();

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _size = size;
  }

  double _t = 0;
  final _rng = math.Random();
  double _pulse = 0; // eye pulse on each march step, 1 → 0
  int _lastMarch = -1;
  double _shake = 0;
  double _hurt = 0;
  double _muzzle = 0;
  double _shieldHit = 0;
  double _tilt = 0;

  double _bomb = 0; // smart bomb wash, 1 -> 0
  double _slowFade = 0; // slow field frost, 0..1
  double _maw = 0; // carrier launch maw open, 1 -> 0
  double _carrierIn = 9; // seconds since the carrier appeared
  final _ward = <Alien, double>{}; // shield-bearer ward flash per alien, 1 -> 0
  final _prev = Expando<Offset>(); // last position of divers / drones (heading)
  final _heading = Expando<double>();
  final _flakes = <_Flake>[];

  final _bursts = <_Burst>[];
  final _parts = <_Part>[];
  final _rings = <_Ring>[];
  final _pops = <_Pop>[];

  // ── Events ──────────────────────────────────────────────────────────────
  void onEvent(InvadersEvent e) {
    switch (e.kind) {
      case InvadersEventKind.shoot:
        _muzzle = 0.06;
      case InvadersEventKind.alienKilled:
        _bursts.add(_Burst(e.x, e.y, _style(), e.alien == AlienKind.elite ? 4.2 : 3.4));
        for (var i = 0; i < 5; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          final sp = 14 + _rng.nextDouble() * 18;
          _parts.add(_Part(e.x, e.y, math.cos(a) * sp, math.sin(a) * sp, 0.55, 0.7, _chitinLit, chip: true, gravity: 40, spin: 10));
        }
        _shake = math.max(_shake, 0.12);
      case InvadersEventKind.march:
        break; // marchCount drives the pulse (see update)
      case InvadersEventKind.alienShot:
        _parts.add(_Part(e.x, e.y, 0, 0, 0.18, 2.2, _ember, hot: true));
      case InvadersEventKind.bunkerChip:
        for (var i = 0; i < 4; i++) {
          final a = -math.pi * _rng.nextDouble();
          final sp = 10 + _rng.nextDouble() * 14;
          _parts.add(_Part(e.x, e.y, math.cos(a) * sp, math.sin(a) * sp, 0.4, 0.45, _ice, chip: true, gravity: 60, spin: 14));
        }
      case InvadersEventKind.mothershipAppear:
        break;
      case InvadersEventKind.mothershipHit:
        _bursts.add(_Burst(e.x, e.y, _style(), 6, big: true));
        _rings.add(_Ring(e.x, e.y, _gold, 0.6, 2, 16));
        _pops.add(_Pop(e.x, e.y + 4, 'NOVA shard +${InvadersSim.mothershipPoints}', _gold));
        for (var i = 0; i < 16; i++) {
          final a = i / 16 * math.pi * 2;
          _parts.add(_Part(e.x, e.y, math.cos(a) * 30, math.sin(a) * 30, 0.6, 0.8, _gold, hot: true, drag: 3));
        }
        _shake = math.max(_shake, 0.4);
      case InvadersEventKind.shipHit:
        _bursts.add(_Burst(e.x, e.y, _style(), 6, big: true));
        _hurt = 1;
        _shake = 0.8;
      case InvadersEventKind.shieldBlock:
        _shieldHit = 1;
        _rings.add(_Ring(e.x, e.y, _ion, 0.4, 4, 12));
      case InvadersEventKind.powerup:
        final k = e.powerup ?? PowerupKind.twin;
        _rings.add(_Ring(e.x, e.y, _powerColor(k), 0.45, 2, 12));
        _pops.add(_Pop(e.x, e.y - 8, powerName(k), _powerColor(k)));
      case InvadersEventKind.powerupDrop:
        _rings.add(_Ring(e.x, e.y, _plasma, 0.35, 1, 6));
      case InvadersEventKind.waveClear:
        _rings.add(_Ring(sim.width / 2, sim.height * 0.35, _ion, 0.8, 4, sim.width * 0.6));
      case InvadersEventKind.waveStart:
        break;
      case InvadersEventKind.alienHit:
        _rings.add(_Ring(e.x, e.y, _steel, 0.25, 1, 5));
        for (var i = 0; i < 3; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          _parts.add(_Part(e.x, e.y, math.cos(a) * 20, math.sin(a) * 20, 0.3, 0.6, _steel, hot: true));
        }
      case InvadersEventKind.alienShielded:
        // Light up the ward on the alien that took it.
        Alien? best;
        var bd = 1e9;
        for (final a in sim.aliens) {
          if (!a.alive || !a.covered) continue;
          final d = (a.x - e.x).abs() + (a.y - e.y).abs();
          if (d < bd) {
            bd = d;
            best = a;
          }
        }
        if (best != null) _ward[best] = 1;
        for (var i = 0; i < 4; i++) {
          final a = math.pi + _rng.nextDouble() * math.pi;
          _parts.add(_Part(e.x, e.y + 3, math.cos(a) * 16, -math.sin(a) * 16, 0.3, 0.45, _frost, chip: true, gravity: 30, spin: 12));
        }
      case InvadersEventKind.alienSplit:
        _rings.add(_Ring(e.x, e.y, _flare, 0.3, 1, 6));
        for (var i = 0; i < 6; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          _parts.add(_Part(e.x, e.y, math.cos(a) * 18, math.sin(a) * 18, 0.35, 0.6, _ember, hot: true, drag: 4));
        }
      case InvadersEventKind.diveStart:
        _rings.add(_Ring(e.x, e.y, _flare, 0.55, 7, 1.5));
      case InvadersEventKind.crash:
        _bursts.add(_Burst(e.x, e.y, _style(), 3.6));
        _shake = math.max(_shake, 0.3);
      case InvadersEventKind.droneSpawn:
        _maw = 1;
        _parts.add(_Part(e.x, e.y, 0, 0, 0.25, 1.6, _ember, hot: true));
      case InvadersEventKind.droneKilled:
        _bursts.add(_Burst(e.x, e.y, _style(), 2.6));
      case InvadersEventKind.carrierAppear:
        _carrierIn = 0;
        _shake = math.max(_shake, 0.4);
      case InvadersEventKind.carrierHit:
        _parts.add(_Part(e.x, e.y, 0, 0, 0.14, 1.4, const Color(0xFFFFD9C2)));
        for (var i = 0; i < 3; i++) {
          final a = -math.pi * _rng.nextDouble();
          _parts.add(_Part(e.x + (_rng.nextDouble() - 0.5) * 4, e.y, math.cos(a) * 18, -math.sin(a) * 18, 0.35, 0.7, _ember, hot: true));
        }
        for (var i = 0; i < 2; i++) {
          final a = -math.pi * _rng.nextDouble();
          _parts.add(_Part(e.x, e.y, math.cos(a) * 14, -math.sin(a) * 14, 0.6, 0.6, _chitinLit, chip: true, gravity: 50, spin: 10));
        }
      case InvadersEventKind.carrierDown:
        for (var i = 0; i < 5; i++) {
          _bursts.add(_Burst(e.x + (i - 2) * 6, e.y + (i.isOdd ? 2 : -2), _style(), 5, big: true));
        }
        for (var i = 0; i < 14; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          final sp = 16 + _rng.nextDouble() * 26;
          _parts.add(
            _Part(e.x + (_rng.nextDouble() - 0.5) * 20, e.y, math.cos(a) * sp, math.sin(a) * sp - 10, 1.1, 1.2, _chitinLit, chip: true, gravity: 45, spin: 8),
          );
        }
        _rings.add(_Ring(e.x, e.y, _gold, 0.7, 4, 40));
        _pops.add(_Pop(e.x, e.y + 8, 'Carrier down +${InvadersSim.carrierPoints}', _gold));
        _shake = math.max(_shake, 0.8);
      case InvadersEventKind.smartBomb:
        // One soft ion ring and a brief low wash: a single flash, no strobing.
        _bomb = 1;
        _rings.add(_Ring(e.x, e.y, _ion, 0.75, 3, sim.height * 1.1, width: 2.6));
        _shake = math.max(_shake, 0.5);
      case InvadersEventKind.gameOver:
        _hurt = 1;
        _shake = math.max(_shake, 0.6);
    }
  }

  void onRestart() {
    _bursts.clear();
    _parts.clear();
    _rings.clear();
    _pops.clear();
    _shake = 0;
    _hurt = 0;
    _pulse = 0;
    _lastMarch = -1;
    _bomb = 0;
    _slowFade = 0;
    _maw = 0;
    _carrierIn = 9;
    _ward.clear();
    _flakes.clear();
  }

  static const _ion = Color(0xFF4DE8FF);
  static const _gold = Color(0xFFFFC23D);
  static const _plasma = Color(0xFFA07CFF);
  static const _flare = Color(0xFFFF4766);
  static const _ember = Color(0xFFFF7A45);
  static const _ice = Color(0xFF7FE4FF);
  static const _chitin = Color(0xFF1C2A36);
  static const _chitinLit = Color(0xFF2E4656);
  static const _steel = Color(0xFFB9CBDD);
  static const _plate = Color(0xFF4E6A82);
  static const _frost = Color(0xFFBFEFFF);

  /// The player-facing name of a power-up (pop-ups, HUD).
  static String powerName(PowerupKind k) => switch (k) {
    PowerupKind.twin => 'Twin shot',
    PowerupKind.shield => 'Shield',
    PowerupKind.spread => 'Spread shot',
    PowerupKind.laser => 'Piercing laser',
    PowerupKind.rapid => 'Rapid fire',
    PowerupKind.homing => 'Homing missiles',
    PowerupKind.slow => 'Slow field',
    PowerupKind.bomb => 'Smart bomb',
  };

  /// Guns are upgrades (plasma); utilities are your energy (ion / frost).
  static Color _powerColor(PowerupKind k) => k.isGun ? _plasma : (k == PowerupKind.slow ? _frost : _ion);

  ExplosionStyle _style() => explosionStyleFor(CoinManager.instance.selectedExplosion);
  ShipPalette get _palette => shipPaletteFor(CoinManager.instance.selectedSkin);
  ThrusterSpec get _thruster => thrusterSpecFor(CoinManager.instance.selectedThruster);

  // ── Update ──────────────────────────────────────────────────────────────
  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (sim.marchCount != _lastMarch) {
      if (_lastMarch >= 0) _pulse = 1;
      _lastMarch = sim.marchCount;
    }
    _pulse = math.max(0, _pulse - dt * 6);
    _shake = math.max(0, _shake - dt * 2.6);
    _hurt = math.max(0, _hurt - dt * 1.8);
    _shieldHit = math.max(0, _shieldHit - dt * 3);
    _bomb = math.max(0, _bomb - dt / 0.6);
    _maw = math.max(0, _maw - dt / 0.5);
    _carrierIn += dt;
    _slowFade = sim.slowed ? math.min(1, _slowFade + dt / 0.3) : math.max(0, _slowFade - dt / 0.5);
    if (_ward.isNotEmpty) {
      _ward.updateAll((_, v) => v - dt * 4);
      _ward.removeWhere((_, v) => v <= 0);
    }
    // Frost flakes drifting down while the slow field holds.
    if (_slowFade > 0 && _flakes.length < 28 && _rng.nextDouble() < dt * 30) {
      _flakes.add(_Flake(_rng.nextDouble() * sim.width, -2, (_rng.nextDouble() - 0.5) * 3, 5 + _rng.nextDouble() * 6, 0.3 + _rng.nextDouble() * 0.4));
    }
    for (final f in _flakes) {
      f.x += f.vx * dt + math.sin(_t * 1.3 + f.y * 0.2) * dt * 1.5;
      f.y += f.vy * dt;
    }
    _flakes.removeWhere((f) => f.y > sim.height + 2 || _slowFade == 0);
    // Headings of divers and drones, from how they moved since last frame.
    for (final a in sim.aliens) {
      if (a.kind == AlienKind.diver) _track(a, a.x, a.y);
    }
    for (final d in sim.drones) {
      _track(d, d.x, d.y);
    }
    // A badly hurt carrier smokes.
    final c = sim.carrier;
    if (c != null && c.hpFraction < 0.34 && _rng.nextDouble() < dt * 8) {
      _parts.add(_Part(c.x + (_rng.nextDouble() - 0.5) * 18, c.y - 1, (_rng.nextDouble() - 0.5) * 4, -6, 0.6, 0.9, _ember, hot: true, drag: 1));
    }
    if (_muzzle > 0) _muzzle -= dt;
    _tilt += ((sim.shipVx / 160).clamp(-1.0, 1.0) * 0.18 - _tilt) * math.min(1.0, dt * 10);
    for (final b in _bursts) {
      b.age += dt;
    }
    _bursts.removeWhere((b) => b.age > b.burst.life);
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age >= r.life);
    for (final p in _pops) {
      p.age += dt;
    }
    _pops.removeWhere((p) => p.age >= 1.0);
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
  }

  void _track(Object o, double x, double y) {
    final p = _prev[o];
    if (p != null) {
      final dx = x - p.dx, dy = y - p.dy;
      if (dx * dx + dy * dy > 0.0004) {
        // The art points "down" (+y); heading is the turn from straight down.
        final target = math.atan2(-dx, dy);
        final h = _heading[o] ?? target;
        var d = target - h;
        while (d > math.pi) {
          d -= math.pi * 2;
        }
        while (d < -math.pi) {
          d += math.pi * 2;
        }
        _heading[o] = h + d * 0.25;
      }
    }
    _prev[o] = Offset(x, y);
  }

  // ── Background (baked per size) ─────────────────────────────────────────
  Image? _bg;
  Size _bgSize = Size.zero;
  late Float32List _stars;

  void _bake(Size s) {
    _bg?.dispose();
    final rec = PictureRecorder();
    paintSky(Canvas(rec), s, horizonY: s.height * 0.955);
    _bg = rec.endRecording().toImageSync(s.width.ceil(), s.height.ceil());
    _bgSize = s;
    final r = math.Random(9);
    _stars = Float32List.fromList([
      for (var i = 0; i < 24; i++) ...[r.nextDouble() * s.width, r.nextDouble() * s.height * 0.6],
    ]);
  }

  /// The sky: teal-black gradient, two aurora bands (blurred once, at bake
  /// time), stars, and the frozen moon's horizon with ice spires.
  static void paintSky(Canvas c, Size s, {required double horizonY}) {
    final r = Offset.zero & s;
    c.drawRect(
      r,
      Paint()
        ..shader = Gradient.linear(
          Offset.zero,
          Offset(0, s.height),
          const [Color(0xFF030E16), Color(0xFF06212A), Color(0xFF0A2633), Color(0xFF04101A)],
          const [0, 0.35, 0.75, 1],
        ),
    );
    // Aurora (blur is fine here: drawn once into the baked image).
    final aur = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * 0.04);
    for (final (band, col, a, yb) in [(0, const Color(0xFF2FE0B8), 0.28, 0.17), (1, const Color(0xFF7A6CFF), 0.22, 0.24)]) {
      final path = Path();
      for (var i = 0; i <= 40; i++) {
        final x = s.width * i / 40;
        final y = s.height * yb + math.sin(x / s.width * 7 + band * 2) * s.height * 0.028 + math.sin(x / s.width * 16 + band) * s.height * 0.01;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      c.drawPath(
        path,
        aur
          ..strokeWidth = s.height * 0.05
          ..color = col.withValues(alpha: a),
      );
    }
    final rnd = math.Random(7);
    final star = Paint();
    for (var i = 0; i < 110; i++) {
      star.color = Color.fromRGBO(233, 237, 255, 0.2 + rnd.nextDouble() * 0.6);
      c.drawCircle(Offset(rnd.nextDouble() * s.width, rnd.nextDouble() * s.height * 0.8), 0.4 + rnd.nextDouble() * 0.8, star);
    }
    // Frozen moon horizon.
    final mr = s.width * 1.6;
    final mc = Offset(s.width / 2, horizonY + mr);
    c.drawCircle(mc, mr, Paint()..shader = Gradient.linear(Offset(0, horizonY), Offset(0, s.height), const [Color(0xFF0E3442), Color(0xFF08202B)]));
    c.drawCircle(
      mc,
      mr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x7F7FE4FF),
    );
    c.drawCircle(
      Offset(s.width / 2, horizonY),
      s.width * 0.7,
      Paint()..shader = Gradient.radial(Offset(s.width / 2, horizonY), s.width * 0.7, const [Color(0x264DE8FF), Color(0x00264DE8)], const [0, 1]),
    );
    final spire = Paint()..color = const Color(0xFF123844);
    for (var k = 0; k < 7; k++) {
      final x = s.width * (0.06 + k * 0.15);
      final h = s.height * (0.012 + (k % 3) * 0.006);
      c.drawPath(
        Path()
          ..moveTo(x - s.width * 0.025, horizonY + s.height * 0.02)
          ..lineTo(x, horizonY - h)
          ..lineTo(x + s.width * 0.025, horizonY + s.height * 0.02)
          ..close(),
        spire,
      );
    }
  }

  // ── Render ──────────────────────────────────────────────────────────────
  static final _imgPaint = Paint()..filterQuality = FilterQuality.low;
  static final _fill = Paint();
  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final _line = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  static final _wash = Paint()..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    if (size.x == 0) return;
    final s = Size(size.x, size.y);
    if (_bg == null || _bgSize != s) _bake(s);
    canvas.drawImage(_bg!, Offset.zero, _imgPaint);
    // A few stars twinkle.
    final tw = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _stars.length; i += 2) {
      final a = 0.3 + 0.5 * (0.5 + 0.5 * math.sin(_t * (1.2 + i % 5 * 0.3) + i));
      tw
        ..strokeWidth = 1.6
        ..color = Color.fromRGBO(233, 237, 255, a);
      canvas.drawPoints(PointMode.points, [Offset(_stars[i], _stars[i + 1])], tw);
    }

    final k = size.x / sim.width;
    canvas.save();
    if (_shake > 0) {
      final m = _shake * _shake * 6;
      canvas.translate((_rng.nextDouble() * 2 - 1) * m, (_rng.nextDouble() * 2 - 1) * m);
    }
    canvas.scale(k);

    if (_slowFade > 0) _paintFrost(canvas);
    _paintRail(canvas);
    _paintBunkers(canvas);
    _paintMothership(canvas);
    _paintAliens(canvas);
    _paintCarrier(canvas);
    _paintDrones(canvas);
    _paintPowerups(canvas);
    _paintShots(canvas);
    _paintShip(canvas);
    _paintEffects(canvas, k);
    canvas.restore();

    // Smart bomb: one brief, low wash (never above 0.3 alpha).
    if (_bomb > 0.01) {
      _wash.shader = null;
      _wash.color = const Color(0xFF9FEFFF).withValues(alpha: 0.3 * _bomb * _bomb);
      canvas.drawRect(Offset.zero & Size(size.x, size.y), _wash);
    }
    // Red glow in from the edges when hit / overrun.
    if (_hurt > 0.01) {
      final e = size.x * 0.18;
      final on = _flare.withValues(alpha: 0.4 * _hurt);
      final off = _flare.withValues(alpha: 0);
      _wash.shader = Gradient.linear(Offset.zero, Offset(0, e), [on, off]);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.x, e), _wash);
      _wash.shader = Gradient.linear(Offset(0, size.y), Offset(0, size.y - e), [on, off]);
      canvas.drawRect(Rect.fromLTWH(0, size.y - e, size.x, e), _wash);
      _wash.shader = Gradient.linear(Offset.zero, Offset(e, 0), [on, off]);
      canvas.drawRect(Rect.fromLTWH(0, 0, e, size.y), _wash);
      _wash.shader = Gradient.linear(Offset(size.x, 0), Offset(size.x - e, 0), [on, off]);
      canvas.drawRect(Rect.fromLTWH(size.x - e, 0, e, size.y), _wash);
      _wash.shader = null;
    }
  }

  // The ion rail the ship rides, and a faint touch band under it.
  void _paintRail(Canvas canvas) {
    final y = sim.shipY + InvadersSim.shipHh + 2.2;
    _line
      ..strokeWidth = 0.25
      ..color = _ion.withValues(alpha: 0.35);
    canvas.drawLine(Offset(4, y), Offset(sim.width - 4, y), _line);
    Glow.drawOval(canvas, Rect.fromCenter(center: Offset(sim.shipX, y), width: 30, height: 3), _ion.withValues(alpha: 0.3));
  }

  void _paintBunkers(Canvas canvas) {
    final diamond = Path()
      ..moveTo(0, -0.62)
      ..lineTo(0.62, 0)
      ..lineTo(0, 0.62)
      ..lineTo(-0.62, 0)
      ..close();
    for (final b in sim.bunkers) {
      if (b.aliveCount == 0) continue;
      Glow.drawOval(
        canvas,
        Rect.fromCenter(center: Offset(b.centerX, b.top + b.height / 2), width: b.width * 1.6, height: b.height * 1.8),
        _ion.withValues(alpha: 0.10),
      );
      for (var r = 0; r < Bunker.rows; r++) {
        for (var c = 0; c < Bunker.cols; c++) {
          if (!b.alive(c, r)) continue;
          final cx = b.left + (c + 0.5) * Bunker.cell;
          final cy = b.top + (r + 0.5) * Bunker.cell;
          // Lighter at the top, with a little per-cell sparkle.
          final h = ((c * 7 + r * 13) % 5) / 5;
          _fill.color = Color.lerp(const Color(0xFFB8F2FF), const Color(0xFF3FA9C9), r / (Bunker.rows - 1) * 0.8 + h * 0.15)!;
          canvas.save();
          canvas.translate(cx, cy);
          canvas.drawPath(diamond, _fill);
          canvas.restore();
        }
      }
    }
  }

  void _paintMothership(Canvas canvas) {
    final m = sim.mothership;
    if (m == null) return;
    final x = m.x, y = m.y;
    Glow.draw(canvas, Offset(x, y + 2), 14, _gold.withValues(alpha: 0.35));
    final hull = Path()
      ..moveTo(x - 5.2, y + 0.6)
      ..lineTo(x - 3.4, y - 1.6)
      ..lineTo(x + 3.4, y - 1.6)
      ..lineTo(x + 5.2, y + 0.6)
      ..lineTo(x + 2.8, y + 2)
      ..lineTo(x - 2.8, y + 2)
      ..close();
    _fill.color = const Color(0xFF2B1E3A);
    canvas.drawPath(hull, _fill);
    _stroke
      ..strokeWidth = 0.32
      ..color = _gold;
    canvas.drawPath(hull, _stroke);
    // Port lights chasing in the direction of travel.
    for (var i = 0; i < 4; i++) {
      final lx = x - 2.4 + i * 1.6;
      final on = ((_t * 8).floor() + (m.dir > 0 ? -i : i)) % 4 == 0;
      _fill.color = on ? const Color(0xFFFFF1C2) : _gold;
      canvas.drawCircle(Offset(lx, y + 0.4), 0.42, _fill);
    }
    // The shard it carries, hanging under the hull.
    canvas.save();
    canvas.translate(x, y + 4.4);
    canvas.scale(0.16);
    ThreadArt.paintShard(canvas, Offset.zero, _t);
    canvas.restore();
  }

  // ── The swarm ───────────────────────────────────────────────────────────
  static final _ghost = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.22;

  void _paintAliens(Canvas canvas) {
    final pulse = _pulse;
    // Shield-bearers' frost tethers to the neighbors they cover.
    for (final w in sim.aliens) {
      if (!w.alive || w.kind != AlienKind.shielder) continue;
      for (final a in sim.aliens) {
        if (!a.alive || !a.covered || a.row != w.row || (a.col - w.col).abs() != 1 || a.diving) continue;
        _line
          ..strokeWidth = 0.35
          ..color = _frost.withValues(alpha: 0.28 + 0.12 * math.sin(_t * 5 + a.col));
        canvas.drawLine(Offset(w.x, w.y - 0.5), Offset(a.x, a.y - 0.5), _line);
        // a bright mote running along the tether
        final f = (_t * 1.4 + a.col * 0.37) % 1;
        Glow.draw(canvas, Offset.lerp(Offset(w.x, w.y - 0.5), Offset(a.x, a.y - 0.5), f)!, 1.4, _frost.withValues(alpha: 0.8));
      }
    }
    for (final a in sim.aliens) {
      if (!a.alive) {
        if (a.flash > 0) {
          final f = a.flash / Alien.flashSeconds;
          Glow.draw(canvas, Offset(a.x, a.y), 3.5 * f + 2, const Color(0xFFFFFFFF).withValues(alpha: 0.8 * f), hot: true);
        }
        continue;
      }
      if (a.diving) {
        // Its empty slot in the formation: a dashed flare ghost.
        _ghost.color = _flare.withValues(alpha: 0.35);
        final r = Rect.fromCenter(center: Offset(a.homeX, a.homeY), width: a.hw * 1.8, height: a.hh * 1.8);
        for (var i = 0; i < 4; i++) {
          final c0 = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft][i];
          final c1 = [r.topRight, r.bottomRight, r.bottomLeft, r.topLeft][i];
          canvas.drawLine(c0, Offset.lerp(c0, c1, 0.3)!, _ghost);
          canvas.drawLine(Offset.lerp(c0, c1, 0.7)!, c1, _ghost);
        }
      }
      canvas.save();
      final shake = a.dive == DiveState.windup ? math.sin(_t * 70) * 0.35 * (a.diveT / InvadersSim.diveWindup).clamp(0.3, 1.0) : 0.0;
      canvas.translate(a.x + shake, a.y);
      if (a.dive == DiveState.diving || a.dive == DiveState.returning) {
        final h = _heading[a] ?? 0;
        if (a.dive == DiveState.diving) {
          // Ember trail behind the dive.
          Glow.draw(canvas, Offset(math.sin(h) * 3.5, -math.cos(h) * 3.5), 4.5, _ember.withValues(alpha: 0.5));
          Glow.draw(canvas, Offset(math.sin(h) * 6.5, -math.cos(h) * 6.5), 3.2, _ember.withValues(alpha: 0.25));
        }
        canvas.rotate(a.dive == DiveState.diving ? h : h * 0.5);
      }
      // Mockup space is ~4 pt per unit; aliens are 7 units wide (minis 4).
      canvas.scale(a.hw / 14);
      if (_slowFade > 0) Glow.draw(canvas, Offset.zero, 17, _frost.withValues(alpha: 0.22 * _slowFade));
      final hurt = a.hurt > 0 ? a.hurt / Alien.hurtSeconds : 0.0;
      switch (a.kind) {
        case AlienKind.elite:
          paintCrab(canvas, a.frame, pulse);
        case AlienKind.guard:
          paintMantis(canvas, a.frame, pulse);
        case AlienKind.grunt:
          paintBeetle(canvas, a.frame, pulse);
        case AlienKind.armored:
          paintIsopod(canvas, a.frame, pulse, cracked: a.cracked, hurt: hurt);
        case AlienKind.diver:
          final pose = switch (a.dive) {
            DiveState.none => 0,
            DiveState.windup => 1,
            DiveState.diving => 2,
            DiveState.returning => 3,
          };
          final charge = a.dive == DiveState.windup ? (a.diveT / InvadersSim.diveWindup).clamp(0.0, 1.0) : 0.0;
          paintWasp(canvas, a.frame, pulse, pose: pose, charge: charge, time: _t);
        case AlienKind.splitter:
          paintPod(canvas, a.frame, pulse, time: _t);
        case AlienKind.shielder:
          paintWarden(canvas, a.frame, pulse, time: _t);
        case AlienKind.mini:
          paintMiniPod(canvas, a.frame, pulse);
      }
      if (a.covered) _paintWard(canvas, _ward[a] ?? 0);
      if (hurt > 0 && a.kind != AlienKind.armored) Glow.draw(canvas, Offset.zero, 18, const Color(0xFFFFFFFF).withValues(alpha: hurt * 0.8), hot: true);
      canvas.restore();
    }
  }

  static final _hex = () {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      final o = Offset(math.cos(a) * 19, math.sin(a) * 16);
      if (i == 0) {
        p.moveTo(o.dx, o.dy);
      } else {
        p.lineTo(o.dx, o.dy);
      }
    }
    return p..close();
  }();

  /// The hex ward a shield-bearer throws round its neighbor; [flash] 1 → 0
  /// when it has just absorbed a shot.
  void _paintWard(Canvas canvas, double flash) {
    _fill.color = _frost.withValues(alpha: 0.07 + 0.18 * flash);
    canvas.drawPath(_hex, _fill);
    _stroke
      ..strokeWidth = 1.3 + 1.2 * flash
      ..color = _frost.withValues(alpha: 0.55 + 0.4 * flash + 0.08 * math.sin(_t * 4));
    canvas.drawPath(_hex, _stroke);
    if (flash > 0) Glow.draw(canvas, Offset.zero, 24 + 8 * flash, _frost.withValues(alpha: 0.45 * flash));
  }

  void _paintCarrier(Canvas canvas) {
    final c = sim.carrier;
    if (c == null) return;
    // It settles in from above when it appears.
    final settle = math.min(1.0, _carrierIn / 0.9);
    final ease = 1 - (1 - settle) * (1 - settle) * (1 - settle);
    final x = c.x, y = c.y - (1 - ease) * 16;
    const hw = InvadersSim.carrierHw, hh = InvadersSim.carrierHh;
    final hp = c.hpFraction;
    Glow.drawOval(canvas, Rect.fromCenter(center: Offset(x, y + 3), width: hw * 2.8, height: hh * 3), _flare.withValues(alpha: 0.18));
    // Gun pods under the wings: they glow up before each shell.
    final charge = (1 - (c.fireClock / 0.7)).clamp(0.0, 1.0);
    for (final sx in [-1.0, 1.0]) {
      final pc = Offset(x + sx * hw * 0.72, y + hh * 0.75);
      _fill.color = _chitin;
      canvas.drawOval(Rect.fromCenter(center: pc, width: 4.4, height: 3.4), _fill);
      _stroke
        ..strokeWidth = 0.3
        ..color = _flare.withValues(alpha: 0.7);
      canvas.drawOval(Rect.fromCenter(center: pc, width: 4.4, height: 3.4), _stroke);
      Glow.draw(canvas, pc.translate(0, 1.2), 2.5 + 3.5 * charge, _ember.withValues(alpha: 0.35 + 0.6 * charge), hot: charge > 0.6);
    }
    final hull = Path()
      ..moveTo(x - hw, y + 1)
      ..lineTo(x - hw * 0.8, y - hh * 0.55)
      ..quadraticBezierTo(x, y - hh * 1.35, x + hw * 0.8, y - hh * 0.55)
      ..lineTo(x + hw, y + 1)
      ..lineTo(x + hw * 0.7, y + hh * 0.9)
      ..lineTo(x - hw * 0.7, y + hh * 0.9)
      ..close();
    _fill.color = _chitin;
    canvas.drawPath(hull, _fill);
    // Carapace segments and the dorsal ridge.
    _stroke
      ..strokeWidth = 0.35
      ..color = _chitinLit;
    for (var i = -3; i <= 3; i++) {
      final sx = x + i * hw * 0.24;
      canvas.drawLine(Offset(sx - 0.4, y - hh * (0.95 - i.abs() * 0.11)), Offset(sx + 0.4, y + hh * 0.85), _stroke);
    }
    _fill.color = _chitinLit;
    for (var i = -2; i <= 2; i++) {
      final sx = x + i * hw * 0.24;
      final top = y - hh * (1.12 - i.abs() * 0.12);
      canvas.drawPath(
        Path()
          ..moveTo(sx - 0.9, top + 0.9)
          ..lineTo(sx, top - 1.0)
          ..lineTo(sx + 0.9, top + 0.9)
          ..close(),
        _fill,
      );
    }
    // Damage: cracks spread as its hull drops, a glint of the furnace inside.
    if (hp < 0.67) {
      _stroke
        ..strokeWidth = 0.32
        ..color = _ember.withValues(alpha: 0.9);
      canvas.drawPath(
        Path()
          ..moveTo(x - hw * 0.55, y - hh * 0.5)
          ..lineTo(x - hw * 0.4, y)
          ..lineTo(x - hw * 0.5, y + hh * 0.4)
          ..moveTo(x - hw * 0.4, y)
          ..lineTo(x - hw * 0.25, y + hh * 0.2),
        _stroke,
      );
      Glow.draw(canvas, Offset(x - hw * 0.42, y), 2.2, _ember.withValues(alpha: 0.6));
    }
    if (hp < 0.34) {
      canvas.drawPath(
        Path()
          ..moveTo(x + hw * 0.35, y - hh * 0.7)
          ..lineTo(x + hw * 0.5, y - hh * 0.1)
          ..lineTo(x + hw * 0.38, y + hh * 0.5)
          ..moveTo(x + hw * 0.5, y - hh * 0.1)
          ..lineTo(x + hw * 0.66, y + hh * 0.1),
        _stroke,
      );
      Glow.draw(canvas, Offset(x + hw * 0.5, y - hh * 0.1), 2.6, _ember.withValues(alpha: 0.7 + 0.2 * math.sin(_t * 9)));
    }
    // Flare rim; a hit brightens the rim only (no full-body flash).
    final flash = (c.flash / 0.12).clamp(0.0, 1.0);
    _stroke
      ..strokeWidth = 0.45 + 0.25 * flash
      ..color = Color.lerp(_flare.withValues(alpha: 0.85), const Color(0xFFFFB3C2), flash * 0.7)!;
    canvas.drawPath(hull, _stroke);
    // Eyes along the brow, pulsing with the march.
    for (final ex in [-0.2, 0.0, 0.2]) {
      _eye(canvas, Offset(x + ex * hw, y - hh * 0.2), 0.7, const Color(0xFFFF5C8A), _pulse);
    }
    // The launch maw: opens for every drone.
    final open = _maw;
    final maw = Rect.fromCenter(center: Offset(x, y + hh * 0.72), width: 6, height: 1.0 + 1.8 * open);
    _fill.color = const Color(0xFF05060F);
    canvas.drawOval(maw, _fill);
    if (open > 0) Glow.drawOval(canvas, maw.inflate(1.5), _flare.withValues(alpha: 0.7 * open));
    _stroke
      ..strokeWidth = 0.3
      ..color = _flare.withValues(alpha: 0.6);
    canvas.drawOval(maw, _stroke);
    if (settle < 1) Glow.drawOval(canvas, Rect.fromCenter(center: Offset(x, y), width: hw * 3, height: hh * 3), _flare.withValues(alpha: 0.4 * (1 - settle)));
  }

  void _paintDrones(Canvas canvas) {
    for (final d in sim.drones) {
      canvas.save();
      canvas.translate(d.x, d.y);
      canvas.rotate(_heading[d] ?? 0);
      Glow.draw(canvas, const Offset(0, -2.2), 2.6, _ember.withValues(alpha: 0.45));
      // buzzing wings
      final flap = (math.sin(_t * 60 + d.phase * 7) * 0.5 + 0.5);
      _fill.color = _chitinLit.withValues(alpha: 0.55 + 0.3 * flap);
      for (final sx in [-1.0, 1.0]) {
        canvas.drawOval(Rect.fromCenter(center: Offset(sx * 1.7, -0.5), width: 2.4 + flap * 0.6, height: 1.2), _fill);
      }
      final body = Path()
        ..moveTo(0, InvadersSim.droneHh + 0.4)
        ..lineTo(-1.2, -InvadersSim.droneHh * 0.6)
        ..lineTo(0, -InvadersSim.droneHh)
        ..lineTo(1.2, -InvadersSim.droneHh * 0.6)
        ..close();
      _fill.color = _chitin;
      canvas.drawPath(body, _fill);
      _stroke
        ..strokeWidth = 0.25
        ..color = _flare.withValues(alpha: 0.85);
      canvas.drawPath(body, _stroke);
      _eye(canvas, const Offset(0, 0.7), 0.45, _flare, _pulse);
      canvas.restore();
    }
  }

  static void _eye(Canvas canvas, Offset c, double r, Color col, double pulse) {
    Glow.draw(canvas, c, r * (3.2 + 2 * pulse), col.withValues(alpha: 0.5 + 0.4 * pulse));
    _fill.color = Color.lerp(col, const Color(0xFFFFFFFF), 0.4 * pulse)!;
    canvas.drawCircle(c, r, _fill);
  }

  static void _shell(Canvas canvas, Path p) {
    _fill.color = _chitin;
    canvas.drawPath(p, _fill);
    _stroke
      ..strokeWidth = 1.2
      ..color = _flare.withValues(alpha: 0.75);
    canvas.drawPath(p, _stroke);
  }

  /// Grunt (1 pt): a small round beetle, two ember eyes, legs that twitch.
  static void paintBeetle(Canvas canvas, int frame, double pulse) {
    _stroke
      ..strokeWidth = 1.6
      ..color = _chitinLit;
    for (final sx in [-1.0, 1.0]) {
      for (var k = 0; k < 2; k++) {
        final ly = k == 0 ? -2.0 : 4.0;
        final spread = (frame + k).isOdd ? 3.0 : 0.0;
        canvas.drawLine(Offset(sx * 7, ly), Offset(sx * (12 + spread), ly + 5), _stroke);
      }
    }
    _shell(canvas, Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 8.5)));
    _fill.color = _chitinLit;
    canvas.drawPath(
      Path()
        ..moveTo(-8, -2)
        ..lineTo(0, -8.5)
        ..lineTo(8, -2)
        ..close(),
      _fill,
    );
    _eye(canvas, const Offset(-3, 1), 1.6, _ember, pulse);
    _eye(canvas, const Offset(3, 1), 1.6, _ember, pulse);
  }

  /// Guard (2 pts): a mantis with two raised blades that swing per step.
  static void paintMantis(Canvas canvas, int frame, double pulse) {
    final up = frame == 1 ? -4.0 : 0.0;
    _stroke
      ..strokeWidth = 2.2
      ..color = _chitinLit;
    for (final sx in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(sx * 5, -2)
          ..lineTo(sx * 12, -9 + up)
          ..lineTo(sx * 9, -14 + up),
        _stroke,
      );
    }
    _shell(
      canvas,
      Path()
        ..moveTo(-7, -4)
        ..lineTo(0, -10)
        ..lineTo(7, -4)
        ..lineTo(5, 8)
        ..lineTo(0, 11)
        ..lineTo(-5, 8)
        ..close(),
    );
    _eye(canvas, const Offset(0, -3), 2.3, _flare, pulse);
  }

  /// Elite (3 pts): an armored crab; pincers open per step; three eyes.
  static void paintCrab(Canvas canvas, int frame, double pulse) {
    final o = frame == 1 ? 2.0 : 0.0;
    _fill.color = _chitinLit;
    for (final sx in [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(sx * 12, -1)
          ..lineTo(sx * (16 + o), -7)
          ..lineTo(sx * (17.5 + o), 1)
          ..lineTo(sx * 15, 4)
          ..close(),
        _fill,
      );
    }
    _shell(
      canvas,
      Path()
        ..moveTo(-14, 6)
        ..lineTo(-11, -6)
        ..lineTo(0, -10)
        ..lineTo(11, -6)
        ..lineTo(14, 6)
        ..lineTo(0, 9)
        ..close(),
    );
    _stroke
      ..strokeWidth = 1.2
      ..color = _chitinLit;
    canvas.drawLine(const Offset(-8, -4), const Offset(8, -4), _stroke);
    for (final ex in [-5.0, 0.0, 5.0]) {
      _eye(canvas, Offset(ex, 1), 1.7, const Color(0xFFFF5C8A), pulse);
    }
  }

  /// Armored (4 pts, 2 hits): a plated isopod. Three steel plates over the
  /// chitin; [cracked] loses the middle plate (its flare core shows) and
  /// crazes the rest; [hurt] 1 → 0 flashes the plates.
  static void paintIsopod(Canvas canvas, int frame, double pulse, {bool cracked = false, double hurt = 0}) {
    _stroke
      ..strokeWidth = 1.5
      ..color = _chitinLit;
    for (final sx in [-1.0, 1.0]) {
      for (var k = 0; k < 3; k++) {
        final ly = -5.0 + k * 5;
        final tw = (frame + k).isOdd ? 1.5 : -0.5;
        canvas.drawLine(Offset(sx * 10, ly), Offset(sx * (14 + tw), ly + 3), _stroke);
      }
    }
    final body = RRect.fromRectAndRadius(const Rect.fromLTRB(-12, -10, 12, 9), const Radius.circular(7));
    _fill.color = _chitin;
    canvas.drawRRect(body, _fill);
    if (cracked) Glow.draw(canvas, const Offset(0, -1), 12, _flare.withValues(alpha: 0.5 + 0.3 * pulse));
    final plateCol = Color.lerp(_plate, const Color(0xFFFFFFFF), hurt * 0.75)!;
    for (var k = 0; k < 3; k++) {
      if (cracked && k == 1) continue;
      final top = -9.0 + k * 5.6;
      final plate = RRect.fromRectAndRadius(Rect.fromLTRB(-11.5 + (k == 0 ? 1.5 : 0), top, 11.5 - (k == 0 ? 1.5 : 0), top + 4.6), const Radius.circular(2.3));
      _fill.color = plateCol;
      canvas.drawRRect(plate, _fill);
      _fill.color = _steel.withValues(alpha: 0.85);
      canvas.drawRect(Rect.fromLTRB(plate.left + 2, top + 0.4, plate.right - 2, top + 1.2), _fill);
    }
    if (cracked) {
      // the exposed core and crazed plates
      _fill.color = const Color(0xFFFF8FA6);
      canvas.drawRect(const Rect.fromLTRB(-7, -2.8, 7, 1.6), _fill);
      _stroke
        ..strokeWidth = 0.9
        ..color = const Color(0xFFE9F6FF);
      canvas.drawPath(
        Path()
          ..moveTo(-6, -9)
          ..lineTo(-3, -6.5)
          ..lineTo(-5, -4.6)
          ..moveTo(5, 3)
          ..lineTo(2, 5.5)
          ..lineTo(4, 7.6),
        _stroke,
      );
    }
    _stroke
      ..strokeWidth = 1.2
      ..color = _flare.withValues(alpha: 0.75);
    canvas.drawRRect(body, _stroke);
    // eye slit under the front plate (aliens face down, toward you)
    Glow.draw(canvas, const Offset(0, 7.6), 5 + 3 * pulse, _flare.withValues(alpha: 0.55 + 0.35 * pulse));
    _fill.color = Color.lerp(_flare, const Color(0xFFFFFFFF), 0.4 * pulse)!;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-4.5, 6.8, 4.5, 8.6), const Radius.circular(0.9)), _fill);
  }

  /// Diver (4 pts): a wasp. [pose] 0 = folded (formation), 1 = wind-up
  /// (wings spread and buzzing, eye charging with [charge]), 2 = diving
  /// (wings swept back), 3 = returning (wings open, gliding).
  static void paintWasp(Canvas canvas, int frame, double pulse, {int pose = 0, double charge = 0, double time = 0}) {
    final buzz = pose == 1 ? math.sin(time * 90) * 0.25 : 0.0;
    final (spread, sweep) = switch (pose) {
      1 => (1.0 + buzz, 0.0),
      2 => (0.35, 1.0),
      3 => (0.9, 0.2),
      _ => (frame == 1 ? 0.5 : 0.4, 0.55),
    };
    for (final sx in [-1.0, 1.0]) {
      final root = Offset(sx * 2.5, -4);
      final tip = Offset(sx * (5 + 10 * spread), -9 - 6 * sweep + 4 * (1 - spread));
      final wing = Path()
        ..moveTo(root.dx, root.dy)
        ..quadraticBezierTo(sx * (6 + 6 * spread), -16 + 3 * sweep, tip.dx, tip.dy)
        ..quadraticBezierTo(sx * (4 + 6 * spread), -3 + 2 * sweep, root.dx, root.dy + 3)
        ..close();
      _fill.color = const Color(0xA02E4656);
      canvas.drawPath(wing, _fill);
      _stroke
        ..strokeWidth = 0.9
        ..color = _ember.withValues(alpha: pose == 1 ? 0.95 : 0.6);
      canvas.drawPath(wing, _stroke);
    }
    final body = Path()
      ..moveTo(0, -11)
      ..quadraticBezierTo(5, -6, 4, 3)
      ..quadraticBezierTo(2.5, 9, 0, 11)
      ..quadraticBezierTo(-2.5, 9, -4, 3)
      ..quadraticBezierTo(-5, -6, 0, -11)
      ..close();
    _shell(canvas, body);
    _stroke
      ..strokeWidth = 1.0
      ..color = _chitinLit;
    for (final by in [-4.0, -0.5, 3.0]) {
      canvas.drawLine(Offset(-3.6, by), Offset(3.6, by), _stroke);
    }
    // stinger
    _fill.color = _flare;
    canvas.drawPath(
      Path()
        ..moveTo(-1.2, 10)
        ..lineTo(0, 14)
        ..lineTo(1.2, 10)
        ..close(),
      _fill,
    );
    final eyeP = math.max(pulse, charge);
    if (charge > 0) Glow.draw(canvas, const Offset(0, 5), 8 + 8 * charge, _flare.withValues(alpha: 0.4 + 0.35 * charge));
    _eye(canvas, const Offset(0, 5), 2.0 + 0.6 * charge, _flare, eyeP);
  }

  /// Splitter (3 pts): a twin-lobed pod joined by a glowing seam, where it
  /// splits into two minis.
  static void paintPod(Canvas canvas, int frame, double pulse, {double time = 0}) {
    _stroke
      ..strokeWidth = 1.4
      ..color = _chitinLit;
    for (final sx in [-1.0, 1.0]) {
      final tw = frame == 1 ? 2.0 : 0.0;
      canvas.drawLine(Offset(sx * 10, 3), Offset(sx * (14 + tw), 8), _stroke);
      canvas.drawLine(Offset(sx * 9, -4), Offset(sx * (13 - tw * 0.5), -8), _stroke);
    }
    final seam = 0.55 + 0.45 * math.sin(time * 5);
    Glow.drawOval(canvas, const Rect.fromLTRB(-3, -10, 3, 10), _flare.withValues(alpha: 0.35 + 0.35 * seam));
    for (final sx in [-1.0, 1.0]) {
      _shell(canvas, Path()..addOval(Rect.fromCircle(center: Offset(sx * 5.6, 0), radius: 7.4)));
      _fill.color = _chitinLit;
      canvas.drawOval(Rect.fromCenter(center: Offset(sx * 6.4, -3.6), width: 6, height: 3), _fill);
      _eye(canvas, Offset(sx * 5.2, 2), 1.5, _ember, pulse);
    }
    _line
      ..strokeWidth = 1.2
      ..color = Color.lerp(_flare, const Color(0xFFFFFFFF), 0.3 * seam)!;
    canvas.drawLine(const Offset(0, -6.5), const Offset(0, 6.5), _line);
  }

  /// Mini (1 pt): one lobe of a split pod, one eye, scuttling legs.
  static void paintMiniPod(Canvas canvas, int frame, double pulse) {
    _stroke
      ..strokeWidth = 2.2
      ..color = _chitinLit;
    for (final sx in [-1.0, 1.0]) {
      final tw = frame == 1 ? 3.0 : -1.0;
      canvas.drawLine(Offset(sx * 9, 2), Offset(sx * (14 + tw), 8), _stroke);
    }
    _shell(canvas, Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: 10)));
    _line
      ..strokeWidth = 2
      ..color = _flare.withValues(alpha: 0.7);
    canvas.drawLine(const Offset(-6, -6), const Offset(-6, 6), _line);
    _eye(canvas, const Offset(1.5, 2), 2.6, _ember, pulse);
  }

  /// Shielder (3 pts): a warden with a frost crest and two emitter arms.
  static void paintWarden(Canvas canvas, int frame, double pulse, {double time = 0}) {
    final hum = 0.5 + 0.5 * math.sin(time * 4);
    _stroke
      ..strokeWidth = 2.0
      ..color = _chitinLit;
    for (final sx in [-1.0, 1.0]) {
      final lift = frame == 1 ? -1.5 : 0.0;
      canvas.drawPath(
        Path()
          ..moveTo(sx * 7, 0)
          ..lineTo(sx * 13, -2 + lift)
          ..lineTo(sx * 15, 3 + lift),
        _stroke,
      );
      Glow.draw(canvas, Offset(sx * 15, 3 + lift), 4 + 2 * hum, _frost.withValues(alpha: 0.6 + 0.3 * hum));
    }
    // frost crest on its back
    for (final (dx, h) in const [(-4.5, 6.0), (0.0, 9.0), (4.5, 6.0)]) {
      final crest = Path()
        ..moveTo(dx - 2, -6)
        ..lineTo(dx, -6 - h)
        ..lineTo(dx + 2, -6)
        ..close();
      _fill.color = const Color(0xFF8FD8F0);
      canvas.drawPath(crest, _fill);
      _fill.color = const Color(0xFFE9FBFF);
      canvas.drawPath(
        Path()
          ..moveTo(dx - 0.4, -6)
          ..lineTo(dx, -6 - h)
          ..lineTo(dx + 2, -6)
          ..close(),
        _fill,
      );
    }
    Glow.draw(canvas, const Offset(0, -10), 9, _frost.withValues(alpha: 0.25 + 0.15 * hum));
    _shell(
      canvas,
      Path()
        ..moveTo(-9, -6)
        ..lineTo(9, -6)
        ..lineTo(11, 2)
        ..lineTo(5, 9)
        ..lineTo(-5, 9)
        ..lineTo(-11, 2)
        ..close(),
    );
    _eye(canvas, const Offset(0, 2.5), 2.2, _flare, pulse);
  }

  // ── Power-ups, shots, ship ──────────────────────────────────────────────
  void _paintPowerups(Canvas canvas) {
    for (final p in sim.powerups) {
      paintCapsule(canvas, Offset(p.x, p.y), p.kind, _t);
    }
  }

  /// A falling capsule. GUNS: a tall plasma cartridge (cut corners, a light
  /// bar along the top). UTILITIES: a round ion / frost orb with four notches
  /// turning round it. Each has its own glyph. Sized in sim units (~5 tall).
  static void paintCapsule(Canvas canvas, Offset c, PowerupKind k, double t) {
    final col = _powerColor(k);
    final bob = math.sin(t * 4 + c.dx) * 0.25;
    c = c.translate(0, bob);
    Glow.draw(canvas, c, 6.5, col.withValues(alpha: 0.4 + 0.15 * math.sin(t * 6)));
    if (k.isGun) {
      const w = 2.1, h = 2.7, cutC = 0.9;
      final pod = Path()
        ..moveTo(c.dx - w + cutC, c.dy - h)
        ..lineTo(c.dx + w - cutC, c.dy - h)
        ..lineTo(c.dx + w, c.dy - h + cutC)
        ..lineTo(c.dx + w, c.dy + h - cutC)
        ..lineTo(c.dx + w - cutC, c.dy + h)
        ..lineTo(c.dx - w + cutC, c.dy + h)
        ..lineTo(c.dx - w, c.dy + h - cutC)
        ..lineTo(c.dx - w, c.dy - h + cutC)
        ..close();
      _fill.color = const Color(0xF0140C33);
      canvas.drawPath(pod, _fill);
      _stroke
        ..strokeWidth = 0.32
        ..color = col;
      canvas.drawPath(pod, _stroke);
      _fill.color = col;
      canvas.drawRect(Rect.fromLTRB(c.dx - w + cutC, c.dy - h + 0.35, c.dx + w - cutC, c.dy - h + 0.75), _fill);
    } else {
      const r = 2.5;
      _fill.color = const Color(0xF0061A26);
      canvas.drawCircle(c, r, _fill);
      _stroke
        ..strokeWidth = 0.32
        ..color = col;
      canvas.drawCircle(c, r, _stroke);
      _fill.color = col;
      for (var i = 0; i < 4; i++) {
        final a = t * 1.6 + i * math.pi / 2;
        canvas.drawCircle(c.translate(math.cos(a) * (r + 0.55), math.sin(a) * (r + 0.55)), 0.32, _fill);
      }
    }
    paintPowerGlyph(canvas, c.translate(0, k.isGun ? 0.35 : 0), k, Color.lerp(col, const Color(0xFFFFFFFF), 0.65)!, 1);
  }

  /// The glyph of a power-up, about 2.6 x [s] units across (also used by the
  /// HUD's timer chips).
  static void paintPowerGlyph(Canvas canvas, Offset c, PowerupKind k, Color col, double s) {
    _stroke
      ..strokeWidth = 0.4 * s
      ..color = col;
    Offset o(double x, double y) => c.translate(x * s, y * s);
    switch (k) {
      case PowerupKind.twin:
        canvas.drawLine(o(-0.7, 1.1), o(-0.7, -1.1), _stroke);
        canvas.drawLine(o(0.7, 1.1), o(0.7, -1.1), _stroke);
      case PowerupKind.spread:
        canvas.drawLine(o(0, 1.1), o(-1.1, -1.0), _stroke);
        canvas.drawLine(o(0, 1.1), o(0, -1.2), _stroke);
        canvas.drawLine(o(0, 1.1), o(1.1, -1.0), _stroke);
      case PowerupKind.laser:
        _stroke.strokeWidth = 0.7 * s;
        canvas.drawLine(o(0, 1.3), o(0, -1.3), _stroke);
        _stroke.strokeWidth = 0.3 * s;
        canvas.drawLine(o(-0.9, 1.3), o(0.9, 1.3), _stroke);
      case PowerupKind.rapid:
        for (final dy in [-0.9, 0.0, 0.9]) {
          canvas.drawPath(
            Path()
              ..moveTo(o(-0.9, dy + 0.45).dx, o(-0.9, dy + 0.45).dy)
              ..lineTo(o(0, dy - 0.3).dx, o(0, dy - 0.3).dy)
              ..lineTo(o(0.9, dy + 0.45).dx, o(0.9, dy + 0.45).dy),
            _stroke,
          );
        }
      case PowerupKind.homing:
        canvas.drawPath(
          Path()
            ..moveTo(o(-0.9, 1.1).dx, o(-0.9, 1.1).dy)
            ..quadraticBezierTo(o(-0.9, -0.9).dx, o(-0.9, -0.9).dy, o(0.9, -1.0).dx, o(0.9, -1.0).dy),
          _stroke,
        );
        canvas.drawLine(o(0.9, -1.0), o(0.2, -1.4), _stroke);
        canvas.drawLine(o(0.9, -1.0), o(0.5, -0.3), _stroke);
      case PowerupKind.shield:
        canvas.drawPath(
          Path()
            ..moveTo(o(0, -1.2).dx, o(0, -1.2).dy)
            ..lineTo(o(1.0, -0.7).dx, o(1.0, -0.7).dy)
            ..quadraticBezierTo(o(1.0, 0.8).dx, o(1.0, 0.8).dy, o(0, 1.3).dx, o(0, 1.3).dy)
            ..quadraticBezierTo(o(-1.0, 0.8).dx, o(-1.0, 0.8).dy, o(-1.0, -0.7).dx, o(-1.0, -0.7).dy)
            ..close(),
          _stroke,
        );
      case PowerupKind.slow:
        for (var i = 0; i < 3; i++) {
          final a = i * math.pi / 3;
          canvas.drawLine(o(math.cos(a) * 1.3, math.sin(a) * 1.3), o(-math.cos(a) * 1.3, -math.sin(a) * 1.3), _stroke);
        }
      case PowerupKind.bomb:
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          final r0 = i.isEven ? 0.5 : 0.7;
          final r1 = i.isEven ? 1.4 : 1.0;
          canvas.drawLine(o(math.cos(a) * r0, math.sin(a) * r0), o(math.cos(a) * r1, math.sin(a) * r1), _stroke);
        }
        _fill.color = col;
        canvas.drawCircle(c, 0.35 * s, _fill);
    }
  }

  void _paintShots(Canvas canvas) {
    final rapid = sim.gun == PowerupKind.rapid;
    for (final s in sim.shipShots) {
      final hh = s.hh;
      switch (s.kind) {
        case ShotKind.laser:
          // A tall piercing beam: ion bloom, white core.
          Glow.drawOval(canvas, Rect.fromCenter(center: Offset(s.x, s.y), width: 5, height: hh * 3), _ion.withValues(alpha: 0.45));
          _line
            ..strokeWidth = 2.0
            ..color = _ion.withValues(alpha: 0.55);
          canvas.drawLine(Offset(s.x, s.y + hh * 1.4), Offset(s.x, s.y - hh), _line);
          _line
            ..strokeWidth = 0.8
            ..color = const Color(0xFFFFFFFF);
          canvas.drawLine(Offset(s.x, s.y + hh), Offset(s.x, s.y - hh), _line);
          continue;
        case ShotKind.missile:
          // A little dart, exhaust curving behind it as it steers.
          final dir = Offset(s.vx, -s.speed);
          final len = dir.distance;
          final u = len == 0 ? const Offset(0, -1) : dir / len;
          final tail = Offset(s.x, s.y) - u * 3.2 - Offset(s.vx * 0.03, 0);
          Glow.draw(canvas, tail, 3.2, _ion.withValues(alpha: 0.5));
          _line
            ..strokeWidth = 0.9
            ..color = _ion.withValues(alpha: 0.45);
          canvas.drawLine(tail, Offset(s.x, s.y), _line);
          canvas.save();
          canvas.translate(s.x, s.y);
          canvas.rotate(math.atan2(u.dx, -u.dy));
          _fill.color = const Color(0xFFE9FCFF);
          canvas.drawPath(
            Path()
              ..moveTo(0, -hh * 0.8)
              ..lineTo(0.55, 0.6)
              ..lineTo(0, 0.2)
              ..lineTo(-0.55, 0.6)
              ..close(),
            _fill,
          );
          canvas.restore();
          continue;
        default:
          break;
      }
      final k = rapid ? 0.7 : 1.0;
      final head = Offset(s.x, s.y - hh * k);
      final tail = Offset(s.x - s.vx * 0.03, s.y + hh * 1.6 * k);
      _line
        ..strokeWidth = s.kind == ShotKind.spread ? 1.1 : 1.5
        ..color = _ion.withValues(alpha: 0.35);
      canvas.drawLine(tail, head, _line);
      _line
        ..strokeWidth = s.kind == ShotKind.spread ? 0.55 : 0.7
        ..color = _ion;
      canvas.drawLine(Offset.lerp(tail, head, 0.3)!, head, _line);
      _line
        ..strokeWidth = 0.32
        ..color = const Color(0xFFFFFFFF);
      canvas.drawLine(Offset.lerp(tail, head, 0.65)!, head, _line);
    }
    for (final s in sim.alienShots) {
      final c = Offset(s.x, s.y);
      if (s.kind == ShotKind.shell) {
        // The carrier's shell: bigger, a dark core and a spiked turning ring.
        Glow.draw(canvas, c, 7, _flare.withValues(alpha: 0.55));
        _fill.color = const Color(0xFF2A0C16);
        canvas.drawCircle(c, 1.5, _fill);
        _stroke
          ..strokeWidth = 0.45
          ..color = _flare;
        canvas.drawCircle(c, 1.7, _stroke);
        final rot = _t * 4;
        for (var i = 0; i < 6; i++) {
          final a = rot + i * math.pi / 3;
          canvas.drawLine(c.translate(math.cos(a) * 2.1, math.sin(a) * 2.1), c.translate(math.cos(a) * 2.9, math.sin(a) * 2.9), _stroke);
        }
        _fill.color = const Color(0xFFFFD9C2);
        canvas.drawCircle(c, 0.6, _fill);
        continue;
      }
      Glow.draw(canvas, c, 4.2, _ember.withValues(alpha: 0.7));
      _stroke
        ..strokeWidth = 0.4
        ..color = _ember;
      canvas.drawCircle(c, 1.1, _stroke);
      _fill.color = const Color(0xFFFFF1D6);
      canvas.drawCircle(c, 0.5, _fill);
    }
  }

  void _paintShip(Canvas canvas) {
    final over = sim.phase == InvadersPhase.over;
    if (over && sim.overFor > 0.1) return;
    final x = sim.shipX, y = sim.shipY;
    // Shot pips under the ship: lit = shots ready.
    final ready = math.max(0, sim.maxShots - sim.shipShots.length);
    final py = y + InvadersSim.shipHh + 2.2;
    for (var i = 0; i < sim.maxShots; i++) {
      final px = x + (i - (sim.maxShots - 1) / 2) * 2.6;
      final lit = i < ready;
      if (lit) Glow.draw(canvas, Offset(px, py), 2.2, _ion.withValues(alpha: 0.7));
      if (lit) {
        _fill.color = _ion;
        canvas.drawCircle(Offset(px, py), 0.55, _fill);
      } else {
        // Spent (shot still in the air): an empty ring.
        _stroke
          ..strokeWidth = 0.18
          ..color = _ion.withValues(alpha: 0.45);
        canvas.drawCircle(Offset(px, py), 0.5, _stroke);
      }
    }
    if (sim.invulnerable > 0 && (_t * 12).floor().isOdd) return;
    final engine = _thruster.color ?? _palette.engine;
    Glow.draw(canvas, Offset(x, y + InvadersSim.shipHh + 0.6), 5 + math.sin(_t * 30) * 0.5, engine.withValues(alpha: 0.7));
    if (_muzzle > 0) Glow.draw(canvas, Offset(x, y - InvadersSim.shipHh - 1), 4, _ion.withValues(alpha: 0.9), hot: true);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(_tilt);
    canvas.scale(InvadersSim.shipHw * 2.3 / 42);
    ShipArt.paint(canvas, _palette, time: _t, thrust: 0.55, engine: _thruster.color);
    final gun = sim.gunLeft > 0 ? sim.gun : null;
    if (gun != null) _paintGunMount(canvas, gun);
    if (sim.shielded) {
      ShieldArt.paint(canvas, 28, shieldSpecFor(CoinManager.instance.selectedShieldSkin), strength: 0.9, time: _t, flash: _shieldHit > 0.5);
    }
    canvas.restore();
  }

  /// The live gun's mount on the ship (ship space, 42 units across), plasma.
  void _paintGunMount(Canvas canvas, PowerupKind gun) {
    const body = Color(0xFFD9CCFF);
    final hum = 0.65 + 0.25 * math.sin(_t * 7);
    switch (gun) {
      case PowerupKind.twin:
        for (final sx in [-14.0, 14.0]) {
          Glow.draw(canvas, Offset(sx, -4), 7, _plasma.withValues(alpha: 0.8 * hum));
          _fill.color = body;
          canvas.drawRect(Rect.fromCenter(center: Offset(sx, -2), width: 3, height: 9), _fill);
        }
      case PowerupKind.spread:
        for (final a in [-0.45, 0.0, 0.45]) {
          canvas.save();
          canvas.translate(0, -12);
          canvas.rotate(a);
          Glow.draw(canvas, const Offset(0, -6), 4, _plasma.withValues(alpha: 0.7 * hum));
          _fill.color = body;
          canvas.drawRect(Rect.fromCenter(center: const Offset(0, -4), width: 2.2, height: 7), _fill);
          canvas.restore();
        }
      case PowerupKind.laser:
        Glow.drawOval(canvas, const Rect.fromLTRB(-5, -32, 5, -10), _ion.withValues(alpha: 0.5 * hum));
        _fill.color = body;
        canvas.drawRect(const Rect.fromLTRB(-1.8, -26, 1.8, -10), _fill);
        _fill.color = _ion;
        canvas.drawRect(const Rect.fromLTRB(-0.7, -27, 0.7, -12), _fill);
      case PowerupKind.rapid:
        // a triple barrel that spins (the lit barrel cycles)
        final lit = (_t * 18).floor() % 3;
        for (var i = 0; i < 3; i++) {
          final x = (i - 1) * 3.2;
          _fill.color = i == lit ? const Color(0xFFFFFFFF) : body;
          canvas.drawRect(Rect.fromLTRB(x - 1, -21, x + 1, -9), _fill);
        }
        Glow.draw(canvas, const Offset(0, -21), 6, _plasma.withValues(alpha: 0.8 * hum));
      case PowerupKind.homing:
        for (final sx in [-12.0, 12.0]) {
          Glow.draw(canvas, Offset(sx, -2), 6, _plasma.withValues(alpha: 0.7 * hum));
          _fill.color = body;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(sx, 0), width: 5, height: 8), const Radius.circular(2)), _fill);
          _fill.color = _plasma;
          for (final dx in [-1.2, 1.2]) {
            canvas.drawCircle(Offset(sx + dx, -3), 0.9, _fill);
          }
        }
      default:
        break;
    }
  }

  /// The slow field: a cold tint over the field and drifting frost flakes.
  Shader? _frostShader;
  double _frostH = 0;
  void _paintFrost(Canvas canvas) {
    final h = sim.height;
    if (_frostShader == null || _frostH != h) {
      _frostH = h;
      _frostShader = Gradient.linear(Offset.zero, Offset(0, h), const [Color(0x40BFEFFF), Color(0x147FE4FF), Color(0x307FE4FF)], const [0, 0.5, 1]);
    }
    _wash
      ..shader = _frostShader
      ..color = Color.fromRGBO(255, 255, 255, _slowFade);
    canvas.drawRect(Rect.fromLTWH(0, 0, sim.width, h), _wash);
    _wash.shader = null;
    for (final f in _flakes) {
      Glow.draw(canvas, Offset(f.x, f.y), f.size * 2.2, _frost.withValues(alpha: 0.55 * _slowFade));
    }
  }

  // ── Effects ─────────────────────────────────────────────────────────────
  void _paintEffects(Canvas canvas, double k) {
    for (final b in _bursts) {
      canvas.save();
      canvas.translate(b.x, b.y);
      canvas.scale(1 / k); // bursts are sized in px
      b.burst.paint(canvas, b.age, _ember);
      canvas.restore();
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus;
    for (final r in _rings) {
      final f = r.age / r.life;
      ring
        ..strokeWidth = ((1 - f) * 0.9 + 0.15) * r.width
        ..color = r.color.withValues(alpha: 0.85 * (1 - f));
      canvas.drawCircle(Offset(r.x, r.y), r.r0 + (r.r1 - r.r0) * (1 - (1 - f) * (1 - f)), ring);
    }
    for (final q in _parts) {
      final f = q.age / q.life;
      final c = Offset(q.x, q.y);
      if (q.chip) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(q.rot);
        final s = q.size;
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
        Glow.draw(canvas, c, q.size * 2.4 * (1 - f * 0.5), q.color.withValues(alpha: 1 - f), hot: q.hot);
      }
    }
    for (final p in _pops) {
      _paintPop(canvas, p, k);
    }
  }

  static final Map<String, Paragraph> _popText = {};
  static final _layer = Paint();

  void _paintPop(Canvas canvas, _Pop p, double k) {
    final key = '${p.text}|${p.color.toARGB32()}';
    final para = _popText.putIfAbsent(key, () {
      final b = ParagraphBuilder(ParagraphStyle(textAlign: TextAlign.center))
        ..pushStyle(
          TextStyle(
            color: p.color,
            fontSize: 15,
            fontFamily: 'ChakraPetch',
            fontWeight: FontWeight.w700,
            shadows: const [Shadow(color: Color(0xCC050817), blurRadius: 4)],
          ),
        )
        ..addText(p.text);
      return b.build()..layout(const ParagraphConstraints(width: 200));
    });
    final f = p.age;
    final y = p.y - 6 * (1 - (1 - f) * (1 - f));
    final a = f < 0.7 ? 1.0 : 1 - (f - 0.7) / 0.3;
    canvas.save();
    canvas.translate(p.x, y);
    canvas.scale(1 / k);
    _layer.color = Color.fromRGBO(0, 0, 0, a);
    canvas.saveLayer(const Rect.fromLTWH(-100, -14, 200, 28), _layer);
    canvas.drawParagraph(para, const Offset(-100, -11));
    canvas.restore();
    canvas.restore();
  }

  // ── Hub preview ─────────────────────────────────────────────────────────
  static final _previewSky = <Size, Image>{};

  /// A live window for the arcade hub's card: aurora sky, three rows of the
  /// swarm marching and stepping, a bunker, the barge crossing and your ship
  /// firing up from the rail.
  static void paintPreview(Canvas canvas, Size s, double t) {
    final sky = _previewSky.putIfAbsent(s, () {
      final rec = PictureRecorder();
      paintSky(Canvas(rec), Size(s.width, s.height * 1.8), horizonY: s.height * 1.75);
      return rec.endRecording().toImageSync(s.width.ceil(), (s.height * 1.8).ceil());
    });
    canvas.drawImageRect(sky, Rect.fromLTWH(0, s.height * 0.1, s.width, s.height), Offset.zero & s, _imgPaint);
    final u = s.width / 100; // px per unit, same field as the game
    canvas.save();
    canvas.scale(u);
    final h = s.height / u;
    // Formation: steps sideways once every 0.45 s.
    final step = (t / 0.45).floor();
    final frame = step % 2;
    final phase = step % 16;
    final dx = (phase < 8 ? phase : 16 - phase) * 2.0 - 8;
    final pulse = math.max(0.0, 1 - ((t / 0.45) % 1) * 5);
    final kinds = [paintCrab, paintMantis, paintBeetle];
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 6; c++) {
        if ((r == 1 && c == 4) || (r == 2 && c == 1)) continue;
        canvas.save();
        canvas.translate(25 + c * 10 + dx, h * 0.2 + r * 8.5);
        canvas.scale(InvadersSim.alienHw / 14);
        kinds[r](canvas, frame, pulse);
        canvas.restore();
      }
    }
    // Barge crossing.
    final bx = ((t * 14) % 140) - 20;
    Glow.draw(canvas, Offset(bx, h * 0.07 + 1), 10, _gold.withValues(alpha: 0.35));
    _fill.color = const Color(0xFF2B1E3A);
    final hull = Path()
      ..moveTo(bx - 5.2, h * 0.07 + 0.6)
      ..lineTo(bx - 3.4, h * 0.07 - 1.6)
      ..lineTo(bx + 3.4, h * 0.07 - 1.6)
      ..lineTo(bx + 5.2, h * 0.07 + 0.6)
      ..lineTo(bx + 2.8, h * 0.07 + 2)
      ..lineTo(bx - 2.8, h * 0.07 + 2)
      ..close();
    canvas.drawPath(hull, _fill);
    _stroke
      ..strokeWidth = 0.32
      ..color = _gold;
    canvas.drawPath(hull, _stroke);
    // Ship sliding on the rail, firing.
    final sx = 50 + math.sin(t * 0.9) * 22;
    final sy = h * 0.86;
    _line
      ..strokeWidth = 0.25
      ..color = _ion.withValues(alpha: 0.35);
    canvas.drawLine(Offset(4, sy + 5), Offset(96, sy + 5), _line);
    for (var i = 0; i < 2; i++) {
      final f = ((t * 1.6) + i / 2) % 1;
      final y = sy - 5 - f * (sy - h * 0.25);
      final ox = 50 + math.sin((t - f * 0.6) * 0.9) * 22;
      _line
        ..strokeWidth = 1.2
        ..color = _ion.withValues(alpha: 0.4);
      canvas.drawLine(Offset(ox, y + 4), Offset(ox, y), _line);
      _line
        ..strokeWidth = 0.55
        ..color = _ion;
      canvas.drawLine(Offset(ox, y + 2.5), Offset(ox, y), _line);
    }
    final pal = shipPaletteFor(CoinManager.instance.selectedSkin);
    final th = thrusterSpecFor(CoinManager.instance.selectedThruster);
    canvas.save();
    canvas.translate(sx, sy);
    canvas.scale(InvadersSim.shipHw * 2.3 / 42);
    ShipArt.paint(canvas, pal, time: t, thrust: 0.6, engine: th.color);
    canvas.restore();
    canvas.restore();
  }
}

class _Burst {
  final double x, y;
  final ExplosionBurst burst;
  double age = 0;
  _Burst(this.x, this.y, ExplosionStyle style, double radiusUnits, {bool big = false})
    : burst = ExplosionBurst(style: style, radius: radiusUnits * 4, big: big);
}

class _Part {
  double x, y, vx, vy;
  final double life, size, drag, gravity, spin;
  final Color color;
  final bool hot, chip;
  double age = 0, rot = 0;
  _Part(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.life,
    this.size,
    this.color, {
    this.hot = false,
    this.chip = false,
    this.drag = 0,
    this.gravity = 0,
    this.spin = 0,
  });
}

class _Ring {
  final double x, y, life, r0, r1, width;
  final Color color;
  double age = 0;
  _Ring(this.x, this.y, this.color, this.life, this.r0, this.r1, {this.width = 1});
}

class _Flake {
  double x, y;
  final double vx, vy, size;
  _Flake(this.x, this.y, this.vx, this.vy, this.size);
}

class _Pop {
  final double x, y;
  final String text;
  final Color color;
  double age = 0;
  _Pop(this.x, this.y, this.text, this.color);
}
