import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../../coins/coin_manager.dart';
import '../../stats/mission_manager.dart';
import '../data/balance.dart';
import '../fx/glow.dart';
import '../novabolt_game.dart';
import '../render/ship_art.dart';
import 'boss_parts.dart';
import 'death_particles.dart';
import 'monster.dart';
import 'monster_boss.dart';
import 'player.dart';
import 'shield_pickup.dart';
import 'weapon_magic_bolt.dart';

/// Wingman color: plasma, the "upgrade" color, lifted a little so its
/// shots read apart from the ship's own.
const wingmanColor = Color(0xFFA07CFF);
const _wingmanShot = Color(0xFFC9B5FF);

/// Dropped by enemies (same chance as a shield). Touch it and a [Wingman]
/// joins you for [Balance.wingmanDuration] seconds.
class WingmanPickup extends PositionComponent
    with HasGameReference<NovaboltGame>, CollisionCallbacks {
  static const double _lifetime = 8.0;
  double _timer = 0;

  WingmanPickup({required Vector2 position})
      : super(position: position, size: Vector2.all(28), anchor: Anchor.center, priority: 2);

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= _lifetime) removeFromParent();
    final r = game.magnetRadius;
    if (r > 0) {
      final d = game.player.position - position;
      final dist = d.length;
      if (dist < r && dist > 1) position += d / dist * (160 + 260 * (1 - dist / r)) * dt;
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player && !isRemoving) {
      game.callWingman(position);
      SfxManager.instance.play(Sfx.pickup);
      MissionManager.instance.onPickup();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final r = size.x / 2;
    ShieldPickup.paintPickup(canvas, Offset(r, r), r, wingmanColor, _timer, _lifetime, (canvas, ink) {
      // Two arrowheads in formation: a lead and a smaller wingman.
      final p = Paint()..color = ink;
      Path arrow(double x, double y, double s) => Path()
        ..moveTo(x, y - 5 * s)
        ..lineTo(x + 4 * s, y + 4 * s)
        ..lineTo(x, y + 2 * s)
        ..lineTo(x - 4 * s, y + 4 * s)
        ..close();
      canvas.drawPath(arrow(-1.6, -0.6, 1.0), p);
      canvas.drawPath(arrow(4.2, 2.6, 0.62), p);
    });
  }
}

/// A small helper ship that circles you, shoots the nearest enemy and draws
/// enemies to itself (see `Monster.target`). Enemies that reach it are
/// rammed apart at the cost of its hull. Leaves when its time runs out or
/// its hull is gone. Not saved with a run.
class Wingman extends PositionComponent
    with HasGameReference<NovaboltGame>, CollisionCallbacks {
  static const _warpIn = 0.4;
  static const _warpOut = 0.45;

  Wingman({required Vector2 position, double startAngle = 0})
      : _orbit = startAngle,
        super(position: position, size: Vector2.all(30), anchor: Anchor.center, priority: 3);

  double _age = 0;
  double _orbit;
  late double maxHull;
  late double hull;
  double _fireT = 0.25;
  double _seekT = 0;
  Monster? _target;
  double _facing = 0;
  double _hitFlash = 0;
  double _leaveT = -1;
  bool _destroyed = false;
  final _vel = Vector2.zero();

  /// Seconds the wingman stays, counted from arrival (refreshed by another pickup).
  double _until = Balance.wingmanDuration;

  bool get leaving => _leaveT >= 0;
  /// Drawing enemies' attention (not while warping in or out).
  bool get taunting => !leaving && _age > _warpIn * 0.5;
  double get remaining => math.max(0, _until - _age);
  double get fraction => (remaining / Balance.wingmanDuration).clamp(0.0, 1.0);
  double get hullFraction => (hull / maxHull).clamp(0.0, 1.0);

  /// Another pickup while it's here: back to full time and hull.
  void refresh() {
    _until = _age + Balance.wingmanDuration;
    hull = maxHull;
  }

  @override
  Future<void> onLoad() async {
    maxHull = game.player.maxHp * Balance.wingmanHull;
    hull = maxHull;
    add(CircleHitbox(radius: 12, position: Vector2.all(3))..collisionType = CollisionType.active);
  }

  @override
  void onRemove() {
    if (identical(game.wingman, this)) {
      game.wingman = null;
      game.wingmanCooldown = Balance.wingmanCooldown;
    }
    super.onRemove();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _age += dt;
    if (_hitFlash > 0) _hitFlash -= dt;
    if (leaving) {
      _leaveT += dt;
      if (_leaveT >= _warpOut) removeFromParent();
      return;
    }
    if (remaining <= 0) {
      _startLeaving();
      return;
    }
    _fly(dt);
    _shoot(dt);
  }

  // Circles the ship with a slow wobble in radius, so enemies chasing it
  // get led around you rather than into you.
  void _fly(double dt) {
    _orbit += dt * 0.95;
    final r = Balance.wingmanOrbit * (1 + 0.18 * math.sin(_age * 1.7));
    final p = game.player.position;
    final goal = Vector2(p.x + math.cos(_orbit) * r, p.y + math.sin(_orbit) * r);
    final gs = game.size;
    goal.x = goal.x.clamp(16, gs.x - 16);
    goal.y = goal.y.clamp(16, gs.y - 16);
    final before = position.clone();
    final k = math.min(1.0, dt * 6);
    position += (goal - position) * k;
    _vel.setFrom((position - before) / math.max(dt, 1e-4));
  }

  void _shoot(double dt) {
    _seekT -= dt;
    final t = _target;
    if (_seekT <= 0 || t == null || t.isDead || t.isRemoving || !t.isMounted) {
      _seekT = 0.12;
      _target = _nearest();
    }
    final target = _target;
    final Vector2 dir;
    if (target != null) {
      dir = (target.position - position)..normalize();
    } else if (_vel.length2 > 400) {
      dir = _vel.normalized();
    } else {
      dir = Vector2(math.sin(_facing), -math.cos(_facing));
    }
    // Turn toward the aim rather than snapping.
    final want = math.atan2(dir.y, dir.x) + math.pi / 2;
    var diff = (want - _facing) % (math.pi * 2);
    if (diff > math.pi) diff -= math.pi * 2;
    _facing += diff * math.min(1.0, dt * 12);

    _fireT -= dt;
    if (target == null || _fireT > 0 || _age < _warpIn) return;
    _fireT = Balance.wingmanFireInterval;
    final nose = position + Vector2(math.sin(_facing), -math.cos(_facing)) * 12;
    game.world.add(MagicBolt(
      position: nose,
      direction: dir.clone(),
      damage: _shotDamage(),
      color: _wingmanShot,
      speed: 460,
      boltSize: 8,
    ));
    SfxManager.instance.play(Sfx.shoot, volume: 0.45);
  }

  double _shotDamage() {
    var best = 0.0;
    for (final w in game.player.activeWeapons) {
      best = math.max(best, w.shotDamage);
    }
    if (best <= 0) best = 15;
    return best * Balance.wingmanShotShare;
  }

  Monster? _nearest() {
    Monster? best;
    var bestD = Balance.wingmanRange * Balance.wingmanRange;
    final gs = game.size;
    for (final m in game.world.children.whereType<Monster>()) {
      if (m.isDead || m.isRemoving) continue;
      final mp = m.position;
      if (mp.x < 0 || mp.y < 0 || mp.x > gs.x || mp.y > gs.y) continue;
      final d = mp.distanceToSquared(position);
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    return best;
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (leaving || _destroyed) return;
    if (other is Monster && !other.isDead && !other.isRemoving) {
      takeHit(other.stats.contactDamagePerSecond * Balance.wingmanRamCost);
      // Like a dash: ordinary enemies are rammed apart; bosses and their
      // armor just hurt it.
      if (other is! BossMonster && other is! BossPart) {
        other.takeDamage(other.currentHp, silent: true);
      }
    }
  }

  /// Contact or a caster shot.
  void takeHit(double damage) {
    if (leaving || _destroyed) return;
    hull -= damage;
    _hitFlash = 0.14;
    if (hull <= 0) _destroy();
  }

  void _destroy() {
    _destroyed = true;
    game.world.add(DeathParticles(position: position.clone(), color: wingmanColor, radius: 16));
    SfxManager.instance.play(Sfx.explode, volume: 0.6);
    game.shake(0.2);
    game.announce('Wingman down', color: wingmanColor);
    removeFromParent();
  }

  void _startLeaving() {
    _leaveT = 0;
    SfxManager.instance.play(Sfx.dash, volume: 0.6);
  }

  // ── Render ────────────────────────────────────────────────────────────────
  static final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final palette = shipPaletteFor(CoinManager.instance.selectedSkin);

    // Warp-in: a ring collapsing onto it, the ship scaling up from a point.
    // Warp-out: the ship stretches and fades into a flash, a ring opening.
    var shipScale = 0.58;
    var alpha = 1.0;
    if (_age < _warpIn) {
      final p = _age / _warpIn;
      _ring
        ..strokeWidth = 2.5 * (1 - p) + 0.6
        ..color = wingmanColor.withValues(alpha: 0.9 * (1 - p));
      canvas.drawCircle(c, 48 * (1 - p) + 10, _ring);
      Glow.draw(canvas, c, 26 * (1 - p) + 6, const Color(0xFFFFFFFF).withValues(alpha: 0.7 * (1 - p)), hot: true);
      shipScale *= _easeOutBack(p);
    }
    if (leaving) {
      final p = (_leaveT / _warpOut).clamp(0.0, 1.0);
      _ring
        ..strokeWidth = 2.2 * (1 - p) + 0.5
        ..color = wingmanColor.withValues(alpha: 0.85 * (1 - p));
      canvas.drawCircle(c, 12 + 40 * p, _ring);
      Glow.draw(canvas, c, 10 + 22 * p, const Color(0xFFFFFFFF).withValues(alpha: 0.75 * (1 - p)), hot: true);
      alpha = 1 - p;
      shipScale *= 1 - 0.6 * p;
    }

    if (!leaving) {
      // Beacon: a slow plasma pulse going out, the "over here" that pulls
      // enemies onto it.
      final beat = (_age % 1.3) / 1.3;
      _ring
        ..strokeWidth = 1.6 * (1 - beat) + 0.4
        ..color = wingmanColor.withValues(alpha: 0.5 * (1 - beat));
      canvas.drawCircle(c, 16 + 34 * beat, _ring);

      // Hull: an arc around it that shrinks as it takes hits.
      final hf = hullFraction;
      final hit = _hitFlash > 0;
      _ring
        ..strokeWidth = hit ? 2.6 : 1.8
        ..color = (hit ? const Color(0xFFFFFFFF) : wingmanColor).withValues(alpha: hit ? 0.95 : 0.7);
      canvas.drawArc(Rect.fromCircle(center: c, radius: 19), -math.pi / 2, math.pi * 2 * hf, false, _ring);
    }

    // Blink through its last two seconds, like a pickup about to expire.
    final left = remaining;
    if (!leaving && left < 2 && (left * 8).floor().isOdd) return;

    Glow.draw(canvas, c, 20, wingmanColor.withValues(alpha: 0.35 * alpha));
    if (shipScale <= 0.01) return;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(_facing);
    canvas.scale(shipScale);
    if (alpha < 1) canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    ShipArt.paint(canvas, palette, time: _age, thrust: 0.7 + 0.3 * math.sin(_age * 9).abs(), engine: wingmanColor);
    if (alpha < 1) canvas.restore();
    canvas.restore();
    if (_hitFlash > 0) {
      Glow.draw(canvas, c, 16, const Color(0xFFFFFFFF).withValues(alpha: 0.6 * _hitFlash / 0.14), hot: true);
    }
  }
}

double _easeOutBack(double t) {
  const c1 = 1.70158;
  const c3 = c1 + 1;
  final x = t - 1;
  return 1 + c3 * x * x * x + c1 * x * x;
}
