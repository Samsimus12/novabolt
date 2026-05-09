import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import 'boss_projectile.dart';
import 'monster_boss.dart';

class MonsterBossSolarTitan extends BossMonster {
  MonsterBossSolarTitan({required super.position, int playerLevel = 1})
      : super(stats: solarTitanStats.scaled(playerLevel), playerLevel: playerLevel);

  @override
  String get displayName => 'SOLAR TITAN';

  @override
  double get fireInterval => hpFraction > 0.5 ? 2.0 : 1.0;

  @override
  double get projectileDamage => 19.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 4).clamp(7, 13);

  @override
  double get specialAttackInterval => 19.0;

  @override
  int get maxSpecialAttacks => 2;

  @override
  int get specialBurstCount => 24;

  @override
  Color get specialColor => const Color(0xFFFFAA00);

  @override
  Color get deathColor => const Color(0xFFFF8800);

  @override
  void fireSpecialAttack() {
    // Two alternating rings: inner ring (12 shots) then outer ring (12 shots offset)
    // Inner ring
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 280,
        size: 18,
        color: specialColor,
      ));
    }
    // Outer ring (offset by half step)
    for (int i = 0; i < 12; i++) {
      final angle = ((i + 0.5) / 12) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 380,
        size: 16,
        color: specialColor,
      ));
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.solarTitan;
    super.onDie();
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Solar Titan is a fortification — it rotates slowly around its center
    // rather than pointing at the player. Use a time-based or constant rotation.
    final dir = game.player.position - position;
    final angle = math.atan2(dir.y, dir.x) + math.pi / 2;

    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(angle);
    canvas.translate(-cx, -cy);

    // Outer solar corona glow
    canvas.drawCircle(
      Offset(cx, cy),
      48,
      Paint()
        ..color = const Color(0x66FF8800)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // 8 triangular solar spike fins radiating outward
    const spikeCount = 8;
    final spikePaint = Paint()..color = const Color(0xFF884400);
    final spikeOutlinePaint = Paint()
      ..color = const Color(0xFFFFAA00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < spikeCount; i++) {
      final spikeAngle = (i / spikeCount) * math.pi * 2;
      final innerR = 28.0;
      final outerR = 52.0;
      final halfWidth = 0.22; // half-angle of spike base in radians

      final tip = Offset(
        cx + math.cos(spikeAngle) * outerR,
        cy + math.sin(spikeAngle) * outerR,
      );
      final baseLeft = Offset(
        cx + math.cos(spikeAngle - halfWidth) * innerR,
        cy + math.sin(spikeAngle - halfWidth) * innerR,
      );
      final baseRight = Offset(
        cx + math.cos(spikeAngle + halfWidth) * innerR,
        cy + math.sin(spikeAngle + halfWidth) * innerR,
      );

      final spikePath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(baseLeft.dx, baseLeft.dy)
        ..lineTo(baseRight.dx, baseRight.dy)
        ..close();

      canvas.drawPath(spikePath, spikePaint);
      canvas.drawPath(spikePath, spikeOutlinePaint);
    }

    // Central disc body
    canvas.drawCircle(Offset(cx, cy), 30, Paint()..color = const Color(0xFF331100));
    // Disc outline
    canvas.drawCircle(
      Offset(cx, cy),
      30,
      Paint()
        ..color = const Color(0xFFFFAA00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Inner ring detail
    canvas.drawCircle(
      Offset(cx, cy),
      22,
      Paint()
        ..color = const Color(0xFF441500)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Cannon ports between spikes (8 ports, positioned between spikes)
    final cannonPaint = Paint()..color = const Color(0xFF220800);
    final cannonGlowPaint = Paint()
      ..color = const Color(0xFFFF6600)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (int i = 0; i < spikeCount; i++) {
      final portAngle = ((i + 0.5) / spikeCount) * math.pi * 2;
      final portR = 24.0;
      final px = cx + math.cos(portAngle) * portR;
      final py = cy + math.sin(portAngle) * portR;
      canvas.drawCircle(Offset(px, py), 4, cannonPaint);
      canvas.drawCircle(Offset(px, py), 3, cannonGlowPaint);
    }

    // Glowing orange core circle
    canvas.drawCircle(
      Offset(cx, cy),
      14,
      Paint()
        ..color = const Color(0xFFFF6600)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(Offset(cx, cy), 10, Paint()..color = const Color(0xFFFF6600));
    // Bright inner core
    canvas.drawCircle(Offset(cx, cy), 5, Paint()..color = const Color(0xFFFFCC66));
    canvas.drawCircle(Offset(cx, cy), 2.5, Paint()..color = const Color(0xFFFFFFAA));

    canvas.restore();

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
