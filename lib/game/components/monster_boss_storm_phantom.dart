import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import 'boss_projectile.dart';
import 'monster_boss.dart';

class MonsterBossStormPhantom extends BossMonster {
  MonsterBossStormPhantom({required super.position, int playerLevel = 1})
      : super(stats: phantomStats.scaled(playerLevel), playerLevel: playerLevel);

  @override
  String get displayName => 'STORM PHANTOM';

  @override
  double get fireInterval => hpFraction > 0.5 ? 1.6 : 0.8;

  @override
  double get projectileDamage => 14.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 4).clamp(8, 14);

  @override
  double get specialAttackInterval => 16.0;

  @override
  int get maxSpecialAttacks => 3;

  @override
  int get specialBurstCount => 16;

  @override
  Color get specialColor => const Color(0xFF00FFFF);

  @override
  Color get deathColor => const Color(0xFF00CCFF);

  @override
  void fireSpecialAttack() {
    // X-pattern: 4 groups of 4 shots at 90° intervals, each group fans ±0.12 rad
    for (int k = 0; k < 4; k++) {
      for (int j = 0; j < 4; j++) {
        final angle = k * math.pi / 2 + (j - 1.5) * 0.12;
        game.world.add(BossProjectile(
          position: position.clone(),
          direction: Vector2(math.cos(angle), math.sin(angle)),
          damage: projectileDamage * 1.5,
          speed: 420,
          size: 14,
          color: specialColor,
        ));
      }
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.stormPhantom;
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

    // Speed glow behind engines
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 4, cy + 32), width: 22, height: 14),
      Paint()
        ..color = const Color(0xAA00AAFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Left swept-back wing (asymmetric, angular)
    final leftWing = Path()
      ..moveTo(cx - 4, cy - 6)
      ..lineTo(cx - 34, cy - 4)
      ..lineTo(cx - 38, cy + 14)
      ..lineTo(cx - 18, cy + 20)
      ..lineTo(cx - 8, cy + 8)
      ..close();
    // Right swept-back wing (slightly different for asymmetry)
    final rightWing = Path()
      ..moveTo(cx + 4, cy - 8)
      ..lineTo(cx + 30, cy - 14)
      ..lineTo(cx + 36, cy + 8)
      ..lineTo(cx + 16, cy + 16)
      ..lineTo(cx + 6, cy + 6)
      ..close();
    final wingPaint = Paint()..color = const Color(0xFF001122);
    canvas.drawPath(leftWing, wingPaint);
    canvas.drawPath(rightWing, wingPaint);

    // Wing outlines
    canvas.drawPath(
      leftWing,
      Paint()
        ..color = const Color(0xFF00AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      rightWing,
      Paint()
        ..color = const Color(0xFF00AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Left spike tip
    final leftSpike = Path()
      ..moveTo(cx - 34, cy - 4)
      ..lineTo(cx - 46, cy - 16)
      ..lineTo(cx - 36, cy + 4)
      ..close();
    // Right spike tip
    final rightSpike = Path()
      ..moveTo(cx + 30, cy - 14)
      ..lineTo(cx + 44, cy - 24)
      ..lineTo(cx + 34, cy - 6)
      ..close();
    final spikePaint = Paint()..color = const Color(0xFF003344);
    canvas.drawPath(leftSpike, spikePaint);
    canvas.drawPath(rightSpike, spikePaint);

    // Main angular hull (lightning-bolt shaped)
    final hull = Path()
      ..moveTo(cx, cy - 38)
      ..lineTo(cx + 10, cy - 22)
      ..lineTo(cx + 6, cy - 10)
      ..lineTo(cx + 14, cy + 4)
      ..lineTo(cx + 10, cy + 28)
      ..lineTo(cx + 2, cy + 36)
      ..lineTo(cx - 6, cy + 28)
      ..lineTo(cx - 4, cy + 4)
      ..lineTo(cx - 12, cy - 8)
      ..lineTo(cx - 6, cy - 22)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF001122));

    // Hull outline
    canvas.drawPath(
      hull,
      Paint()
        ..color = const Color(0xFF00AAFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Lightning discharge lines on hull surface
    final lightningPaint = Paint()
      ..color = const Color(0xFF00FFFF)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(cx - 8, cy - 18), Offset(cx + 4, cy - 6), lightningPaint);
    canvas.drawLine(Offset(cx + 4, cy - 6), Offset(cx - 4, cy + 2), lightningPaint);
    canvas.drawLine(Offset(cx - 4, cy + 2), Offset(cx + 6, cy + 14), lightningPaint);
    canvas.drawLine(Offset(cx + 6, cy + 14), Offset(cx - 2, cy + 22), lightningPaint);

    // Additional electric accent lines
    canvas.drawLine(Offset(cx - 6, cy - 28), Offset(cx + 8, cy - 20), lightningPaint);

    // Bright cyan cockpit orb at front
    canvas.drawCircle(
      Offset(cx, cy - 30),
      9,
      Paint()
        ..color = const Color(0xFF00CCFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(Offset(cx, cy - 30), 6, Paint()..color = const Color(0xFF00FFFF));
    canvas.drawCircle(Offset(cx, cy - 30), 3, Paint()..color = const Color(0xFFFFFFFF));

    // Engine port
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 4, cy + 32), width: 10, height: 6),
      Paint()..color = const Color(0xFF001122),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 4, cy + 34), width: 7, height: 4),
      Paint()
        ..color = const Color(0xFF0088FF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
