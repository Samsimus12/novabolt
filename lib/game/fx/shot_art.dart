import 'dart:math' as math;
import 'dart:ui';

import 'glow.dart';

/// Projectile looks. Player fire is drawn as directional *streaks*; hostile
/// fire as ringed *orbs* — so you can tell what will hurt you by shape alone,
/// whatever the color.
abstract final class ShotArt {
  static final _core = Paint()..strokeCap = StrokeCap.round;
  static final _ring = Paint()..style = PaintingStyle.stroke;

  /// Streak centerd on [c] traveling at [angle], [len] long, [width] thick.
  static void streak(Canvas canvas, Offset c, double angle, double len, double width, Color color) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    Glow.drawOval(
      canvas,
      Rect.fromCenter(center: Offset(-len * 0.15, 0), width: len * 2.1, height: width * 3.6),
      color.withValues(alpha: 0.85),
    );
    _core
      ..strokeWidth = width
      ..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.75)!;
    canvas.drawLine(Offset(-len / 2, 0), Offset(len / 2, 0), _core);
    canvas.restore();
  }

  /// Hostile orb: colored halo, a darker rim ring and a white-hot core.
  static void orb(Canvas canvas, Offset c, double r, Color color, {double time = 0}) {
    final pulse = 1 + 0.08 * math.sin(time * 18);
    Glow.draw(canvas, c, r * 2.6 * pulse, color.withValues(alpha: 0.75));
    _ring
      ..strokeWidth = math.max(1.5, r * 0.28)
      ..color = color;
    canvas.drawCircle(c, r * 0.82, _ring);
    Glow.draw(canvas, c, r * 1.05, const Color(0xFFFFFFFF), hot: true);
  }
}
