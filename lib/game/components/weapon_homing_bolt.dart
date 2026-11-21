import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../fx/glow.dart';
import 'monster.dart';
import 'projectile.dart';
import 'weapon.dart';

class WeaponHomingBolt extends Weapon {
  WeaponHomingBolt() : super(damage: 12, fireRate: 1.5);

  @override
  String get displayName => 'Homing Missile';

  @override
  void fire(Vector2 playerPos, Vector2 direction) {
    game.world.add(HomingBolt(
      position: playerPos.clone(),
      direction: direction,
      damage: damage,
    ));
  }
}

class HomingBolt extends Projectile {
  static const _turnRate = 3.0;

  late Vector2 _velocity;

  HomingBolt({
    required super.position,
    required super.direction,
    required super.damage,
  }) : super(speed: 220, size: 11) {
    _velocity = direction * 220;
  }

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.active);
  }

  @override
  void update(double dt) {
    Monster? nearest;
    double minDist = double.infinity;
    for (final m in game.world.children.whereType<Monster>()) {
      final d = m.position.distanceTo(position);
      if (d < minDist) {
        minDist = d;
        nearest = m;
      }
    }

    if (nearest != null) {
      final toTarget = (nearest.position - position).normalized();
      final newDir = (_velocity.normalized() + toTarget * (_turnRate * dt)).normalized();
      _velocity = newDir * speed;
    }

    position += _velocity * dt;
    lifetime += dt;

    final gs = game.size;
    if (lifetime > 5.0 ||
        position.x < -60 ||
        position.x > gs.x + 60 ||
        position.y < -60 ||
        position.y > gs.y + 60) {
      removeFromParent();
    }
  }

  @override
  void onHit(PositionComponent other) {
    if (other is Monster) {
      other.takeDamage(damage);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    final a = math.atan2(_velocity.y, _velocity.x);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(a);
    // Exhaust plume behind the missile.
    final flicker = 0.8 + 0.2 * math.sin(lifetime * 60);
    Glow.drawOval(canvas, Rect.fromLTRB(-24 * flicker, -5, -2, 5), const Color(0xFFB98CFF));
    Glow.drawOval(canvas, Rect.fromLTRB(-12 * flicker, -2.5, -2, 2.5), const Color(0xFFFFFFFF), hot: true);
    // Body
    final body = Path()
      ..moveTo(7, 0)
      ..lineTo(2, -2.6)
      ..lineTo(-5, -2.6)
      ..lineTo(-7, -4.5)
      ..lineTo(-7, 4.5)
      ..lineTo(-5, 2.6)
      ..lineTo(2, 2.6)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFE6DAFF));
    canvas.drawCircle(const Offset(5, 0), 1.6, Paint()..color = const Color(0xFFA07CFF));
    canvas.restore();
  }
}
