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
class OrbitalStrikeNova extends NovaAttack {
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
      _strikes.add(_Strike(at));
    }
    for (final s in _strikes) {
      s.t += dt;
      if (!s.hit && s.t >= 0.35) {
        s.hit = true;
        damageInRadius(s.at, 70, Balance.orbitalStrikeDamage * novaMult);
        game.shake(0.12);
        SfxManager.instance.play(Sfx.explode, volume: 0.45);
      }
    }
    _strikes.removeWhere((s) => s.t > 0.7);
  }

  static final _ring = Paint()..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas) {
    for (final s in _strikes) {
      final c = Offset(s.at.x, s.at.y);
      if (s.t < 0.35) {
        final p = s.t / 0.35;
        _ring
          ..strokeWidth = 1.5
          ..color = const Color(0xFFFFDD00).withValues(alpha: 0.9);
        canvas.drawCircle(c, 70 * (1 - p) + 8, _ring);
        canvas.drawLine(c - const Offset(10, 0), c + const Offset(10, 0), _ring);
        canvas.drawLine(c - const Offset(0, 10), c + const Offset(0, 10), _ring);
      } else {
        final p = (s.t - 0.35) / 0.35;
        Glow.draw(canvas, c, 80 * (0.6 + 0.6 * p), const Color(0xFFFFDD00).withValues(alpha: 0.9 * (1 - p)), hot: true);
        // The beam from orbit.
        Glow.drawOval(canvas, Rect.fromCenter(center: c - Offset(0, 300 * (1 - p)), width: 14, height: 600), const Color(0xFFFFF3A0).withValues(alpha: 0.7 * (1 - p)));
      }
    }
  }
}

class _Strike {
  final Vector2 at;
  double t = 0;
  bool hit = false;
  _Strike(this.at);
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
