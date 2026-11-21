import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../novabolt_game.dart';
import 'player.dart';
import 'shield_pickup.dart';

class HealthPickup extends PositionComponent
    with HasGameReference<NovaboltGame>, CollisionCallbacks {
  static const double healAmount = 30.0;
  static const double _lifetime = 8.0;

  double _timer = 0;

  HealthPickup({required Vector2 position})
      : super(
          position: position,
          size: Vector2.all(28),
          anchor: Anchor.center,
          priority: 2,
        );

  @override
  Future<void> onLoad() async {
    add(CircleHitbox()..collisionType = CollisionType.passive);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= _lifetime) removeFromParent();
  }

  @override
  void onCollisionStart(
      Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Player) {
      other.addHp(healAmount);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final r = size.x / 2;
    ShieldPickup.paintPickup(canvas, Offset(r, r), r, const Color(0xFF4DFFB0), _timer, _lifetime, (canvas, ink) {
      final p = Paint()..color = ink;
      canvas.drawRect(const Rect.fromLTWH(-1.8, -6, 3.6, 12), p);
      canvas.drawRect(const Rect.fromLTWH(-6, -1.8, 12, 3.6), p);
    });
  }
}
