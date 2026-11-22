import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../data/balance.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import 'monster.dart';
import 'weapon_homing_bolt.dart';

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

  final _rng = math.Random();
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

    // Centre pip blinks faster as it locks.
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
  final _rng = math.Random();

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

// ── Singularity: Event Horizon (screen pulses) ──────────────────────────────
class EventHorizonNova extends NovaAttack {
  double _next = 0;
  double _flash = 0;

  @override
  void tick(double dt) {
    _flash = math.max(0, _flash - dt * 3);
    _next -= dt;
    if (_next <= 0) {
      _next = Balance.eventHorizonInterval;
      _flash = 1;
      for (final m in liveMonsters.where(onScreen).toList()) {
        m.takeDamage(Balance.eventHorizonDamage * novaMult);
        m.applySlow(0.5, 0.6);
      }
      game.shake(0.25);
      SfxManager.instance.play(Sfx.explode, volume: 0.6);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_flash <= 0) return;
    final s = game.size;
    final c = Offset(game.player.position.x, game.player.position.y);
    final r = s.length * (1.1 - _flash);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 * _flash + 2
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.7 * _flash),
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, s.x, s.y), Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.07 * _flash));
  }
}
