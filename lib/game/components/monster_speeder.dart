import 'dart:math' as math;
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

    // Rotate to face player
    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x) + math.pi / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    // Engine glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 8), width: 6, height: 8),
      Paint()
        ..color = const Color(0xAAFF4400)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Swept wings
    final wingPath = Path()
      ..moveTo(cx - 2, cy + 1)
      ..lineTo(cx - 9, cy + 7)
      ..lineTo(cx - 3, cy + 7)
      ..close()
      ..moveTo(cx + 2, cy + 1)
      ..lineTo(cx + 9, cy + 7)
      ..lineTo(cx + 3, cy + 7)
      ..close();
    canvas.drawPath(wingPath, Paint()..color = const Color(0xFFCC3700));

    // Fuselage
    final body = Path()
      ..moveTo(cx, cy - 9)
      ..lineTo(cx + 3, cy - 1)
      ..lineTo(cx + 3, cy + 6)
      ..lineTo(cx, cy + 4)
      ..lineTo(cx - 3, cy + 6)
      ..lineTo(cx - 3, cy - 1)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFFF4500));

    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFFFF7055)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // Tiny cockpit
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 4), width: 4, height: 5),
      Paint()..color = const Color(0xFF00CCDD),
    );

    // Engine fire
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 7), width: 3, height: 4),
      Paint()..color = const Color(0xFFFF9900),
    );

    canvas.restore();

    renderHpBar(canvas);
    renderFlash(canvas);
  }
}
