import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import 'boss_projectile.dart';
import 'monster_boss.dart';

class MonsterBossCosmicBehemoth extends BossMonster {
  MonsterBossCosmicBehemoth({required super.position, int playerLevel = 1})
      : super(stats: behemothStats.scaled(playerLevel), playerLevel: playerLevel);

  @override
  String get displayName => 'COSMIC BEHEMOTH';

  @override
  double get fireInterval => hpFraction > 0.5 ? 2.8 : 1.6;

  @override
  double get projectileDamage => 22.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 3).clamp(5, 11);

  @override
  double get specialAttackInterval => 22.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 32;

  @override
  Color get specialColor => const Color(0xFF4444FF);

  @override
  Color get deathColor => const Color(0xFF0000CC);

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 160,
        size: 28,
        color: specialColor,
      ));
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.cosmicBehemoth;
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

    // Engine glow along underside — multiple soft glows
    for (int i = -3; i <= 3; i++) {
      canvas.drawCircle(
        Offset(cx + i * 16.0, cy + 28),
        10,
        Paint()
          ..color = const Color(0x884466FF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }

    // Main wide oval body (wide, low-profile manta shape)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 120, height: 54),
      Paint()..color = const Color(0xFF000828),
    );

    // Wide outer outline glow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: 120, height: 54),
      Paint()
        ..color = const Color(0xFF2244AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Small fins along left side (4 fins)
    for (int i = 0; i < 4; i++) {
      final fx = cx - 48.0 + i * 14.0;
      final fy = cy + 22.0;
      final fin = Path()
        ..moveTo(fx, fy)
        ..lineTo(fx - 6, fy + 14)
        ..lineTo(fx + 4, fy + 10)
        ..close();
      canvas.drawPath(fin, Paint()..color = const Color(0xFF112255));
      canvas.drawPath(
        fin,
        Paint()
          ..color = const Color(0xFF2244AA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // Small fins along right side (4 fins)
    for (int i = 0; i < 4; i++) {
      final fx = cx + 6.0 + i * 14.0;
      final fy = cy + 22.0;
      final fin = Path()
        ..moveTo(fx, fy)
        ..lineTo(fx + 6, fy + 14)
        ..lineTo(fx - 4, fy + 10)
        ..close();
      canvas.drawPath(fin, Paint()..color = const Color(0xFF112255));
      canvas.drawPath(
        fin,
        Paint()
          ..color = const Color(0xFF2244AA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // Large dark viewport across front with tiny star dots inside
    final viewportRect = Rect.fromCenter(center: Offset(cx, cy - 12), width: 72, height: 18);
    canvas.drawOval(viewportRect, Paint()..color = const Color(0xFF000510));
    canvas.drawOval(
      viewportRect,
      Paint()
        ..color = const Color(0xFF2244AA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Tiny star dots painted inside viewport
    final starPaint = Paint()..color = const Color(0xFF4466FF);
    final starOffsets = [
      Offset(cx - 24, cy - 14),
      Offset(cx - 10, cy - 10),
      Offset(cx + 4, cy - 14),
      Offset(cx + 18, cy - 12),
      Offset(cx - 18, cy - 8),
      Offset(cx + 10, cy - 8),
      Offset(cx + 28, cy - 10),
      Offset(cx - 28, cy - 12),
    ];
    for (final s in starOffsets) {
      canvas.drawCircle(s, 1.2, starPaint);
    }

    // Bioluminescent dots along hull
    final bioGlowPaint = Paint()
      ..color = const Color(0xFF4466FF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final bioDotPaint = Paint()..color = const Color(0xFF6688FF);
    final bioPositions = [
      Offset(cx - 46, cy - 4),
      Offset(cx - 32, cy - 14),
      Offset(cx - 16, cy - 18),
      Offset(cx, cy - 20),
      Offset(cx + 16, cy - 18),
      Offset(cx + 32, cy - 14),
      Offset(cx + 46, cy - 4),
      Offset(cx - 38, cy + 12),
      Offset(cx + 38, cy + 12),
    ];
    for (final p in bioPositions) {
      canvas.drawCircle(p, 4, bioGlowPaint);
      canvas.drawCircle(p, 2.5, bioDotPaint);
    }

    // Multiple engine ports along underside center
    final enginePortPaint = Paint()..color = const Color(0xFF000C28);
    final engineFirePaint = Paint()
      ..color = const Color(0xFF2255CC)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (int i = -4; i <= 4; i++) {
      final ex = cx + i * 12.0;
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 24), width: 8, height: 6), enginePortPaint);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(ex, cy + 26), width: 5, height: 4), engineFirePaint);
    }

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
