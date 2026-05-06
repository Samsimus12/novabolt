import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterSpeeder extends Monster {
  MonsterSpeeder({required super.position, int playerLevel = 1})
      : super(stats: speederStats.scaled(playerLevel));

  @override
  Color get deathColor => const Color(0xFFFF4500);

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;

    // Outer glow (speed aura)
    canvas.drawCircle(
      Offset(cx, cy),
      r + 3,
      Paint()
        ..color = const Color(0x55FF6B35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Body
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()..color = const Color(0xFFFF4500),
    );

    // Highlight stripe — gives a sense of motion
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = const Color(0xFFFF6B35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Tiny eyes
    final eyePaint = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(Offset(cx - r * 0.32, cy - r * 0.2), 2, eyePaint);
    canvas.drawCircle(Offset(cx + r * 0.32, cy - r * 0.2), 2, eyePaint);

    renderHpBar(canvas);
    renderFlash(canvas);
  }
}
