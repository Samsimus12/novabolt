import 'dart:math' as math;
import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterTank extends Monster {
  MonsterTank({required super.position, int playerLevel = 1})
      : super(stats: tankStats.scaled(playerLevel));

  @override
  Color get deathColor {
    return switch (game.bossPhase.clamp(0, 2)) {
      1 => const Color(0xFF78909C),
      2 => const Color(0xFFCC00FF),
      _ => const Color(0xFF8B0000),
    };
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;

    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x) + math.pi / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    switch (game.bossPhase.clamp(0, 2)) {
      case 1:
        _renderMechanical(canvas, cx, cy);
      case 2:
        _renderVoid(canvas, cx, cy);
      default:
        _renderOrganic(canvas, cx, cy);
    }

    canvas.restore();
    renderHpBar(canvas);
    renderFlash(canvas);
  }

  // Phase 0 — dark red capital warship
  void _renderOrganic(Canvas canvas, double cx, double cy) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 22), width: 22, height: 14),
      Paint()
        ..color = const Color(0xAAFF4400)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final leftPod = Path()
      ..moveTo(cx - 14, cy - 6)
      ..lineTo(cx - 22, cy - 2)
      ..lineTo(cx - 22, cy + 14)
      ..lineTo(cx - 14, cy + 12)
      ..close();
    final rightPod = Path()
      ..moveTo(cx + 14, cy - 6)
      ..lineTo(cx + 22, cy - 2)
      ..lineTo(cx + 22, cy + 14)
      ..lineTo(cx + 14, cy + 12)
      ..close();
    final podPaint = Paint()..color = const Color(0xFF6B0000);
    canvas.drawPath(leftPod, podPaint);
    canvas.drawPath(rightPod, podPaint);

    final gunPaint = Paint()..color = const Color(0xFF3D0000);
    canvas.drawRect(Rect.fromLTWH(cx - 25, cy - 7, 5, 9), gunPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 20, cy - 7, 5, 9), gunPaint);

    final hull = Path()
      ..moveTo(cx, cy - 24)
      ..lineTo(cx + 12, cy - 14)
      ..lineTo(cx + 13, cy + 14)
      ..lineTo(cx + 7, cy + 22)
      ..lineTo(cx - 7, cy + 22)
      ..lineTo(cx - 13, cy + 14)
      ..lineTo(cx - 12, cy - 14)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF8B0000));

    final innerHull = Path()
      ..moveTo(cx, cy - 18)
      ..lineTo(cx + 8, cy - 10)
      ..lineTo(cx + 9, cy + 10)
      ..lineTo(cx + 4, cy + 18)
      ..lineTo(cx - 4, cy + 18)
      ..lineTo(cx - 9, cy + 10)
      ..lineTo(cx - 8, cy - 10)
      ..close();
    canvas.drawPath(innerHull, Paint()..color = const Color(0xFF3D0000));

    canvas.drawPath(hull, Paint()
      ..color = const Color(0xFFAA2020)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);

    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 4, cy - 22), width: 4, height: 10), gunPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx + 4, cy - 22), width: 4, height: 10), gunPaint);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 5), width: 13, height: 11),
      Paint()..color = const Color(0xFF5A0000),
    );
    final eyePaint = Paint()..color = const Color(0xFFFF8C00);
    canvas.drawCircle(Offset(cx - 3.5, cy - 5), 3.5, eyePaint);
    canvas.drawCircle(Offset(cx + 3.5, cy - 5), 3.5, eyePaint);
    final pupilPaint = Paint()..color = const Color(0xFF1A0000);
    canvas.drawCircle(Offset(cx - 3.5, cy - 5), 1.5, pupilPaint);
    canvas.drawCircle(Offset(cx + 3.5, cy - 5), 1.5, pupilPaint);

    final portPaint = Paint()..color = const Color(0xFF1A0000);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 21), width: 6, height: 4), portPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 21), width: 6, height: 4), portPaint);
    final firePaint = Paint()..color = const Color(0xFFFF6600);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 22), width: 4, height: 3), firePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 22), width: 4, height: 3), firePaint);
  }

  // Phase 1 — steel/gray industrial juggernaut
  void _renderMechanical(Canvas canvas, double cx, double cy) {
    // Blue-white engine glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 22), width: 22, height: 14),
      Paint()
        ..color = const Color(0xAA0088FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Blockier side pods
    final leftPod = Path()
      ..moveTo(cx - 13, cy - 6)
      ..lineTo(cx - 24, cy - 4)
      ..lineTo(cx - 24, cy + 14)
      ..lineTo(cx - 13, cy + 12)
      ..close();
    final rightPod = Path()
      ..moveTo(cx + 13, cy - 6)
      ..lineTo(cx + 24, cy - 4)
      ..lineTo(cx + 24, cy + 14)
      ..lineTo(cx + 13, cy + 12)
      ..close();
    canvas.drawPath(leftPod, Paint()..color = const Color(0xFF37474F));
    canvas.drawPath(rightPod, Paint()..color = const Color(0xFF37474F));
    // Pod edge
    canvas.drawPath(leftPod, Paint()
      ..color = const Color(0xFF546E7A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);
    canvas.drawPath(rightPod, Paint()
      ..color = const Color(0xFF546E7A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);

    final gunPaint = Paint()..color = const Color(0xFF263238);
    canvas.drawRect(Rect.fromLTWH(cx - 27, cy - 7, 5, 9), gunPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 22, cy - 7, 5, 9), gunPaint);

    final hull = Path()
      ..moveTo(cx, cy - 24)
      ..lineTo(cx + 12, cy - 14)
      ..lineTo(cx + 13, cy + 14)
      ..lineTo(cx + 7, cy + 22)
      ..lineTo(cx - 7, cy + 22)
      ..lineTo(cx - 13, cy + 14)
      ..lineTo(cx - 12, cy - 14)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF546E7A));

    final innerHull = Path()
      ..moveTo(cx, cy - 18)
      ..lineTo(cx + 8, cy - 10)
      ..lineTo(cx + 9, cy + 10)
      ..lineTo(cx + 4, cy + 18)
      ..lineTo(cx - 4, cy + 18)
      ..lineTo(cx - 9, cy + 10)
      ..lineTo(cx - 8, cy - 10)
      ..close();
    canvas.drawPath(innerHull, Paint()..color = const Color(0xFF37474F));

    canvas.drawPath(hull, Paint()
      ..color = const Color(0xFF78909C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);

    // Vent slits on hull
    for (int i = -1; i <= 1; i++) {
      canvas.drawRect(
        Rect.fromLTWH(cx - 3, cy + 2 + i * 5.0, 6, 2),
        Paint()..color = const Color(0xFF263238),
      );
    }

    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 4, cy - 22), width: 4, height: 10), gunPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx + 4, cy - 22), width: 4, height: 10), gunPaint);

    // Command bridge
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 5), width: 13, height: 11),
      Paint()..color = const Color(0xFF37474F),
    );
    // Cyan viewport slits
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 3.5, cy - 5), width: 5, height: 3),
        Paint()..color = const Color(0xFF00E5FF));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 3.5, cy - 5), width: 5, height: 3),
        Paint()..color = const Color(0xFF00E5FF));

    // Engine ports (blue)
    final portPaint = Paint()..color = const Color(0xFF1A2327);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 21), width: 6, height: 4), portPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 21), width: 6, height: 4), portPaint);
    final firePaint = Paint()..color = const Color(0xFF0088FF);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 22), width: 4, height: 3), firePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 22), width: 4, height: 3), firePaint);
  }

  // Phase 2 — void-corrupted dreadnought
  void _renderVoid(Canvas canvas, double cx, double cy) {
    // Purple void engine glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 22), width: 22, height: 14),
      Paint()
        ..color = const Color(0xAACC00FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    final leftPod = Path()
      ..moveTo(cx - 14, cy - 6)
      ..lineTo(cx - 22, cy - 2)
      ..lineTo(cx - 22, cy + 14)
      ..lineTo(cx - 14, cy + 12)
      ..close();
    final rightPod = Path()
      ..moveTo(cx + 14, cy - 6)
      ..lineTo(cx + 22, cy - 2)
      ..lineTo(cx + 22, cy + 14)
      ..lineTo(cx + 14, cy + 12)
      ..close();
    canvas.drawPath(leftPod, Paint()..color = const Color(0xFF0D001A));
    canvas.drawPath(rightPod, Paint()..color = const Color(0xFF0D001A));
    canvas.drawPath(leftPod, Paint()
      ..color = const Color(0xFF9900CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);
    canvas.drawPath(rightPod, Paint()
      ..color = const Color(0xFF9900CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);

    final gunPaint = Paint()..color = const Color(0xFF110022);
    canvas.drawRect(Rect.fromLTWH(cx - 25, cy - 7, 5, 9), gunPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 20, cy - 7, 5, 9), gunPaint);

    final hull = Path()
      ..moveTo(cx, cy - 24)
      ..lineTo(cx + 12, cy - 14)
      ..lineTo(cx + 13, cy + 14)
      ..lineTo(cx + 7, cy + 22)
      ..lineTo(cx - 7, cy + 22)
      ..lineTo(cx - 13, cy + 14)
      ..lineTo(cx - 12, cy - 14)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF1A0033));

    final innerHull = Path()
      ..moveTo(cx, cy - 18)
      ..lineTo(cx + 8, cy - 10)
      ..lineTo(cx + 9, cy + 10)
      ..lineTo(cx + 4, cy + 18)
      ..lineTo(cx - 4, cy + 18)
      ..lineTo(cx - 9, cy + 10)
      ..lineTo(cx - 8, cy - 10)
      ..close();
    canvas.drawPath(innerHull, Paint()..color = const Color(0xFF0D0020));

    canvas.drawPath(hull, Paint()
      ..color = const Color(0xFFCC00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0);

    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 4, cy - 22), width: 4, height: 10), gunPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx + 4, cy - 22), width: 4, height: 10), gunPaint);

    // Command bridge with three void eyes
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 5), width: 13, height: 11),
      Paint()..color = const Color(0xFF110022),
    );
    // Central dominant eye
    canvas.drawCircle(Offset(cx, cy - 5), 3.5, Paint()..color = const Color(0xFFCC00FF));
    canvas.drawCircle(Offset(cx, cy - 5), 1.8, Paint()..color = const Color(0xFFFF00FF));
    canvas.drawCircle(Offset(cx, cy - 5), 0.8, Paint()..color = const Color(0xFF000000));
    // Flanking eyes
    canvas.drawCircle(Offset(cx - 5, cy - 4), 2.0, Paint()..color = const Color(0xFF9900CC));
    canvas.drawCircle(Offset(cx + 5, cy - 4), 2.0, Paint()..color = const Color(0xFF9900CC));

    // Engine ports (void purple)
    final portPaint = Paint()..color = const Color(0xFF0D0020);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 21), width: 6, height: 4), portPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 21), width: 6, height: 4), portPaint);
    final firePaint = Paint()..color = const Color(0xFFCC00FF);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 22), width: 4, height: 3), firePaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 22), width: 4, height: 3), firePaint);
  }
}
