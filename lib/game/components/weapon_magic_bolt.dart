import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../fx/shot_art.dart';
import 'projectile.dart';
import 'weapon.dart';

// ── Weapon ──────────────────────────────────────────────────────────────────

class WeaponMagicBolt extends Weapon {
  WeaponMagicBolt() : super(damage: 15, fireRate: 2.0);

  @override
  String get displayName => 'Laser Bolt';

  @override
  void fire(Vector2 playerPos, Vector2 direction) {
    game.world.add(MagicBolt(
      position: playerPos.clone(),
      direction: direction,
      damage: shotDamage,
      color: evolved ? const Color(0xFFB8F6FF) : const Color(0xFF00E5FF),
      boltSize: evolved ? 13 : 10,
    )..pierce = evolved ? 3 : 0);
  }
}

// ── Projectile ───────────────────────────────────────────────────────────────

class MagicBolt extends Projectile {
  final Color color;

  MagicBolt({
    required super.position,
    required super.direction,
    required super.damage,
    this.color = const Color(0xFF00E5FF),
    super.speed = 300,
    double boltSize = 10,
  }) : super(size: boltSize);

  @override
  void render(Canvas canvas) {
    final c = Offset(size.x / 2, size.y / 2);
    ShotArt.streak(canvas, c, math.atan2(direction.y, direction.x), size.x * 2.0, size.x * 0.32, color);
  }
}
