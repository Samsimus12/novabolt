import 'dart:ui';

import 'package:flame/components.dart';

import 'player.dart';
import 'projectile.dart';

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
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Outer glow
    canvas.drawCircle(
      Offset(cx, cy),
      size.x / 2 + 5,
      Paint()
        ..color = const Color(0x8876FF03)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Core
    canvas.drawCircle(
      Offset(cx, cy),
      size.x / 2,
      Paint()..color = const Color(0xFF76FF03),
    );

    // Bright center
    canvas.drawCircle(
      Offset(cx, cy),
      size.x / 4,
      Paint()..color = const Color(0xFFEEFFCC),
    );
  }
}
