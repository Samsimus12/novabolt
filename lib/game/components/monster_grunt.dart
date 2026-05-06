import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterGrunt extends Monster {
  MonsterGrunt({required super.position, int playerLevel = 1})
      : super(stats: gruntStats.scaled(playerLevel));

  @override
  Color get deathColor => const Color(0xFFCC2936);

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;

    // Body
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFFCC2936),
    );

    // Eyes
    final eyePaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(cx - r * 0.28, cy - r * 0.15), 3.5, eyePaint);
    canvas.drawCircle(Offset(cx + r * 0.28, cy - r * 0.15), 3.5, eyePaint);

    // Pupils
    final pupilPaint = Paint()..color = const Color(0xFF000000);
    canvas.drawCircle(Offset(cx - r * 0.28, cy - r * 0.15), 1.5, pupilPaint);
    canvas.drawCircle(Offset(cx + r * 0.28, cy - r * 0.15), 1.5, pupilPaint);

    renderHpBar(canvas);
    renderFlash(canvas);
  }
}
