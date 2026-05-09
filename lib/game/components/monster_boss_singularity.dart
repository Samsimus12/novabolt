import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import '../data/nova_mode.dart';
import 'boss_projectile.dart';
import 'monster_boss.dart';

class MonsterBossSingularity extends BossMonster {
  MonsterBossSingularity({required super.position, int playerLevel = 1})
      : super(stats: singularityStats.scaled(playerLevel), playerLevel: playerLevel);

  @override
  String get displayName => 'THE SINGULARITY';

  @override
  double get fireInterval => hpFraction > 0.5 ? 1.4 : 0.6;

  @override
  double get projectileDamage => 25.0;

  @override
  int get shotCount => (playerLevel ~/ 10 + 8).clamp(12, 20);

  @override
  double get specialAttackInterval => 14.0;

  @override
  int get maxSpecialAttacks => 3;

  @override
  int get specialBurstCount => 40;

  @override
  Color get specialColor => const Color(0xFFFFFFFF);

  @override
  Color get deathColor => const Color(0xFFFFFFFF);

  /// Singularity fires full 360° radial — ignores player direction.
  @override
  void fireAtPlayer() {
    final count = shotCount;
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage,
      ));
    }
  }

  @override
  void fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 300,
        size: 20,
        color: const Color(0xFFFFFFFF),
      ));
    }
  }

  @override
  void onDie() {
    game.pendingInheritMode = NovaMode.singularity;
    super.onDie();
  }

  @override
  void render(Canvas canvas) {
    if (isDead) return;
    final cx = size.x / 2;
    final cy = size.y / 2;

    // Singularity doesn't orient toward player — it is a black hole.
    // No rotation transform needed.

    // Outer gravitational lensing distortion glow
    canvas.drawCircle(
      Offset(cx, cy),
      64,
      Paint()
        ..color = const Color(0x22FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
    );

    // Accretion disk — wide ellipse at slight angle, semi-transparent white
    final accretionRect = Rect.fromCenter(
      center: Offset(cx, cy + 4),
      width: 120,
      height: 28,
    );
    canvas.save();
    canvas.translate(cx, cy + 4);
    canvas.rotate(0.18); // slight tilt
    canvas.translate(-cx, -(cy + 4));
    canvas.drawOval(
      accretionRect,
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      accretionRect,
      Paint()
        ..color = const Color(0x33DDDDFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();

    // Event horizon ring (outer white glow stroke)
    canvas.drawCircle(
      Offset(cx, cy),
      46,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      Offset(cx, cy),
      46,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Gravitational lensing inner ring (slightly lighter just inside event horizon)
    canvas.drawCircle(
      Offset(cx, cy),
      40,
      Paint()
        ..color = const Color(0x44FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Perfect black event horizon filled circle
    canvas.drawCircle(Offset(cx, cy), 44, Paint()..color = const Color(0xFF000000));

    // Intense white core at center
    canvas.drawCircle(
      Offset(cx, cy),
      8,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = const Color(0xFFFFFFFF));
    // Innermost bright point
    canvas.drawCircle(Offset(cx, cy), 2, Paint()..color = const Color(0xFFFFFFFF));

    renderChargeEffect(canvas, cx, cy);
    renderFlash(canvas);
  }
}
