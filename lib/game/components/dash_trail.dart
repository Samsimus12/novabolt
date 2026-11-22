import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../fx/glow.dart';

/// The light streak a dash leaves behind: a tapered ion line that fades
/// over a quarter second, with a few sparks along it.
class DashTrail extends Component {
  final Vector2 from;
  final Vector2 to;
  double _t = 0;
  static const _life = 0.28;
  static const _color = Color(0xFF4DE8FF);

  DashTrail({required this.from, required this.to}) : super(priority: 2);

  @override
  void update(double dt) {
    _t += dt;
    if (_t >= _life) removeFromParent();
  }

  static final _line = Paint()
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;

  @override
  void render(Canvas canvas) {
    final f = 1 - _t / _life;
    final a = Offset(from.x, from.y);
    final b = Offset(to.x, to.y);
    // Tapered: draw a few segments that thicken toward the ship.
    const steps = 6;
    for (var i = 0; i < steps; i++) {
      final p0 = Offset.lerp(a, b, i / steps)!;
      final p1 = Offset.lerp(a, b, (i + 1) / steps)!;
      final w = (i + 1) / steps;
      _line
        ..strokeWidth = 14 * w * f + 1
        ..color = _color.withValues(alpha: 0.25 * f);
      canvas.drawLine(p0, p1, _line);
      _line
        ..strokeWidth = 4 * w * f + 0.5
        ..color = const Color(0xFFE0FBFF).withValues(alpha: 0.85 * f);
      canvas.drawLine(p0, p1, _line);
    }
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / math.max(1, d.distance);
    for (var i = 0; i < 5; i++) {
      final p = Offset.lerp(a, b, (i + 0.5) / 5)! + n * (math.sin(i * 2.3 + _t * 20) * 8);
      Glow.draw(canvas, p, 6 * f + 1, _color.withValues(alpha: 0.7 * f), hot: true);
    }
  }
}
