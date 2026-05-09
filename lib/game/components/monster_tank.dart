import 'dart:math' as math;
import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterTank extends Monster {
  MonsterTank({required super.position, int playerLevel = 1})
      : super(stats: tankStats.scaled(playerLevel));

  static const _deathColors = [
    Color(0xFF8B0000), Color(0xFF78909C), Color(0xFFCC00FF),
    Color(0xFFBB0000), Color(0xFF6600CC), Color(0xFF00BBFF),
    Color(0xFFFF8800), Color(0xFFFFFFFF), Color(0xFF440088), Color(0xFFCCCCCC),
  ];

  @override
  Color get deathColor => _deathColors[(game.bossPhase % 10).clamp(0, 9)];

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

    switch (game.bossPhase % 10) {
      case 1:
        _renderMechanical(canvas, cx, cy);
      case 2:
        _renderVoid(canvas, cx, cy);
      default:
        _renderThemed(canvas, cx, cy);
    }

    canvas.restore();
    renderHpBar(canvas);
    renderFlash(canvas);
  }

  // Hull colour table for phases 0, 3-9 (reuses phase-0 shape).
  static const _hullColor = [
    Color(0xFF8B0000), Color(0xFF546E7A), Color(0xFF1A0033), // 0-2
    Color(0xFF550000), Color(0xFF1A0033), Color(0xFF002244), // 3-5
    Color(0xFF331100), Color(0xFF030808), Color(0xFF0A0015), Color(0xFF0A0A0A), // 6-9
  ];
  static const _outlineColor = [
    Color(0xFFAA2020), Color(0xFF78909C), Color(0xFFCC00FF),
    Color(0xFFAA0000), Color(0xFF6600CC), Color(0xFF0088FF),
    Color(0xFFFFAA00), Color(0xFF00FFCC), Color(0xFF5500AA), Color(0xFFAAAAAA),
  ];
  static const _eyeColor = [
    Color(0xFFFF8C00), Color(0xFF00E5FF), Color(0xFFFF00FF),
    Color(0xFFFF2200), Color(0xFF9900FF), Color(0xFF00FFFF),
    Color(0xFFFFDD00), Color(0xFF00FFAA), Color(0xFFAA00FF), Color(0xFFFFFFFF),
  ];
  static const _engineColor = [
    Color(0xFFFF6600), Color(0xFF0088FF), Color(0xFFCC00FF),
    Color(0xFFFF2200), Color(0xFF7700FF), Color(0xFF00AAFF),
    Color(0xFFFF8800), Color(0xFF00FFCC), Color(0xFF6600CC), Color(0xFFCCCCCC),
  ];
  static const _glowColor = [
    Color(0xAAFF4400), Color(0xAA0088FF), Color(0xAACC00FF),
    Color(0xAACC0000), Color(0xAA6600CC), Color(0xAA0088FF),
    Color(0xAAAA6600), Color(0xAA00FFAA), Color(0xAA440088), Color(0xAA888888),
  ];

  void _renderThemed(Canvas canvas, double cx, double cy) {
    final p = (game.bossPhase % 10).clamp(0, 9);

    // Engine glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 22), width: 22, height: 14),
      Paint()..color = _glowColor[p]..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final leftPod = Path()
      ..moveTo(cx - 14, cy - 6)..lineTo(cx - 22, cy - 2)
      ..lineTo(cx - 22, cy + 14)..lineTo(cx - 14, cy + 12)..close();
    final rightPod = Path()
      ..moveTo(cx + 14, cy - 6)..lineTo(cx + 22, cy - 2)
      ..lineTo(cx + 22, cy + 14)..lineTo(cx + 14, cy + 12)..close();
    final podPaint = Paint()..color = _hullColor[p].withAlpha(200);
    canvas.drawPath(leftPod, podPaint);
    canvas.drawPath(rightPod, podPaint);

    final hull = Path()
      ..moveTo(cx, cy - 24)..lineTo(cx + 12, cy - 14)
      ..lineTo(cx + 13, cy + 14)..lineTo(cx + 7, cy + 22)
      ..lineTo(cx - 7, cy + 22)..lineTo(cx - 13, cy + 14)
      ..lineTo(cx - 12, cy - 14)..close();
    canvas.drawPath(hull, Paint()..color = _hullColor[p]);
    canvas.drawPath(hull, Paint()
      ..color = _outlineColor[p]..style = PaintingStyle.stroke..strokeWidth = 2.0);

    // Guns
    final gunPaint = Paint()..color = _hullColor[p].withAlpha(180);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 4, cy - 22), width: 4, height: 10), gunPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx + 4, cy - 22), width: 4, height: 10), gunPaint);

    // Bridge + eyes
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy - 5), width: 13, height: 11),
        Paint()..color = _hullColor[p].withAlpha(220));
    canvas.drawCircle(Offset(cx - 3.5, cy - 5), 3.5, Paint()..color = _eyeColor[p]);
    canvas.drawCircle(Offset(cx + 3.5, cy - 5), 3.5, Paint()..color = _eyeColor[p]);

    // Engine ports
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 21), width: 6, height: 4),
        Paint()..color = _hullColor[p].withAlpha(200));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 21), width: 6, height: 4),
        Paint()..color = _hullColor[p].withAlpha(200));
    canvas.drawOval(Rect.fromCenter(center: Offset(cx - 4, cy + 22), width: 4, height: 3),
        Paint()..color = _engineColor[p]);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx + 4, cy + 22), width: 4, height: 3),
        Paint()..color = _engineColor[p]);
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
