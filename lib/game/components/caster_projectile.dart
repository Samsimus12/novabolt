import 'dart:ui';

import 'package:flame/components.dart';

import 'player.dart';
import 'projectile.dart';
import '../fx/shot_art.dart';

class CasterProjectile extends Projectile {
  CasterProjectile({
    required super.position,
    required super.direction,
  }) : super(speed: 220, damage: 12, size: 10);

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
    ShotArt.orb(canvas, Offset(size.x / 2, size.y / 2), size.x / 2, const Color(0xFF8CFF2E), time: lifetime);
  }
}
