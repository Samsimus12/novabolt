import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import 'boss_projectile.dart';
import 'monster_boss.dart';

class MonsterBossVoidEmperor extends BossMonster {
  MonsterBossVoidEmperor({required super.position, int playerLevel = 1})
      : super(stats: emperorStats.scaled(playerLevel), playerLevel: playerLevel);

  @override
  String get displayName => 'VOID EMPEROR';

  @override
  double get fireInterval => hpFraction > 0.5 ? 1.6 : 0.7;

  @override
  double get projectileDamage => 21.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 4).clamp(5, 11);

  @override
  double get specialAttackInterval => 16.0;

  @override
  int get maxSpecialAttacks => 3;

  @override
  int get specialBurstCount => 28;

  @override
  Color get specialColor => const Color(0xFF8800CC);

  @override
  Color get deathColor => const Color(0xFF660099);

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 500,
        size: 14,
        color: specialColor,
      ));
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.voidEmperor;
    super.onDie();
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;

    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x) + math.pi / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    // Void aura glow
    canvas.drawCircle(
      Offset(cx, cy),
      50,
      Paint()
        ..color = const Color(0x338800CC)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Void corruption tendrils along edges
    final tendrilPaint = Paint()
      ..color = const Color(0xFF330066)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final tendrilPositions = [
      [Offset(cx - 40, cy - 10), Offset(cx - 54, cy - 20)],
      [Offset(cx - 42, cy + 10), Offset(cx - 56, cy + 22)],
      [Offset(cx + 40, cy - 10), Offset(cx + 54, cy - 20)],
      [Offset(cx + 42, cy + 10), Offset(cx + 56, cy + 22)],
      [Offset(cx - 10, cy + 44), Offset(cx - 18, cy + 58)],
      [Offset(cx + 10, cy + 44), Offset(cx + 18, cy + 58)],
    ];
    for (final t in tendrilPositions) {
      canvas.drawLine(t[0], t[1], tendrilPaint);
    }

    // Wide diamond / rhombus main hull
    final hull = Path()
      ..moveTo(cx, cy - 50)         // top
      ..lineTo(cx + 46, cy)         // right
      ..lineTo(cx, cy + 50)         // bottom
      ..lineTo(cx - 46, cy)         // left
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF110022));

    // Hull outline glow
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF8800CC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0x668800CC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Ornate symmetrical hull panels
    final innerDiamond = Path()
      ..moveTo(cx, cy - 34)
      ..lineTo(cx + 30, cy)
      ..lineTo(cx, cy + 34)
      ..lineTo(cx - 30, cy)
      ..close();
    canvas.drawPath(
      innerDiamond,
      Paint()
        ..color = const Color(0xFF1A0033)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Crown spikes along top edge (5 spikes)
    final crownPaint = Paint()..color = const Color(0xFFAA00FF);
    final crownOutlinePaint = Paint()
      ..color = const Color(0xFFCC44FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Crown spike positions distributed across top quarter of diamond
    final crownSpikes = [
      // [base-left-x, base-left-y, base-right-x, base-right-y, tip-x, tip-y]
      [-16.0, -36.0, -8.0, -44.0, -12.0, -54.0],
      [-6.0, -44.0, 0.0, -48.0, -3.0, -58.0],
      [0.0, -48.0, 6.0, -44.0, 3.0, -60.0],  // center (tallest)
      [8.0, -44.0, 16.0, -36.0, 12.0, -54.0],
      [16.0, -34.0, 22.0, -26.0, 20.0, -46.0],
    ];
    for (final s in crownSpikes) {
      final spike = Path()
        ..moveTo(cx + s[0], cy + s[1])
        ..lineTo(cx + s[2], cy + s[3])
        ..lineTo(cx + s[4], cy + s[5])
        ..close();
      canvas.drawPath(spike, crownPaint);
      canvas.drawPath(spike, crownOutlinePaint);
    }

    // Panel detail lines
    canvas.drawLine(
      Offset(cx - 22, cy - 6),
      Offset(cx + 22, cy - 6),
      Paint()
        ..color = const Color(0xFF440088)
        ..strokeWidth = 1.0,
    );
    canvas.drawLine(
      Offset(cx - 18, cy + 8),
      Offset(cx + 18, cy + 8),
      Paint()
        ..color = const Color(0xFF440088)
        ..strokeWidth = 1.0,
    );

    // Three glowing eyes in a triangle on the bridge
    final eyePositions = [
      Offset(cx, cy - 20),          // top eye
      Offset(cx - 12, cy - 6),      // bottom-left eye
      Offset(cx + 12, cy - 6),      // bottom-right eye
    ];
    final eyeGlowPaint = Paint()
      ..color = const Color(0xFF8800CC)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final eyeCorePaint = Paint()..color = const Color(0xFFBB44FF);
    final eyePupilPaint = Paint()..color = const Color(0xFFFFBBFF);
    for (final e in eyePositions) {
      canvas.drawCircle(e, 5.5, eyeGlowPaint);
      canvas.drawCircle(e, 4, eyeCorePaint);
      canvas.drawCircle(e, 1.8, eyePupilPaint);
    }

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
