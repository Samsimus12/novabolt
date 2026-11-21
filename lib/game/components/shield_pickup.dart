import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/collisions.dart';
import 'package:flame/components.dart';

import '../fx/glow.dart';
import '../novabolt_game.dart';
import 'player.dart';

class ShieldPickup extends PositionComponent
    with HasGameReference<NovaboltGame>, CollisionCallbacks {
  static const double shieldAmount = 50.0;
  static const double _lifetime = 8.0;

  double _timer = 0;

  ShieldPickup({required Vector2 position})
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
      other.addShield(shieldAmount);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final r = size.x / 2;
    paintPickup(canvas, Offset(r, r), r, const Color(0xFF4DE8FF), _timer, _lifetime, (canvas, ink) {
      final shield = Path()
        ..moveTo(0, -6.5)
        ..lineTo(5.5, -4)
        ..cubicTo(5.5, 1.5, 3.5, 5, 0, 7)
        ..cubicTo(-3.5, 5, -5.5, 1.5, -5.5, -4)
        ..close();
      canvas.drawPath(shield, Paint()..color = ink);
    });
  }

  // Shared pickup look: a slowly turning chamfered diamond holding a glyph,
  // bobbing in place; blinks during its last two seconds.
  static void paintPickup(Canvas canvas, Offset c, double r, Color color, double timer, double lifetime,
      void Function(Canvas canvas, Color ink) glyph) {
    final left = lifetime - timer;
    if (left < 2 && (left * 8).floor().isOdd) return;
    final bob = math.sin(timer * 3) * 2;
    final center = c.translate(0, bob);
    Glow.draw(canvas, center, r * 2.2, color.withValues(alpha: 0.45 + 0.15 * math.sin(timer * 5)));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.save();
    canvas.rotate(timer * 0.8);
    final d = Path()
      ..moveTo(0, -r)
      ..lineTo(r, 0)
      ..lineTo(0, r)
      ..lineTo(-r, 0)
      ..close();
    canvas.drawPath(d, Paint()..color = const Color(0xE6050817));
    canvas.drawPath(
      d,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );
    canvas.restore();
    glyph(canvas, color);
    canvas.restore();
  }
}
