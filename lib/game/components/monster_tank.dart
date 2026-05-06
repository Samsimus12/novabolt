import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterTank extends Monster {
  MonsterTank({required super.position, int playerLevel = 1})
      : super(stats: tankStats.scaled(playerLevel));

  @override
  Color get deathColor => const Color(0xFF8B0000);

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;

    // Outer armored ring
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFF8B0000),
    );

    // Inner body
    canvas.drawCircle(
      Offset(cx, cy),
      r - 7,
      Paint()..color = const Color(0xFF3D0000),
    );

    // Riveted ring detail
    canvas.drawCircle(
      Offset(cx, cy),
      r - 3.5,
      Paint()
        ..color = const Color(0xFFAA2020)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    // Eyes (large, orange — menacing)
    final eyePaint = Paint()..color = const Color(0xFFFF8C00);
    canvas.drawCircle(Offset(cx - r * 0.28, cy - r * 0.12), 6, eyePaint);
    canvas.drawCircle(Offset(cx + r * 0.28, cy - r * 0.12), 6, eyePaint);

    // Pupils
    final pupilPaint = Paint()..color = const Color(0xFF1A0000);
    canvas.drawCircle(Offset(cx - r * 0.28, cy - r * 0.12), 3, pupilPaint);
    canvas.drawCircle(Offset(cx + r * 0.28, cy - r * 0.12), 3, pupilPaint);

    renderHpBar(canvas);
    renderFlash(canvas);
  }
}
