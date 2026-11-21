import 'dart:ui';

import 'package:flame/components.dart';

import 'monster.dart';
import 'projectile.dart';
import 'weapon.dart';
import '../fx/glow.dart';

class WeaponFrostShard extends Weapon {
  WeaponFrostShard() : super(damage: 10, fireRate: 1.2);

  @override
  String get displayName => 'EMP Burst';

  @override
  void fire(Vector2 playerPos, Vector2 direction) {
    game.world.add(FrostShard(
      position: playerPos.clone(),
      direction: direction,
      damage: damage,
    ));
  }
}

class FrostShard extends Projectile {
  FrostShard({
    required super.position,
    required super.direction,
    required double damage,
  }) : super(speed: 280, damage: damage, size: 9);

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    if (other is Monster) {
      other.takeDamage(damage);
      other.applySlow(0.4, 2.0);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    const ice = Color(0xFF9BE8FF);
    Glow.draw(canvas, c, size.x * 1.6, ice.withValues(alpha: 0.7));
    // Spinning ice diamond
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(lifetime * 9);
    final r = size.x * 0.7;
    final d = Path()
      ..moveTo(0, -r)
      ..lineTo(r * 0.55, 0)
      ..lineTo(0, r)
      ..lineTo(-r * 0.55, 0)
      ..close();
    canvas.drawPath(d, Paint()..color = const Color(0xFFE8FBFF));
    canvas.drawPath(
      d,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ice,
    );
    canvas.restore();
  }
}
