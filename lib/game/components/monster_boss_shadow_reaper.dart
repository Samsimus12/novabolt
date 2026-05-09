import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import 'boss_projectile.dart';
import 'monster_boss.dart';

class MonsterBossShadowReaper extends BossMonster {
  MonsterBossShadowReaper({required super.position, int playerLevel = 1})
      : super(stats: reaperStats.scaled(playerLevel), playerLevel: playerLevel);

  @override
  String get displayName => 'SHADOW REAPER';

  @override
  double get fireInterval => hpFraction > 0.5 ? 1.8 : 0.9;

  @override
  double get projectileDamage => 18.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 2).clamp(3, 9);

  @override
  double get specialAttackInterval => 17.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 20;

  @override
  Color get specialColor => const Color(0xFF6600CC);

  @override
  Color get deathColor => const Color(0xFF440088);

  @override
  void fireSpecialAttack() {
    // Twin streams: forward fan (10 shots) + backward fan (10 shots)
    final dir = game.player.position - position;
    final baseAngle = math.atan2(dir.y, dir.x);
    const halfCount = 10;
    const spread = 0.35;

    // Forward fan
    for (int i = 0; i < halfCount; i++) {
      final offset = (i / (halfCount - 1) - 0.5) * spread * 2;
      final angle = baseAngle + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 360,
        size: 16,
        color: specialColor,
      ));
    }

    // Backward fan
    for (int i = 0; i < halfCount; i++) {
      final offset = (i / (halfCount - 1) - 0.5) * spread * 2;
      final angle = baseAngle + math.pi + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 360,
        size: 16,
        color: specialColor,
      ));
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.shadowReaper;
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

    // Indigo aura glow
    canvas.drawCircle(
      Offset(cx, cy),
      42,
      Paint()
        ..color = const Color(0x445500AA)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Dark tendrils extending from back
    final tendrilPaint = Paint()
      ..color = const Color(0xFF220044)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 4, cy + 28), Offset(cx - 14, cy + 48), tendrilPaint);
    canvas.drawLine(Offset(cx, cy + 28), Offset(cx + 4, cy + 50), tendrilPaint);
    canvas.drawLine(Offset(cx + 6, cy + 26), Offset(cx + 18, cy + 44), tendrilPaint);
    canvas.drawLine(Offset(cx - 10, cy + 24), Offset(cx - 22, cy + 42), tendrilPaint);

    // Large curved blade extending from right side
    final blade = Path()
      ..moveTo(cx + 8, cy - 30)
      ..quadraticBezierTo(cx + 52, cy - 10, cx + 44, cy + 28)
      ..lineTo(cx + 36, cy + 22)
      ..quadraticBezierTo(cx + 42, cy - 6, cx + 12, cy - 22)
      ..close();
    canvas.drawPath(blade, Paint()..color = const Color(0xFF0A0015));
    canvas.drawPath(
      blade,
      Paint()
        ..color = const Color(0xFF5500AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Crescent/scythe main hull (curves to left side)
    final hull = Path()
      ..moveTo(cx, cy - 36)
      ..quadraticBezierTo(cx + 16, cy - 24, cx + 14, cy)
      ..quadraticBezierTo(cx + 10, cy + 18, cx + 2, cy + 28)
      ..lineTo(cx - 8, cy + 24)
      ..quadraticBezierTo(cx - 30, cy + 10, cx - 34, cy - 8)
      ..quadraticBezierTo(cx - 26, cy - 28, cx, cy - 36)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF0A0015));
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF5500AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Glow outline
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0x776600CC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 4 small dark eyes along the curved hull
    final eyePositions = [
      Offset(cx - 16, cy - 20),
      Offset(cx - 24, cy - 6),
      Offset(cx - 28, cy + 8),
      Offset(cx - 20, cy + 20),
    ];
    final eyeGlowPaint = Paint()
      ..color = const Color(0xFF6600CC)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final eyeCorePaint = Paint()..color = const Color(0xFF9922FF);
    for (final e in eyePositions) {
      canvas.drawCircle(e, 4.5, eyeGlowPaint);
      canvas.drawCircle(e, 2.5, eyeCorePaint);
      canvas.drawCircle(e, 1.0, Paint()..color = const Color(0xFFCC88FF));
    }

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
