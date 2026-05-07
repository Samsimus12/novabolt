import 'dart:math' as math;
import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterGrunt extends Monster {
  MonsterGrunt({required super.position, int playerLevel = 1})
      : super(stats: gruntStats.scaled(playerLevel));

  double _rotAngle = 0;

  // Radius factors for 12 vertices — hand-tuned for a craggy silhouette
  static const _rFactors = [0.90, 0.65, 0.85, 0.72, 1.00, 0.68, 0.88, 0.62, 0.92, 0.78, 0.70, 0.95];
  static const _baseR = 14.0;

  @override
  void update(double dt) {
    super.update(dt);
    _rotAngle += 0.5 * dt;
  }

  Path _buildPath(double cx, double cy) {
    final path = Path();
    const n = 12;
    for (int i = 0; i < n; i++) {
      final a = _rotAngle + (i / n) * 2 * math.pi;
      final r = _baseR * _rFactors[i];
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  @override
  Color get deathColor => const Color(0xFF8B7355);

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    final path = _buildPath(cx, cy);

    // Rock body
    canvas.drawPath(path, Paint()..color = const Color(0xFF7A6652));

    // Lighter edge highlight
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF9A8268)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Craters — rotate with the rock
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(_rotAngle);
    final craterPaint = Paint()..color = const Color(0xFF4A3A2A);
    canvas.drawCircle(const Offset(-5.0, -3.0), 3.5, craterPaint);
    canvas.drawCircle(const Offset(4.0, 5.0), 2.5, craterPaint);
    canvas.drawCircle(const Offset(-3.0, 6.0), 2.0, craterPaint);
    canvas.drawCircle(const Offset(6.0, -4.5), 1.8, craterPaint);
    canvas.restore();

    renderHpBar(canvas);
    renderFlash(canvas);
  }
}
