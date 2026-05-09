import 'dart:math' as math;
import 'dart:ui';

import '../data/monster_data.dart';
import 'caster_projectile.dart';
import 'monster.dart';

class MonsterCaster extends Monster {
  static const _preferredRange = 200.0;
  static const _retreatRange = 130.0;
  static const _fireInterval = 2.5;

  double _fireTimer = 1.5;

  MonsterCaster({required super.position, int playerLevel = 1})
      : super(stats: casterStats.scaled(playerLevel));

  static const _deathColors = [
    Color(0xFF7C4DFF), Color(0xFF00E5FF), Color(0xFFFF00FF),
    Color(0xFFCC0000), Color(0xFF8800FF), Color(0xFF00FFFF),
    Color(0xFFFFAA00), Color(0xFF00FFCC), Color(0xFF5500AA), Color(0xFFFFFFFF),
  ];

  @override
  Color get deathColor => _deathColors[(game.bossPhase % 10).clamp(0, 9)];

  @override
  void updateMovement(double dt) {
    final dir = game.player.position - position;
    final dist = dir.length;
    if (dist < 1) return;
    if (dist > _preferredRange) {
      position += dir.normalized() * stats.speed * slowFactor * dt;
    } else if (dist < _retreatRange) {
      position -= dir.normalized() * stats.speed * slowFactor * dt;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;
    _fireTimer -= dt;
    if (_fireTimer <= 0) {
      _fireTimer = _fireInterval;
      _fire();
    }
  }

  void _fire() {
    final dir = game.player.position - position;
    if (dir.length < 1) return;
    game.world.add(CasterProjectile(
      position: position.clone(),
      direction: dir.normalized(),
    ));
  }

  @override
  void render(Canvas canvas) {
    final cx = size.x / 2;
    final cy = size.y / 2;
    final r = size.x / 2;
    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x);

    switch (game.bossPhase % 10) {
      case 0:
        _renderOrganic(canvas, cx, cy, r, angle);
      case 1:
        _renderMechanical(canvas, cx, cy, r, angle);
      case 2:
        _renderVoid(canvas, cx, cy, r, angle);
      default:
        _renderThemed(canvas, cx, cy, r, angle);
    }

    renderHpBar(canvas);
    renderFlash(canvas);
  }

  // Phase 0 — purple hexagon mage
  void _renderOrganic(Canvas canvas, double cx, double cy, double r, double angle) {
    canvas.drawCircle(Offset(cx, cy), r + 4, Paint()
      ..color = const Color(0x557C4DFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    final hex = Path();
    for (int i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) hex.moveTo(x, y);
      else hex.lineTo(x, y);
    }
    hex.close();
    canvas.drawPath(hex, Paint()..color = const Color(0xFF311B92));
    canvas.drawPath(hex, Paint()
      ..color = const Color(0xFF7C4DFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, -3, r - 2, 6), const Radius.circular(2)),
      Paint()..color = const Color(0xFF4527A0),
    );
    canvas.drawCircle(Offset(r - 1, 0), 3, Paint()..color = const Color(0xFF76FF03));
    canvas.restore();

    canvas.drawCircle(Offset(cx, cy), 7, Paint()
      ..color = const Color(0xAA76FF03)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = const Color(0xFFB2FF59));

    final chargeAlpha = (_fireTimer / _fireInterval * 180).toInt().clamp(0, 180);
    canvas.drawCircle(Offset(cx, cy), 11, Paint()
      ..color = Color.fromARGB(chargeAlpha, 118, 255, 3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  // Phase 1 — chrome orbital turret
  void _renderMechanical(Canvas canvas, double cx, double cy, double r, double angle) {
    // Outer gear ring
    canvas.drawCircle(Offset(cx, cy), r + 5, Paint()
      ..color = const Color(0xFF455A64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4);

    // Gear teeth
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final tx = cx + (r + 5) * math.cos(a);
      final ty = cy + (r + 5) * math.sin(a);
      canvas.save();
      canvas.translate(tx, ty);
      canvas.rotate(a);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 5, height: 3),
        Paint()..color = const Color(0xFF546E7A),
      );
      canvas.restore();
    }

    // Octagonal body
    final oct = Path();
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final x = cx + r * math.cos(a);
      final y = cy + r * math.sin(a);
      if (i == 0) oct.moveTo(x, y);
      else oct.lineTo(x, y);
    }
    oct.close();
    canvas.drawPath(oct, Paint()..color = const Color(0xFF455A64));
    canvas.drawPath(oct, Paint()
      ..color = const Color(0xFF78909C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // Mechanical barrel
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, -3, r - 2, 6), const Radius.circular(2)),
      Paint()..color = const Color(0xFF37474F),
    );
    canvas.drawCircle(Offset(r - 1, 0), 3, Paint()..color = const Color(0xFF00E5FF));
    canvas.restore();

    // Cyan inner core
    canvas.drawCircle(Offset(cx, cy), 7, Paint()
      ..color = const Color(0xAA00E5FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = const Color(0xFF00E5FF));

    final chargeAlpha = (_fireTimer / _fireInterval * 180).toInt().clamp(0, 180);
    canvas.drawCircle(Offset(cx, cy), 11, Paint()
      ..color = Color.fromARGB(chargeAlpha, 0, 229, 255)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  // Phase 2 — void eye with tendrils
  void _renderVoid(Canvas canvas, double cx, double cy, double r, double angle) {
    // Void aura
    canvas.drawCircle(Offset(cx, cy), r + 6, Paint()
      ..color = const Color(0x55CC00FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

    // Dark body
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = const Color(0xFF0D0020));

    // Spike/tendril border
    for (int i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        Offset(cx + r * math.cos(a), cy + r * math.sin(a)),
        Offset(cx + (r + 8) * math.cos(a), cy + (r + 8) * math.sin(a)),
        Paint()
          ..color = const Color(0xFFCC00FF)
          ..strokeWidth = 1.5,
      );
    }

    canvas.drawCircle(Offset(cx, cy), r, Paint()
      ..color = const Color(0xFFCC00FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);

    // Void barrel
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, -3, r - 2, 6), const Radius.circular(2)),
      Paint()..color = const Color(0xFF1A0033),
    );
    canvas.drawCircle(Offset(r - 1, 0), 3, Paint()..color = const Color(0xFFFF00FF));
    canvas.restore();

    // Central void eye
    canvas.drawCircle(Offset(cx, cy), 7, Paint()
      ..color = const Color(0xAACC00FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = const Color(0xFFFF00FF));
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = const Color(0xFF000000));
    canvas.drawCircle(Offset(cx, cy), 1, Paint()..color = const Color(0xFFFFFFFF));

    final chargeAlpha = (_fireTimer / _fireInterval * 180).toInt().clamp(0, 180);
    canvas.drawCircle(Offset(cx, cy), 11, Paint()
      ..color = Color.fromARGB(chargeAlpha, 255, 0, 255)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }

  static const _hexBodyColor = [
    Color(0xFF311B92), Color(0xFF455A64), Color(0xFF0D0020),
    Color(0xFF3D0000), Color(0xFF1A0033), Color(0xFF002244),
    Color(0xFF2A1500), Color(0xFF020808), Color(0xFF06000F), Color(0xFF050505),
  ];
  static const _hexOutlineColor = [
    Color(0xFF7C4DFF), Color(0xFF78909C), Color(0xFFCC00FF),
    Color(0xFF880000), Color(0xFF6600CC), Color(0xFF00AAFF),
    Color(0xFFCC7700), Color(0xFF00FFCC), Color(0xFF440088), Color(0xFFAAAAAA),
  ];
  static const _coreColor = [
    Color(0xFFB2FF59), Color(0xFF00E5FF), Color(0xFFFF00FF),
    Color(0xFFFF2200), Color(0xFF9900FF), Color(0xFF00FFFF),
    Color(0xFFFFDD00), Color(0xFF00FFAA), Color(0xFFAA00FF), Color(0xFFFFFFFF),
  ];

  void _renderThemed(Canvas canvas, double cx, double cy, double r, double angle) {
    final p = (game.bossPhase % 10).clamp(0, 9);
    final outlineColor = _hexOutlineColor[p];
    final coreColor = _coreColor[p];

    // Aura
    canvas.drawCircle(Offset(cx, cy), r + 4, Paint()
      ..color = outlineColor.withAlpha(80)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));

    // Hexagon body
    final hex = Path();
    for (int i = 0; i < 6; i++) {
      final a = math.pi / 6 + i * math.pi / 3;
      if (i == 0) hex.moveTo(cx + r * math.cos(a), cy + r * math.sin(a));
      else hex.lineTo(cx + r * math.cos(a), cy + r * math.sin(a));
    }
    hex.close();
    canvas.drawPath(hex, Paint()..color = _hexBodyColor[p]);
    canvas.drawPath(hex, Paint()
      ..color = outlineColor..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // Rotating barrel
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(2, -3, r - 2, 6), const Radius.circular(2)),
      Paint()..color = _hexBodyColor[p].withAlpha(220),
    );
    canvas.drawCircle(Offset(r - 1, 0), 3, Paint()..color = coreColor);
    canvas.restore();

    // Core glow + dot
    canvas.drawCircle(Offset(cx, cy), 7, Paint()
      ..color = coreColor.withAlpha(160)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = coreColor);

    // Charge ring
    final chargeAlpha = (_fireTimer / _fireInterval * 180).toInt().clamp(0, 180);
    final chargeRgb = coreColor;
    canvas.drawCircle(Offset(cx, cy), 11, Paint()
      ..color = chargeRgb.withAlpha(chargeAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
  }
}
