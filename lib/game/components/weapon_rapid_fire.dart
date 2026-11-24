import 'dart:ui';

import 'package:flame/components.dart';

import '../data/balance.dart';
import 'weapon.dart';
import 'weapon_magic_bolt.dart';

class WeaponRapidFire extends Weapon {
  WeaponRapidFire() : super(damage: 9, fireRate: 4.0);

  @override
  String get displayName => 'Pulse Cannon';

  @override
  String get nextUpgradeDescription =>
      'Fire rate +${((Balance.upgradeRateStep(upgradeLevel + 1, evolved: evolved) - 1) * 100).round()}%';

  @override
  void applyUpgrade() {
    upgradeLevel++;
    fireRate *= Balance.upgradeRateStep(upgradeLevel, evolved: evolved);
  }

  @override
  void fire(Vector2 playerPos, Vector2 direction) {
    game.world.add(MagicBolt(
      position: playerPos.clone(),
      direction: direction,
      damage: shotDamage,
      color: const Color(0xFFFF6B35),
      speed: 350,
      boltSize: 7,
    ));
  }
}
