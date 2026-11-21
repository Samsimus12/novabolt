import 'dart:ui';

import 'package:flame/components.dart';

import 'player.dart';
import 'projectile.dart';
import '../fx/shot_art.dart';

class BossProjectile extends Projectile {
  final Color _color;

  BossProjectile({
    required super.position,
    required super.direction,
    required double damage,
    double speed = 280,
    double size = 14,
    Color color = const Color(0xFFFF3300),
  })  : _color = color,
        super(speed: speed, damage: damage, size: size);

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    if (other is Player) {
      other.takeDamage(damage);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    ShotArt.orb(canvas, Offset(size.x / 2, size.y / 2), size.x / 2, _color, time: lifetime);
  }
}
