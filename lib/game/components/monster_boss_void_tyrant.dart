import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import 'boss_projectile.dart';
import 'monster_boss.dart';

class MonsterBossVoidTyrant extends BossMonster {
  MonsterBossVoidTyrant({required super.position, int playerLevel = 1})
      : super(stats: tyrantStats.scaled(playerLevel));

  @override
  String get displayName => 'VOID TYRANT';

  @override
  double get fireInterval => hpFraction > 0.4 ? 1.8 : 0.9;

  @override
  double get projectileDamage => 18.0;

  @override
  Color get deathColor => const Color(0xFFCC0000);

  @override
  void fireAtPlayer() {
    final dir = game.player.position - position;
    if (dir.length < 1) return;
    final baseAngle = math.atan2(dir.y, dir.x);
    const spread = 0.35;
    for (final offset in [-spread, 0.0, spread]) {
      final angle = baseAngle + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage,
      ));
    }
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

    // Engine exhaust glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 48), width: 56, height: 30),
      Paint()
        ..color = const Color(0xAACC0000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Outer swept wings
    final leftWing = Path()
      ..moveTo(cx - 10, cy - 10)
      ..lineTo(cx - 54, cy + 10)
      ..lineTo(cx - 52, cy + 32)
      ..lineTo(cx - 24, cy + 26)
      ..lineTo(cx - 14, cy + 12)
      ..close();
    final rightWing = Path()
      ..moveTo(cx + 10, cy - 10)
      ..lineTo(cx + 54, cy + 10)
      ..lineTo(cx + 52, cy + 32)
      ..lineTo(cx + 24, cy + 26)
      ..lineTo(cx + 14, cy + 12)
      ..close();
    final wingPaint = Paint()..color = const Color(0xFF550000);
    canvas.drawPath(leftWing, wingPaint);
    canvas.drawPath(rightWing, wingPaint);

    // Wing weapon pods
    final podPaint = Paint()..color = const Color(0xFF330000);
    canvas.drawRect(Rect.fromLTWH(cx - 57, cy + 8, 10, 16), podPaint);
    canvas.drawRect(Rect.fromLTWH(cx + 47, cy + 8, 10, 16), podPaint);

    // Wing gun barrel tips
    final barrelPaint = Paint()..color = const Color(0xFF880000);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx - 52, cy + 2), width: 5, height: 12), barrelPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx + 52, cy + 2), width: 5, height: 12), barrelPaint);
    canvas.drawCircle(Offset(cx - 52, cy - 4), 3, Paint()..color = const Color(0xFFFF0000));
    canvas.drawCircle(Offset(cx + 52, cy - 4), 3, Paint()..color = const Color(0xFFFF0000));

    // Secondary forward swept fins
    final leftFin = Path()
      ..moveTo(cx - 8, cy - 14)
      ..lineTo(cx - 30, cy + 2)
      ..lineTo(cx - 28, cy + 16)
      ..lineTo(cx - 12, cy + 10)
      ..close();
    final rightFin = Path()
      ..moveTo(cx + 8, cy - 14)
      ..lineTo(cx + 30, cy + 2)
      ..lineTo(cx + 28, cy + 16)
      ..lineTo(cx + 12, cy + 10)
      ..close();
    canvas.drawPath(leftFin, Paint()..color = const Color(0xFF660000));
    canvas.drawPath(rightFin, Paint()..color = const Color(0xFF660000));

    // Main hull
    final hull = Path()
      ..moveTo(cx, cy - 52)
      ..lineTo(cx + 20, cy - 30)
      ..lineTo(cx + 24, cy - 8)
      ..lineTo(cx + 22, cy + 28)
      ..lineTo(cx + 12, cy + 44)
      ..lineTo(cx - 12, cy + 44)
      ..lineTo(cx - 22, cy + 28)
      ..lineTo(cx - 24, cy - 8)
      ..lineTo(cx - 20, cy - 30)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF660000));

    // Armour panels
    final armorPaint = Paint()..color = const Color(0xFF880000);
    final leftPanel = Path()
      ..moveTo(cx - 18, cy - 26)
      ..lineTo(cx - 5, cy - 34)
      ..lineTo(cx - 5, cy + 10)
      ..lineTo(cx - 18, cy + 6)
      ..close();
    final rightPanel = Path()
      ..moveTo(cx + 18, cy - 26)
      ..lineTo(cx + 5, cy - 34)
      ..lineTo(cx + 5, cy + 10)
      ..lineTo(cx + 18, cy + 6)
      ..close();
    canvas.drawPath(leftPanel, armorPaint);
    canvas.drawPath(rightPanel, armorPaint);

    // Hull outline glow
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFFFF2222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Triple forward cannon barrels
    final gunPaint = Paint()..color = const Color(0xFF330000);
    for (final dx in [-10.0, 0.0, 10.0]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(cx + dx, cy - 47), width: 5, height: 14),
        gunPaint,
      );
    }
    for (final dx in [-10.0, 0.0, 10.0]) {
      canvas.drawCircle(Offset(cx + dx, cy - 54), 3, Paint()..color = const Color(0xFFFF0000));
    }

    // Bridge dome
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 16), width: 26, height: 22),
      Paint()..color = const Color(0xFF440000),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 16), width: 16, height: 9),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 16), width: 8, height: 5),
      Paint()..color = const Color(0xFFFF6666),
    );

    // Engine bank
    final enginePortPaint = Paint()..color = const Color(0xFF1A0000);
    final engineFirePaint = Paint()..color = const Color(0xFFFF2200);
    for (int i = -3; i <= 3; i++) {
      final ex = cx + i * 9.0;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 42), width: 10, height: 7), enginePortPaint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 44), width: 7, height: 5), engineFirePaint);
    }

    canvas.restore();

    renderFlash(canvas);
  }
}
