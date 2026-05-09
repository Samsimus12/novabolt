import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../data/monster_data.dart';
import 'boss_projectile.dart';
import 'monster.dart';

abstract class BossMonster extends Monster {
  final int playerLevel;

  double _fireTimer = 0;
  double _specialTimer = 0;
  int _specialAttacksUsed = 0;
  double _chargeTimer = -1;

  static const double _chargeDuration = 0.8;

  // Shots fired per normal attack volley — scales with playerLevel.
  int get shotCount;

  // Seconds between special attacks.
  double get specialAttackInterval;

  // How many times the special can fire per fight.
  int get maxSpecialAttacks;

  // Projectiles in the special radial burst.
  int get specialBurstCount;

  // Colour of the special burst projectiles.
  Color get specialColor;

  double get fireInterval;
  double get projectileDamage;
  String get displayName;

  BossMonster({
    required super.position,
    required MonsterStats stats,
    this.playerLevel = 1,
  }) : super(stats: stats);

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;

    // Normal fire
    _fireTimer += dt;
    if (_fireTimer >= fireInterval) {
      _fireTimer = 0;
      fireAtPlayer();
    }

    // Special attack — charge-up then burst
    if (_specialAttacksUsed < maxSpecialAttacks) {
      _specialTimer += dt;
      final nextTriggerAt = specialAttackInterval * (_specialAttacksUsed + 1);

      if (_chargeTimer < 0 && _specialTimer >= nextTriggerAt - _chargeDuration) {
        _chargeTimer = 0;
      }

      if (_chargeTimer >= 0) {
        _chargeTimer += dt;
        if (_chargeTimer >= _chargeDuration) {
          _chargeTimer = -1;
          _specialAttacksUsed++;
          _fireSpecialAttack();
        }
      }
    }
  }

  // Progress 0→1 while charging; -1 (negative) when idle.
  double get chargeProgress =>
      _chargeTimer < 0 ? -1.0 : (_chargeTimer / _chargeDuration).clamp(0.0, 1.0);

  void fireAtPlayer() {
    final dir = game.player.position - position;
    if (dir.length < 1) return;
    final baseAngle = math.atan2(dir.y, dir.x);
    final count = shotCount;
    const spreadPerShot = 0.2; // radians between adjacent shots
    final totalArc = (count - 1) * spreadPerShot;
    for (int i = 0; i < count; i++) {
      final offset = count > 1 ? (i / (count - 1) - 0.5) * totalArc : 0.0;
      final angle = baseAngle + offset;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage,
      ));
    }
  }

  void _fireSpecialAttack() {
    for (int i = 0; i < specialBurstCount; i++) {
      final angle = (i / specialBurstCount) * math.pi * 2;
      game.world.add(BossProjectile(
        position: position.clone(),
        direction: Vector2(math.cos(angle), math.sin(angle)),
        damage: projectileDamage * 1.5,
        speed: 380,
        size: 18,
        color: specialColor,
      ));
    }
  }

  // Call this inside each boss's render(), before renderFlash().
  void renderChargeEffect(Canvas canvas, double cx, double cy) {
    final progress = chargeProgress;
    if (progress < 0) return;
    final radius = size.x / 2 + progress * size.x * 0.8;
    final alpha = ((1 - progress) * 220).toInt();
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..color = specialColor.withAlpha(alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0 - progress * 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
  }

  @override
  void onDie() {
    game.onBossKilled();
  }
}
