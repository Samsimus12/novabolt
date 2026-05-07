import 'dart:ui';

import 'package:flame/components.dart';

import 'player.dart';
import 'projectile.dart';

class BossProjectile extends Projectile {
  BossProjectile({
    required super.position,
    required super.direction,
    required double damage,
  }) : super(speed: 280, damage: damage, size: 14);

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
    final cx = size.x / 2;
    final cy = size.y / 2;
    canvas.drawCircle(
      Offset(cx, cy),
      size.x / 2 + 4,
      Paint()
        ..color = const Color(0xAAFF2200)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      size.x / 2,
      Paint()..color = const Color(0xFFFF3300),
    );
  }
}
