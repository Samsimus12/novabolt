import 'dart:math' as math;
import 'dart:ui';

import '../data/monster_data.dart';
import 'monster.dart';

class MonsterSpeeder extends Monster {
  MonsterSpeeder({required super.position, int playerLevel = 1})
      : super(stats: speederStats.scaled(playerLevel));

  static const _deathColors = [
    Color(0xFFFF4500), Color(0xFF00E5FF), Color(0xFFFF00FF),
    Color(0xFFCC2200), Color(0xFF9900FF), Color(0xFF00FFFF),
    Color(0xFFFFAA00), Color(0xFFCCFFAA), Color(0xFF6600CC), Color(0xFFFFFFFF),
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

  static const _bodyColor = [
    Color(0xFFFF4500), Color(0xFF546E7A), Color(0xFF1A0033),
    Color(0xFF880000), Color(0xFF1A0033), Color(0xFF003344),
    Color(0xFF662200), Color(0xFF020808), Color(0xFF0A0010), Color(0xFF0A0A0A),
  ];
  static const _wingColor = [
    Color(0xFFCC3700), Color(0xFF37474F), Color(0xFF1A0033),
    Color(0xFF550000), Color(0xFF220044), Color(0xFF004455),
    Color(0xFF441100), Color(0xFF010404), Color(0xFF060012), Color(0xFF050505),
  ];
  static const _cockpitColor = [
    Color(0xFF00CCDD), Color(0xFF00E5FF), Color(0xFFFF00FF),
    Color(0xFFFF4400), Color(0xFF9900FF), Color(0xFF00FFFF),
    Color(0xFFFFDD00), Color(0xFF00FFAA), Color(0xFF8800FF), Color(0xFFFFFFFF),
  ];
  static const _thrustColor = [
    Color(0xFFFF9900), Color(0xFF00E5FF), Color(0xFFFF00FF),
    Color(0xFFFF3300), Color(0xFF8800FF), Color(0xFF00CCFF),
    Color(0xFFFF8800), Color(0xFF00FFCC), Color(0xFF7700CC), Color(0xFFDDDDDD),
  ];
  static const _glowColor = [
    Color(0xAAFF4400), Color(0xAA00E5FF), Color(0xAAFF00FF),
    Color(0xAACC0000), Color(0xAA7700FF), Color(0xAA00CCFF),
    Color(0xAAAA6600), Color(0xAA00FFAA), Color(0xAA5500BB), Color(0xAAAAAAAAAA),
  ];

  void _renderThemed(Canvas canvas, double cx, double cy) {
    final p = (game.bossPhase % 10).clamp(0, 9);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 8), width: 6, height: 8),
      Paint()..color = _glowColor[p]..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    final wingPath = Path()
      ..moveTo(cx - 2, cy + 1)..lineTo(cx - 9, cy + 7)..lineTo(cx - 3, cy + 7)..close()
      ..moveTo(cx + 2, cy + 1)..lineTo(cx + 9, cy + 7)..lineTo(cx + 3, cy + 7)..close();
    canvas.drawPath(wingPath, Paint()..color = _wingColor[p]);

    final body = Path()
      ..moveTo(cx, cy - 9)..lineTo(cx + 3, cy - 1)..lineTo(cx + 3, cy + 6)
      ..lineTo(cx, cy + 4)..lineTo(cx - 3, cy + 6)..lineTo(cx - 3, cy - 1)..close();
    canvas.drawPath(body, Paint()..color = _bodyColor[p]);
    canvas.drawPath(body, Paint()
      ..color = _cockpitColor[p].withAlpha(120)..style = PaintingStyle.stroke..strokeWidth = 0.8);

    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy - 4), width: 4, height: 5),
        Paint()..color = _cockpitColor[p]);
    canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + 7), width: 3, height: 4),
        Paint()..color = _thrustColor[p]);
  }

  // Phase 0 — red-orange scout fighter
  void _renderOrganic(Canvas canvas, double cx, double cy) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 8), width: 6, height: 8),
      Paint()
        ..color = const Color(0xAAFF4400)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

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

    final body = Path()
      ..moveTo(cx, cy - 9)
      ..lineTo(cx + 3, cy - 1)
      ..lineTo(cx + 3, cy + 6)
      ..lineTo(cx, cy + 4)
      ..lineTo(cx - 3, cy + 6)
      ..lineTo(cx - 3, cy - 1)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFFF4500));
    canvas.drawPath(body, Paint()
      ..color = const Color(0xFFFF7055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 4), width: 4, height: 5),
      Paint()..color = const Color(0xFF00CCDD),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 7), width: 3, height: 4),
      Paint()..color = const Color(0xFFFF9900),
    );
  }

  // Phase 1 — steel/cyan cyber drone
  void _renderMechanical(Canvas canvas, double cx, double cy) {
    // Cyan engine glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 8), width: 7, height: 9),
      Paint()
        ..color = const Color(0xAA00E5FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Wider delta wings
    final wingPath = Path()
      ..moveTo(cx - 2, cy + 1)
      ..lineTo(cx - 11, cy + 8)
      ..lineTo(cx - 5, cy + 8)
      ..close()
      ..moveTo(cx + 2, cy + 1)
      ..lineTo(cx + 11, cy + 8)
      ..lineTo(cx + 5, cy + 8)
      ..close();
    canvas.drawPath(wingPath, Paint()..color = const Color(0xFF37474F));
    // Wing edge highlight
    canvas.drawPath(wingPath, Paint()
      ..color = const Color(0xFF78909C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8);

    // Angular fuselage
    final body = Path()
      ..moveTo(cx, cy - 9)
      ..lineTo(cx + 4, cy)
      ..lineTo(cx + 3, cy + 6)
      ..lineTo(cx, cy + 5)
      ..lineTo(cx - 3, cy + 6)
      ..lineTo(cx - 4, cy)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF546E7A));
    canvas.drawPath(body, Paint()
      ..color = const Color(0xFF90A4AE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8);

    // Antenna
    canvas.drawLine(
      Offset(cx, cy - 9), Offset(cx, cy - 12),
      Paint()..color = const Color(0xFF90A4AE)..strokeWidth = 1.0,
    );
    canvas.drawCircle(Offset(cx, cy - 12), 1.5, Paint()..color = const Color(0xFF00E5FF));

    // Cyan cockpit
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 3), width: 4, height: 5),
      Paint()..color = const Color(0xFF00E5FF),
    );

    // Cyan engine fire
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 7), width: 3, height: 4),
      Paint()..color = const Color(0xFF00E5FF),
    );
  }

  // Phase 2 — void dart / lance
  void _renderVoid(Canvas canvas, double cx, double cy) {
    // Magenta trail glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 9), width: 6, height: 12),
      Paint()
        ..color = const Color(0xAAFF00FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // Thin swept wings
    final wingPath = Path()
      ..moveTo(cx - 1, cy - 1)
      ..lineTo(cx - 9, cy + 7)
      ..lineTo(cx - 3, cy + 6)
      ..close()
      ..moveTo(cx + 1, cy - 1)
      ..lineTo(cx + 9, cy + 7)
      ..lineTo(cx + 3, cy + 6)
      ..close();
    canvas.drawPath(wingPath, Paint()..color = const Color(0xFF1A0033));
    canvas.drawPath(wingPath, Paint()
      ..color = const Color(0xFF9900CC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7);

    // Elongated lance body
    final body = Path()
      ..moveTo(cx, cy - 10)
      ..lineTo(cx + 2.5, cy + 1)
      ..lineTo(cx + 2.5, cy + 7)
      ..lineTo(cx, cy + 6)
      ..lineTo(cx - 2.5, cy + 7)
      ..lineTo(cx - 2.5, cy + 1)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF1A0033));
    canvas.drawPath(body, Paint()
      ..color = const Color(0xFFCC00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8);

    // Single void eye
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 4), width: 5, height: 6),
      Paint()..color = const Color(0xFFFF00FF),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 4), width: 2.5, height: 3),
      Paint()..color = const Color(0xFF000000),
    );

    // Magenta engine flame
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 7), width: 3, height: 4),
      Paint()..color = const Color(0xFFFF00FF),
    );
  }
}
