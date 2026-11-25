import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../data/balance.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import 'graze.dart';
import 'monster.dart';
import 'weapon_homing_bolt.dart';

/// Tests set this to make every Nova attack's randomness repeatable.
int? novaTestSeed;
math.Random newNovaRandom() => novaTestSeed == null ? math.Random() : math.Random(novaTestSeed);

/// Base for the Nova attacks inherited from bosses. Drains the Nova bar like
/// the laser does and removes itself when it's empty; subclasses implement
/// [tick] (logic) and optionally [render].
abstract class NovaAttack extends Component with HasGameReference<NovaboltGame> {
  NovaAttack() : super(priority: 4);

  double t = 0;

  /// Damage multiplier from Nova upgrades.
  double get novaMult => game.superchargeSystem.damageMultiplier;

  Iterable<Monster> get liveMonsters => game.world.children.whereType<Monster>().where((m) => !m.isDead);

  bool onScreen(Monster m) =>
      m.position.x > -20 && m.position.x < game.size.x + 20 && m.position.y > -20 && m.position.y < game.size.y + 20;

  /// Damage every monster within [r] of [c]; returns how many were hit.
  int damageInRadius(Vector2 c, double r, double damage) {
    var n = 0;
    for (final m in liveMonsters.toList()) {
      if (m.position.distanceTo(c) < r + m.size.x / 2) {
        m.takeDamage(damage);
        n++;
      }
    }
    return n;
  }

  @override
  void update(double dt) {
    if (game.superchargeSystem.deplete(dt)) {
      onEnd();
      removeFromParent();
      return;
    }
    t += dt;
    tick(dt);
  }

  void tick(double dt);
  void onEnd() {}

  Vector2 get aimPoint {
    final p = game.player;
    return p.position + p.aimDirection * 190;
  }
}

// ── Dreadnought: Orbital Strike ─────────────────────────────────────────────
/// Marks targets on screen and drops strikes on them in quick succession.
///
/// Each strike: a targeting reticle locks on (showing the blast radius), a
/// tracking laser drops from orbit, then a white-hot column slams down with a
/// flash, a double shockwave, sparks and a glowing crater. Opening the attack
/// sweeps a scan line down the screen. Timing and damage are unchanged:
/// the hit lands [_lock] seconds after the mark.
class OrbitalStrikeNova extends NovaAttack {
  static const _lock = 0.35;
  static const _radius = 70.0;
  static const _life = 1.25; // visuals only; damage is applied once at _lock
  static const _gold = Color(0xFFFFDD00);
  static const _amber = Color(0xFFFF9A1F);
  static const _hot = Color(0xFFFFF6C8);

  final _rng = newNovaRandom();
  double _next = 0;
  final _strikes = <_Strike>[];

  @override
  void tick(double dt) {
    _next -= dt;
    if (_next <= 0) {
      _next = Balance.orbitalStrikeInterval;
      final targets = liveMonsters.where(onScreen).toList();
      final at = targets.isEmpty
          ? game.player.position + Vector2((_rng.nextDouble() - 0.5) * 300, (_rng.nextDouble() - 0.5) * 300)
          : targets[_rng.nextInt(targets.length)].position.clone();
      _strikes.add(_Strike(at, _rng));
    }
    for (final s in _strikes) {
      s.t += dt;
      if (!s.hit && s.t >= _lock) {
        s.hit = true;
        damageInRadius(s.at, _radius, Balance.orbitalStrikeDamage * novaMult);
        game.shake(0.2);
        SfxManager.instance.play(Sfx.explode, volume: 0.45);
      }
    }
    _strikes.removeWhere((s) => s.t > _life);
  }

  static final _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus
    ..strokeCap = StrokeCap.round;
  static final _fill = Paint()..blendMode = BlendMode.plus;

  static double _easeOut(double x) => 1 - math.pow(1 - x.clamp(0.0, 1.0), 3).toDouble();

  @override
  void render(Canvas canvas) {
    final w = game.size.x;
    final h = game.size.y;
    final f = game.superchargeSystem.fraction;
    final presence = math.min(1.0, t / 0.3) * math.min(1.0, f / 0.08);

    // Light from orbit: a warm wash falling from the top edge while active.
    if (presence > 0) {
      _fill.shader = Gradient.linear(Offset.zero, Offset(0, h * 0.35), [
        _gold.withValues(alpha: 0.13 * presence * (0.85 + 0.15 * math.sin(t * 9))),
        _gold.withValues(alpha: 0),
      ]);
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.35), _fill);
      _fill.shader = null;
    }

    // Opening scan: a line sweeps down the screen as the satellite acquires.
    if (t < 0.6) {
      final p = t / 0.6;
      final y = h * _easeOut(p);
      final a = 1 - p * p;
      Glow.drawOval(canvas, Rect.fromCenter(center: Offset(w / 2, y), width: w * 1.4, height: 70), _gold.withValues(alpha: 0.35 * a));
      _stroke
        ..strokeWidth = 2
        ..color = _hot.withValues(alpha: 0.9 * a);
      canvas.drawLine(Offset(0, y), Offset(w, y), _stroke);
    }

    for (final s in _strikes) {
      final c = Offset(s.at.x, s.at.y);
      if (s.t < _lock) {
        _renderLock(canvas, c, s.t / _lock, s);
      } else {
        _renderImpact(canvas, c, s.t - _lock, s);
      }
    }
  }

  void _renderLock(Canvas canvas, Offset c, double p, _Strike s) {
    final a = math.min(1.0, p * 3);
    // Ground glow builds under the target.
    Glow.draw(canvas, c, _radius * (0.4 + 0.6 * p), _gold.withValues(alpha: 0.28 * p));

    // Blast-radius ring: dashed, spinning, settling onto the real radius.
    final r = _radius * (1.5 - 0.5 * _easeOut(p));
    _stroke
      ..strokeWidth = 1.6
      ..color = _gold.withValues(alpha: 0.85 * a);
    const dashes = 18;
    final spin = s.spin + p * 2.4;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, spin + i * math.pi * 2 / dashes, math.pi / dashes, false, _stroke);
    }

    // Corner brackets close in and rotate to square as the lock completes.
    final b = 26 + 30 * (1 - _easeOut(p));
    final rot = (1 - _easeOut(p)) * math.pi / 2;
    _stroke
      ..strokeWidth = 2.4
      ..color = (p > 0.8 ? _hot : _gold).withValues(alpha: a);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    for (var k = 0; k < 4; k++) {
      canvas.rotate(math.pi / 2);
      canvas.drawLine(Offset(b, b), Offset(b - 11, b), _stroke);
      canvas.drawLine(Offset(b, b), Offset(b, b - 11), _stroke);
    }
    canvas.restore();

    // Center pip blinks faster as it locks.
    if (math.sin(p * p * 60) > -0.3) {
      Glow.draw(canvas, c, 10, _hot.withValues(alpha: 0.9 * a), hot: true);
    }

    // Tracking laser from orbit: thin and flickering, then the column drops.
    final flick = 0.35 + 0.3 * math.sin(s.t * 70);
    _stroke
      ..strokeWidth = 1
      ..color = _gold.withValues(alpha: flick * a);
    canvas.drawLine(Offset(c.dx, 0), c, _stroke);
    const drop = 0.22; // last 22% of the lock
    if (p > 1 - drop) {
      final q = (p - (1 - drop)) / drop;
      final tip = c.dy * q * q;
      _column(canvas, c.dx, tip, 9, 0.9);
      Glow.draw(canvas, Offset(c.dx, tip), 26, _hot.withValues(alpha: 0.9), hot: true);
    }
  }

  void _renderImpact(Canvas canvas, Offset c, double q, _Strike s) {
    // Column from orbit, slamming wide then pinching out.
    if (q < 0.34) {
      final k = q / 0.34;
      final cw = 40 * math.pow(1 - k, 0.7).toDouble() + 2;
      _column(canvas, c.dx, c.dy, cw, 1 - k * 0.6);
    }

    // Impact flash: white-hot core, gold bloom.
    if (q < 0.2) {
      final k = q / 0.2;
      Glow.draw(canvas, c, 150 * (0.7 + 0.3 * k), _hot.withValues(alpha: 1 - k), hot: true);
    }
    if (q < 0.6) {
      final k = q / 0.6;
      Glow.draw(canvas, c, 120 * (0.8 + 0.5 * k), _gold.withValues(alpha: 0.75 * (1 - k)));
    }

    // Double shockwave.
    for (final (delay, width, reach) in const [(0.0, 9.0, 1.75), (0.07, 4.0, 1.35)]) {
      final k = (q - delay) / 0.5;
      if (k <= 0 || k >= 1) continue;
      final r = _radius * reach * _easeOut(k);
      _stroke
        ..strokeWidth = width * (1 - k) + 1
        ..color = Color.lerp(_hot, _amber, k)!.withValues(alpha: 1 - k);
      canvas.drawCircle(c, r, _stroke);
    }

    // Sparks thrown out of the blast.
    if (q < 0.55) {
      final k = q / 0.55;
      final travel = _easeOut(k);
      _stroke.strokeWidth = 2.2 * (1 - k) + 0.6;
      for (final sp in s.sparks) {
        final d = Offset(math.cos(sp.angle), math.sin(sp.angle));
        final far = sp.reach * travel;
        _stroke.color = Color.lerp(_hot, _amber, k)!.withValues(alpha: 1 - k);
        canvas.drawLine(c + d * (far * 0.62 + 8), c + d * (far + 8), _stroke);
      }
    }

    // Crater: a molten ring and embers cooling after the hit.
    final cool = (q / (_life - _lock)).clamp(0.0, 1.0);
    final heat = 1 - cool;
    if (heat > 0) {
      Glow.draw(canvas, c, 44, _amber.withValues(alpha: 0.45 * heat * heat));
      _stroke
        ..strokeWidth = 2.5 * heat
        ..color = _amber.withValues(alpha: 0.7 * heat);
      canvas.drawCircle(c, _radius * 0.42, _stroke);
      for (final e in s.embers) {
        final p = c + Offset(math.cos(e.angle), math.sin(e.angle)) * e.dist;
        Glow.draw(canvas, p, 6 + 4 * heat, _amber.withValues(alpha: 0.9 * heat), hot: true);
      }
    }
  }

  /// Vertical energy column from the top of the screen down to [bottom].
  void _column(Canvas canvas, double x, double bottom, double halfW, double alpha) {
    if (bottom <= 0) return;
    _fill.shader = Gradient.linear(Offset(x - halfW * 2.2, 0), Offset(x + halfW * 2.2, 0), [
      _gold.withValues(alpha: 0),
      _gold.withValues(alpha: 0.45 * alpha),
      _hot.withValues(alpha: alpha),
      _gold.withValues(alpha: 0.45 * alpha),
      _gold.withValues(alpha: 0),
    ], const [0, 0.3, 0.5, 0.7, 1]);
    canvas.drawRect(Rect.fromLTRB(x - halfW * 2.2, 0, x + halfW * 2.2, bottom), _fill);
    _fill.shader = null;
    _fill.color = const Color(0xFFFFFFFF).withValues(alpha: alpha);
    canvas.drawRect(Rect.fromLTRB(x - halfW * 0.28, 0, x + halfW * 0.28, bottom), _fill);
    _fill.color = const Color(0xFFFFFFFF);
  }
}

class _Strike {
  final Vector2 at;
  final double spin;
  final List<({double angle, double reach})> sparks;
  final List<({double angle, double dist})> embers;
  double t = 0;
  bool hit = false;

  _Strike(this.at, math.Random rng)
      : spin = rng.nextDouble() * math.pi * 2,
        sparks = List.generate(16, (_) => (angle: rng.nextDouble() * math.pi * 2, reach: 70 + rng.nextDouble() * 110)),
        embers = List.generate(7, (_) => (angle: rng.nextDouble() * math.pi * 2, dist: 10 + rng.nextDouble() * 34));
}

// ── Void Tyrant: Void Pulse (gravity well) ──────────────────────────────────
/// A well ahead of the ship drags enemies in and grinds them down.
class GravityWellNova extends NovaAttack {
  /// Cosmic Behemoth's variant grows into a black hole over its lifetime.
  final bool growing;
  final Color color;
  GravityWellNova({this.growing = false, this.color = const Color(0xFFFF00CC)});

  Vector2? _at;
  double get _radius => growing ? math.min(150, 45 + t * 22) : 70;

  @override
  void tick(double dt) {
    // The well drifts toward where you're aiming.
    final target = aimPoint;
    _at ??= target.clone();
    _at!.add((target - _at!) * math.min(1.0, dt * 2.0));
    final r = _radius;
    for (final m in liveMonsters.toList()) {
      final to = _at! - m.position;
      final d = to.length;
      if (d < r * 3.2 && d > 2) {
        final pull = m.minion || m.stats.size > 70 ? 40.0 : 160.0;
        m.position += to / d * pull * dt;
      }
      if (d < r + m.size.x / 2) m.takeDamage((growing ? Balance.blackHoleDps : Balance.voidWellDps) * novaMult * dt);
    }
    game.rumble(0.12);
  }

  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final at = _at;
    if (at == null) return;
    final c = Offset(at.x, at.y);
    final r = _radius;
    Glow.draw(canvas, c, r * 2.2, color.withValues(alpha: 0.35));
    canvas.drawCircle(c, r * 0.55, Paint()..color = const Color(0xFF050817));
    for (var k = 0; k < 4; k++) {
      final p = (t * 0.9 + k / 4) % 1.0;
      _ring
        ..strokeWidth = 2.5 * p + 0.5
        ..color = color.withValues(alpha: 0.8 * p);
      canvas.drawCircle(c, r * (2.6 - 2.0 * p), _ring);
    }
    _ring
      ..strokeWidth = 2
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.8);
    canvas.drawCircle(c, r * 0.55, _ring);
  }
}

// ── Void Tyrant: Void Mines (area denial) ───────────────────────────────────
/// Scatters [count] void mines in a ring around the ship. Each one pops out,
/// arms after a short moment, drifts slightly, and blasts (area damage) the
/// moment an enemy comes close. Whatever is left when the Nova runs out pops
/// by itself. No pulling: it is about where the enemies are NOT allowed to be.
class VoidMinesNova extends NovaAttack {
  static const count = 8;
  static const ringRadius = 120.0;
  static const scatterTime = 0.35; // seconds to fly out to the ring
  static const armTime = 0.45; // after landing
  static const triggerRadius = 52.0; // an enemy this close (edge to mine) sets it off
  static const blastRadius = 88.0;
  static const blastDamage = 70.0;
  static const driftSpeed = 8.0;
  static const color = Color(0xFFFF00CC);

  final _rng = newNovaRandom();
  final _mines = <_Mine>[];
  Vector2? _origin;

  void _spawn() {
    final o = _origin = game.player.position.clone();
    final base = _rng.nextDouble() * math.pi * 2;
    for (var i = 0; i < count; i++) {
      final a = base + i * math.pi * 2 / count + (_rng.nextDouble() - 0.5) * 0.35;
      final r = ringRadius * (0.85 + _rng.nextDouble() * 0.3);
      final target = o + Vector2(math.cos(a), math.sin(a)) * r;
      target.x = target.x.clamp(24.0, math.max(24.0, game.size.x - 24));
      target.y = target.y.clamp(24.0, math.max(24.0, game.size.y - 24));
      final da = _rng.nextDouble() * math.pi * 2;
      _mines.add(_Mine(target, Vector2(math.cos(da), math.sin(da)) * driftSpeed, _rng.nextDouble() * 6.28));
    }
    SfxManager.instance.play(Sfx.zap, volume: 0.5);
  }

  void _detonate(_Mine m) {
    if (m.done) return;
    m.done = true;
    damageInRadius(m.pos, blastRadius, blastDamage * novaMult);
    game.world.add(_MineBlastFx(m.pos.clone()));
    game.shake(0.1);
    SfxManager.instance.play(Sfx.explode, volume: 0.45);
  }

  @override
  void tick(double dt) {
    if (_origin == null) _spawn();
    final live = liveMonsters.toList();
    for (final m in _mines) {
      m.age += dt;
      if (m.age < scatterTime) {
        m.pos = _origin! + (m.landing - _origin!) * _easeOut(m.age / scatterTime);
      } else {
        m.landing += m.vel * dt;
        m.landing.x = m.landing.x.clamp(24.0, math.max(24.0, game.size.x - 24));
        m.landing.y = m.landing.y.clamp(24.0, math.max(24.0, game.size.y - 24));
        m.pos = m.landing;
      }
      if (!m.armed) continue;
      for (final e in live) {
        if (e.isDead) continue;
        if (e.position.distanceTo(m.pos) < triggerRadius + e.size.x / 2) {
          _detonate(m);
          break;
        }
      }
    }
    _mines.removeWhere((m) => m.done);
  }

  @override
  void onEnd() {
    for (final m in _mines.toList()) {
      _detonate(m);
    }
    _mines.clear();
  }

  @override
  void render(Canvas canvas) {
    for (final m in _mines) {
      final c = Offset(m.pos.x, m.pos.y);
      final grow = _easeOut(m.age / scatterTime);
      final armed = m.armed;
      final pulse = armed ? 0.5 + 0.5 * math.sin(t * 9 + m.phase) : 0.25;
      Glow.draw(canvas, c, 26 * grow, color.withValues(alpha: 0.25 + 0.3 * pulse));
      canvas.drawCircle(c, 9 * grow, Paint()..color = const Color(0xFF14041F));
      canvas.drawCircle(
        c,
        9 * grow,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: armed ? 0.95 : 0.5),
      );
      canvas.drawCircle(c, 3 * grow, Paint()..color = Color.lerp(const Color(0xFF5A1070), const Color(0xFFFFFFFF), pulse)!);
      if (armed) {
        canvas.drawCircle(
          c,
          triggerRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = color.withValues(alpha: 0.10 + 0.08 * pulse),
        );
      }
    }
  }
}

class _Mine {
  Vector2 pos;
  Vector2 landing; // where it settles (and then drifts from)
  final Vector2 vel;
  final double phase;
  double age = 0;
  bool done = false;
  _Mine(Vector2 target, this.vel, this.phase)
      : landing = target,
        pos = target.clone();
  bool get armed => age >= VoidMinesNova.scatterTime + VoidMinesNova.armTime;
}

/// The blast flash of one mine: a hot core and an expanding ring, 0.4 s.
class _MineBlastFx extends Component {
  final Vector2 at;
  double t = 0;
  _MineBlastFx(this.at) : super(priority: 4);

  @override
  void update(double dt) {
    t += dt;
    if (t > 0.4) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final p = (t / 0.4).clamp(0.0, 1.0);
    final c = Offset(at.x, at.y);
    final r = VoidMinesNova.blastRadius * _easeOut(p);
    Glow.draw(canvas, c, r * 1.2, VoidMinesNova.color.withValues(alpha: 0.5 * (1 - p)), hot: true);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 * (1 - p) + 1.5
        ..blendMode = BlendMode.plus
        ..color = VoidMinesNova.color.withValues(alpha: 0.8 * (1 - p)),
    );
  }
}

// ── Leviathan: Leviathan Wave (shockwaves) ──────────────────────────────────
/// Rings of force roll out from the ship, hitting and shoving everything.
class ShockwaveNova extends NovaAttack {
  final _waves = <_Wave>[];
  double _next = 0;

  @override
  void tick(double dt) {
    _next -= dt;
    if (_next <= 0) {
      _next = Balance.shockwaveInterval;
      _waves.add(_Wave(game.player.position.clone()));
      SfxManager.instance.play(Sfx.zap, volume: 0.6);
    }
    for (final w in _waves) {
      w.t += dt;
      final r = w.radius;
      for (final m in liveMonsters.toList()) {
        if (w.hit.contains(m)) continue;
        final d = m.position.distanceTo(w.c);
        if (d < r + m.size.x / 2 && d > r - 30) {
          w.hit.add(m);
          m.takeDamage(Balance.shockwaveDamage * novaMult);
          if (m.stats.size < 70 && d > 1) m.position += (m.position - w.c) / d * 45;
        }
      }
    }
    _waves.removeWhere((w) => w.t > 0.8);
  }

  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    for (final w in _waves) {
      final p = w.t / 0.8;
      final c = Offset(w.c.x, w.c.y);
      _ring
        ..strokeWidth = 14 * (1 - p) + 2
        ..color = const Color(0xFF00CCFF).withValues(alpha: 0.6 * (1 - p));
      canvas.drawCircle(c, w.radius, _ring);
      _ring
        ..strokeWidth = 2
        ..color = const Color(0xFFE0FBFF).withValues(alpha: 0.9 * (1 - p));
      canvas.drawCircle(c, w.radius, _ring);
    }
  }
}

class _Wave {
  final Vector2 c;
  double t = 0;
  final hit = <Monster>{};
  _Wave(this.c);
  double get radius => 20 + 360 * _easeOut(t / 0.8);
}

double _easeOut(double x) => 1 - math.pow(1 - x.clamp(0.0, 1.0), 3).toDouble();

// ── Storm Phantom: Chain Lightning ──────────────────────────────────────────
class ChainLightningNova extends NovaAttack {
  double _next = 0;
  final _arcs = <_Arc>[];
  final _rng = newNovaRandom();

  @override
  void tick(double dt) {
    _next -= dt;
    if (_next <= 0) {
      _next = Balance.chainInterval;
      var from = game.player.position.clone();
      final hit = <Monster>{};
      for (var hop = 0; hop < Balance.chainHops; hop++) {
        Monster? best;
        var bestD = hop == 0 ? 320.0 : 180.0;
        for (final m in liveMonsters) {
          if (hit.contains(m)) continue;
          final d = m.position.distanceTo(from);
          if (d < bestD) {
            bestD = d;
            best = m;
          }
        }
        if (best == null) break;
        hit.add(best);
        _arcs.add(_Arc(_jag(from, best.position)));
        best.takeDamage(Balance.chainDamage * (hop == 0 ? Balance.chainFirstHopBonus : 1) * novaMult);
        from = best.position.clone();
      }
      if (hit.isNotEmpty) SfxManager.instance.play(Sfx.zap);
    }
    for (final a in _arcs) {
      a.t += dt;
    }
    _arcs.removeWhere((a) => a.t > 0.16);
  }

  List<Offset> _jag(Vector2 a, Vector2 b) {
    final pts = <Offset>[Offset(a.x, a.y)];
    final d = b - a;
    final n = Vector2(-d.y, d.x)..normalize();
    for (var i = 1; i < 6; i++) {
      final p = a + d * (i / 6) + n * ((_rng.nextDouble() - 0.5) * 26);
      pts.add(Offset(p.x, p.y));
    }
    pts.add(Offset(b.x, b.y));
    return pts;
  }

  static final _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    for (final a in _arcs) {
      final f = 1 - a.t / 0.16;
      final path = Path()..addPolygon(a.pts, false);
      _line
        ..strokeWidth = 7
        ..color = const Color(0xFF00FFFF).withValues(alpha: 0.35 * f);
      canvas.drawPath(path, _line);
      _line
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF).withValues(alpha: f);
      canvas.drawPath(path, _line);
    }
  }
}

class _Arc {
  final List<Offset> pts;
  double t = 0;
  _Arc(this.pts);
}

// ── Shadow Reaper: Shadow Veil (time slow) ──────────────────────────────────
/// Everything but you crawls; your weapons hit harder while it lasts.
class TimeSlowNova extends NovaAttack {
  @override
  void tick(double dt) {
    game.timeSlowActive = true;
    for (final m in liveMonsters) {
      m.applySlow(Balance.shadowVeilSlow, 0.25);
    }
  }

  @override
  void onRemove() {
    game.timeSlowActive = false;
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    final s = game.size;
    final pulse = 0.5 + 0.5 * math.sin(t * 3);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.x, s.y),
      Paint()..color = const Color(0xFF2A0050).withValues(alpha: 0.18 + 0.06 * pulse),
    );
    final c = Offset(game.player.position.x, game.player.position.y);
    Glow.draw(canvas, c, 90, const Color(0xFF9B4DFF).withValues(alpha: 0.35));
  }
}

// ── Solar Titan: Solar Rings (rotating beams) ───────────────────────────────
class SunBeamsNova extends NovaAttack {
  static const _len = 270.0;

  @override
  void tick(double dt) {
    final o = game.player.position;
    for (final m in liveMonsters.toList()) {
      for (var i = 0; i < 4; i++) {
        final a = t * 1.7 + i * math.pi / 2;
        final dir = Vector2(math.cos(a), math.sin(a));
        final rel = m.position - o;
        final along = rel.dot(dir);
        if (along < 0 || along > _len) continue;
        if ((rel - dir * along).length < 12 + m.size.x / 2) {
          m.takeDamage(Balance.sunBeamDps * novaMult * dt);
          break;
        }
      }
    }
  }

  static final _beam = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final o = Offset(game.player.position.x, game.player.position.y);
    for (var i = 0; i < 4; i++) {
      final a = t * 1.7 + i * math.pi / 2;
      final end = o + Offset(math.cos(a), math.sin(a)) * _len;
      _beam
        ..strokeWidth = 22
        ..color = const Color(0xFFFFAA00).withValues(alpha: 0.3);
      canvas.drawLine(o, end, _beam);
      _beam
        ..strokeWidth = 8
        ..color = const Color(0xFFFFD27A).withValues(alpha: 0.9);
      canvas.drawLine(o, end, _beam);
    }
    Glow.draw(canvas, o, 50, const Color(0xFFFFAA00).withValues(alpha: 0.6), hot: true);
  }
}

// ── Void Emperor: Void Surge (missile swarm) ────────────────────────────────
class MissileSwarmNova extends NovaAttack {
  double _next = 0;
  int _side = 1;

  @override
  void tick(double dt) {
    _next -= dt;
    if (_next <= 0) {
      _next = Balance.missileInterval;
      _side = -_side;
      final p = game.player;
      final aim = p.aimDirection;
      final dir = Vector2(aim.x * math.cos(0.9 * _side) - aim.y * math.sin(0.9 * _side),
          aim.x * math.sin(0.9 * _side) + aim.y * math.cos(0.9 * _side));
      game.world.add(HomingBolt(position: p.position.clone(), direction: dir, damage: Balance.missileDamage * novaMult));
    }
  }
}

// ── Singularity: Event Horizon (orbiting barrier) ───────────────────────────
/// A ring of collapsed space orbits the ship for the whole Nova. Enemy
/// projectiles that touch it are erased; enemies that touch it take heavy
/// damage and are thrown back (big ones and bosses take the damage but
/// can't be shoved, and a little less often).
class EventHorizonNova extends NovaAttack {
  static const ringRadius = 96.0;
  static const band = 12.0; // half the ring's thickness for touching
  static const hitDamage = 52.0, hitGap = 0.35, knockback = 70.0;
  static const bigDamage = 32.0, bigGap = 0.8; // size >= 70: bosses, same dps as the old pulses
  static const growTime = 0.25;

  final _next = <Monster, double>{}; // when each enemy may be hit again
  final _sparks = <_RingSpark>[];
  double _sfxGap = 0;

  double get _radius => ringRadius * _easeOut(t / growTime);

  @override
  void tick(double dt) {
    final p = game.player.position;
    final r = _radius;
    _sfxGap -= dt;
    _sparks.removeWhere((s) => (s.age += dt) > 0.25);

    // Erase enemy shots that touch (or sit inside) the ring.
    for (final shot in game.world.children.whereType<Grazeable>().toList()) {
      final d = shot.position.distanceTo(p);
      if (d < r + band + 6) {
        shot.removeFromParent();
        _sparks.add(_RingSpark(math.atan2(shot.position.y - p.y, shot.position.x - p.x)));
        _ping();
      }
    }

    // Shred and shove enemies that touch it.
    _next.removeWhere((m, _) => m.isDead || m.isRemoving);
    for (final m in liveMonsters.toList()) {
      final d = m.position.distanceTo(p);
      if ((d - r).abs() >= band + m.size.x * 0.4) continue;
      if (t < (_next[m] ?? 0)) continue;
      final big = m.stats.size >= 70;
      _next[m] = t + (big ? bigGap : hitGap);
      m.takeDamage((big ? bigDamage : hitDamage) * novaMult);
      _sparks.add(_RingSpark(math.atan2(m.position.y - p.y, m.position.x - p.x)));
      if (!big && d > 1) m.position += (m.position - p) / d * knockback;
      game.rumble(0.1);
      _ping();
    }
  }

  void _ping() {
    if (_sfxGap > 0) return;
    _sfxGap = 0.12;
    SfxManager.instance.play(Sfx.zap, volume: 0.35);
  }

  static final _stroke = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    final p = game.player.position;
    final c = Offset(p.x, p.y);
    final r = _radius;
    if (r < 2) return;
    Glow.draw(canvas, c, r * 1.5, const Color(0xFFB9A6FF).withValues(alpha: 0.18));
    // The collapsed-space band: dark, with a white edge on each side.
    _stroke
      ..blendMode = BlendMode.srcOver
      ..strokeWidth = band * 2
      ..color = const Color(0xFF06061A).withValues(alpha: 0.55);
    canvas.drawCircle(c, r, _stroke);
    _stroke
      ..blendMode = BlendMode.plus
      ..strokeWidth = 2
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85);
    canvas.drawCircle(c, r, _stroke);
    _stroke
      ..strokeWidth = 1
      ..color = const Color(0xFFB9A6FF).withValues(alpha: 0.45);
    canvas.drawCircle(c, r - band, _stroke);
    canvas.drawCircle(c, r + band, _stroke);
    // Three bright arcs orbit around the band.
    final spin = t * 1.8;
    _stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9);
    for (var k = 0; k < 3; k++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), spin + k * math.pi * 2 / 3, 0.7, false, _stroke);
    }
    _stroke.strokeCap = StrokeCap.butt;
    // Where something just hit.
    for (final s in _sparks) {
      final f = 1 - s.age / 0.25;
      final d = Offset(math.cos(s.angle), math.sin(s.angle));
      _stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFFFFFFF).withValues(alpha: f);
      canvas.drawLine(c + d * (r - band), c + d * (r + band + 10 * (1 - f)), _stroke);
      Glow.draw(canvas, c + d * r, 18, const Color(0xFFB9A6FF).withValues(alpha: 0.6 * f));
    }
    _stroke.blendMode = BlendMode.srcOver;
  }
}

class _RingSpark {
  final double angle;
  double age = 0;
  _RingSpark(this.angle);
}
