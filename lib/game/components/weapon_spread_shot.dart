import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import 'weapon.dart';
import 'weapon_magic_bolt.dart';

class WeaponSpreadShot extends Weapon {
  WeaponSpreadShot() : super(damage: 10, fireRate: 1.5);

  @override
  String get displayName => 'Scatter Cannon';

  @override
  void fire(Vector2 playerPos, Vector2 direction) {
    final angles = evolved ? const [-0.52, -0.26, 0.0, 0.26, 0.52] : const [-0.35, 0.0, 0.35];
    for (final angle in angles) {
      game.world.add(MagicBolt(
        position: playerPos.clone(),
        direction: _rotate(direction, angle),
        damage: shotDamage,
        color: const Color(0xFFF4A800),
        boltSize: 8,
      ));
    }
  }

  Vector2 _rotate(Vector2 v, double rad) {
    final c = math.cos(rad);
    final s = math.sin(rad);
    return Vector2(v.x * c - v.y * s, v.x * s + v.y * c);
  }
}
