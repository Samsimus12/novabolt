import 'dart:math' as math;

import '../components/weapon.dart';
import '../components/weapon_explosive_bolt.dart';
import '../components/weapon_frost_shard.dart';
import '../components/weapon_homing_bolt.dart';
import '../components/weapon_rapid_fire.dart';
import '../components/weapon_spread_shot.dart';
import '../components/weapon_sword_aura.dart';
import '../novabolt_game.dart';

abstract class UpgradeCard {
  String get title;
  String get description;
  String get iconLabel;
  void apply(NovaboltGame game);
}

class WeaponUpgradeCard extends UpgradeCard {
  final Weapon weapon;
  WeaponUpgradeCard(this.weapon);

  @override
  String get title => '${weapon.displayName} Lv${weapon.upgradeLevel + 1}';
  @override
  String get description => weapon.nextUpgradeDescription;
  @override
  String get iconLabel => '⬆';
  @override
  void apply(NovaboltGame game) => weapon.applyUpgrade();
}

class NewWeaponCard extends UpgradeCard {
  final String _title;
  final String _description;
  final Weapon Function() factory;

  NewWeaponCard({
    required String title,
    required String description,
    required this.factory,
  })  : _title = title,
        _description = description;

  @override
  String get title => _title;
  @override
  String get description => _description;
  @override
  String get iconLabel => '✦';
  @override
  void apply(NovaboltGame game) => game.player.add(factory());
}

class StatBuffCard extends UpgradeCard {
  final String _title;
  final String _description;
  final String _icon;
  final void Function(NovaboltGame) _apply;

  StatBuffCard({
    required String title,
    required String description,
    required void Function(NovaboltGame) apply,
    String icon = '★',
  })  : _title = title,
        _description = description,
        _icon = icon,
        _apply = apply;

  @override
  String get title => _title;
  @override
  String get description => _description;
  @override
  String get iconLabel => _icon;
  @override
  void apply(NovaboltGame game) => _apply(game);
}

List<UpgradeCard> generateUpgradeCards(NovaboltGame game) {
  final pool = <UpgradeCard>[];
  final player = game.player;

  // Upgrade existing weapons (up to level 4)
  for (final w in player.activeWeapons) {
    if (w.upgradeLevel < 4) pool.add(WeaponUpgradeCard(w));
  }

  // Unlock new weapons
  if (!player.hasWeapon<WeaponSpreadShot>()) {
    pool.add(NewWeaponCard(
      title: 'Scatter Cannon',
      description: 'Fires 3 laser blasts in a wide arc',
      factory: WeaponSpreadShot.new,
    ));
  }
  if (!player.hasWeapon<WeaponRapidFire>()) {
    pool.add(NewWeaponCard(
      title: 'Pulse Cannon',
      description: '4 pulses/sec at 60% power each',
      factory: WeaponRapidFire.new,
    ));
  }
  if (!player.hasWeapon<WeaponHomingBolt>()) {
    pool.add(NewWeaponCard(
      title: 'Homing Missile',
      description: 'Self-guided missile seeks the nearest target',
      factory: WeaponHomingBolt.new,
    ));
  }
  if (!player.hasWeapon<WeaponSwordAura>()) {
    pool.add(NewWeaponCard(
      title: 'Force Field',
      description: 'Energy ring shreds nearby enemies continuously',
      factory: WeaponSwordAura.new,
    ));
  }
  if (!player.hasWeapon<WeaponExplosiveBolt>()) {
    pool.add(NewWeaponCard(
      title: 'Plasma Rocket',
      description: 'Detonates on impact, blasting all nearby enemies',
      factory: WeaponExplosiveBolt.new,
    ));
  }
  if (!player.hasWeapon<WeaponFrostShard>()) {
    pool.add(NewWeaponCard(
      title: 'EMP Burst',
      description: 'EMP pulse slows targets to 40% speed for 2s',
      factory: WeaponFrostShard.new,
    ));
  }

  // Stat buffs — always available
  final statBuffs = [
    StatBuffCard(
      title: 'Targeting Array',
      description: 'Weapon calibration — all weapons deal 20% more damage',
      apply: (g) {
        for (final w in g.player.activeWeapons) {
          w.damage *= 1.20;
        }
      },
    ),
    StatBuffCard(
      title: 'Afterburner',
      description: 'Thrust upgrade — move speed +25%',
      apply: (g) => g.player.moveSpeed *= 1.25,
    ),
    StatBuffCard(
      title: 'Nova Accelerator',
      description: 'Boost NOVA charge rate — bar fills 25% faster',
      apply: (g) => g.superchargeSystem.chargeMultiplier += 0.20,
    ),
    StatBuffCard(
      title: 'Extended Beam',
      description: 'Reinforce NOVA core — beam lasts 25% longer',
      apply: (g) => g.superchargeSystem.depleteMultiplier =
          (g.superchargeSystem.depleteMultiplier - 0.20).clamp(0.2, 1.0),
    ),
    StatBuffCard(
      title: 'Overcharge',
      description: 'Overclock all weapon systems — fire rate +15%',
      apply: (g) {
        for (final w in g.player.activeWeapons) {
          w.fireRate *= 1.15;
        }
      },
    ),
  ];

  pool.addAll(statBuffs);
  pool.shuffle(math.Random());

  // Ensure we always return exactly 3 unique cards
  return pool.take(3).toList();
}

// Rolls 0–2 bonus HP cards (each ~40% chance). Caller applies and displays them.
List<StatBuffCard> rollBonusCards(NovaboltGame game) {
  final result = <StatBuffCard>[];
  final rng = math.Random();
  if (rng.nextDouble() < 0.20) {
    result.add(StatBuffCard(
      title: '+25 Hull Plating',
      description: 'Reinforce hull for +25 max HP',
      icon: '♥',
      apply: (g) {
        g.player.maxHp += 25;
        g.player.currentHp = (g.player.currentHp + 25).clamp(0, g.player.maxHp);
      },
    ));
  }
  if (rng.nextDouble() < 0.20) {
    result.add(StatBuffCard(
      title: 'Repair Drones',
      description: 'Emergency repair restores 40 HP',
      icon: '♥',
      apply: (g) {
        g.player.currentHp = (g.player.currentHp + 40).clamp(0, g.player.maxHp);
      },
    ));
  }
  return result;
}
