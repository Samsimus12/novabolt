import 'dart:math' as math;

import '../components/player.dart';
import '../components/weapon.dart';
import '../components/weapon_explosive_bolt.dart';
import '../components/weapon_frost_shard.dart';
import '../components/weapon_homing_bolt.dart';
import '../components/weapon_rapid_fire.dart';
import '../components/weapon_spread_shot.dart';
import '../components/weapon_sword_aura.dart';
import '../novabolt_game.dart';

enum UpgradeCategory { weapon, nova, mobility }

abstract class UpgradeCard {
  String get title;
  String get description;
  String get iconLabel;
  UpgradeCategory get category;
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
  UpgradeCategory get category => UpgradeCategory.weapon;
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
  UpgradeCategory get category => UpgradeCategory.weapon;
  @override
  void apply(NovaboltGame game) => game.player.add(factory());
}

class StatBuffCard extends UpgradeCard {
  final String _title;
  final String _description;
  final String _icon;
  final UpgradeCategory _category;
  final void Function(NovaboltGame) _apply;

  StatBuffCard({
    required String title,
    required String description,
    required UpgradeCategory category,
    required void Function(NovaboltGame) apply,
    String icon = '★',
  })  : _title = title,
        _description = description,
        _category = category,
        _icon = icon,
        _apply = apply;

  @override
  String get title => _title;
  @override
  String get description => _description;
  @override
  String get iconLabel => _icon;
  @override
  UpgradeCategory get category => _category;
  @override
  void apply(NovaboltGame game) => _apply(game);
}

List<UpgradeCard> generateUpgradeCards(NovaboltGame game) {
  final rng = math.Random();
  final pool = <UpgradeCard>[];
  final player = game.player;
  final phase = game.bossPhase;

  // Phase-scaled buff values (+5% per boss phase).
  // Integer percentages avoid floating-point display errors (e.g. 1.15-1 = 0.1499…).
  final fireRatePct   = 15 + phase * 5;
  final weaponDmgPct  = 20 + phase * 5;
  final chargePct     = 20 + phase * 5;
  final beamPct       = 20 + phase * 5;
  final novaDmgPct    = 30 + phase * 5;

  final fireRateMult  = 1.0 + fireRatePct / 100.0;
  final weaponDmgMult = 1.0 + weaponDmgPct / 100.0;
  final chargeBonus   = chargePct / 100.0;
  final beamBonus     = beamPct / 100.0;
  final novaDmgBonus  = novaDmgPct / 100.0;

  // --- Weapon category ---

  for (final w in player.activeWeapons) {
    if (w.isUpgradeable && w.upgradeLevel < 10) pool.add(WeaponUpgradeCard(w));
  }

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

  // Rare all-weapon damage buff (~10% chance)
  if (rng.nextDouble() < 0.10) {
    pool.add(StatBuffCard(
      title: 'Targeting Array',
      description: 'All weapons deal +$weaponDmgPct% damage',
      category: UpgradeCategory.weapon,
      apply: (g) {
        for (final w in g.player.activeWeapons) {
          w.damage *= weaponDmgMult;
        }
      },
    ));
  }

  pool.add(StatBuffCard(
    title: 'Overcharge',
    description: 'Fire rate +$fireRatePct% for all weapons',
    category: UpgradeCategory.weapon,
    apply: (g) {
      for (final w in g.player.activeWeapons) {
        w.fireRate *= fireRateMult;
      }
    },
  ));

  // --- Nova category ---

  // Regular nova stat buffs — always in pool
  pool.addAll([
    StatBuffCard(
      title: 'Nova Accelerator',
      description: 'Charge rate +$chargePct% faster',
      category: UpgradeCategory.nova,
      apply: (g) => g.superchargeSystem.chargeMultiplier += chargeBonus,
    ),
    StatBuffCard(
      title: 'Extended Beam',
      description: 'Nova lasts $beamPct% longer',
      category: UpgradeCategory.nova,
      apply: (g) => g.superchargeSystem.depleteMultiplier =
          (g.superchargeSystem.depleteMultiplier - beamBonus).clamp(0.2, 1.0),
    ),
    StatBuffCard(
      title: 'Nova Overload',
      description: 'Nova damage +$novaDmgPct%',
      category: UpgradeCategory.nova,
      icon: '⚡',
      apply: (g) => g.superchargeSystem.damageMultiplier += novaDmgBonus,
    ),
  ]);

  // --- Mobility category ---

  if (player.afterburnerStacks < Player.maxAfterburnerStacks) {
    pool.add(StatBuffCard(
      title: 'Afterburner',
      description: 'Thrust upgrade — move speed +25%',
      category: UpgradeCategory.mobility,
      apply: (g) {
        g.player.moveSpeed *= 1.25;
        g.player.afterburnerStacks++;
      },
    ));
  }

  // Pick one random card from each category, then shuffle the result.
  final byCategory = <UpgradeCategory, List<UpgradeCard>>{};
  for (final card in pool) {
    byCategory.putIfAbsent(card.category, () => []).add(card);
  }

  final picks = <UpgradeCard>[];
  for (final cards in byCategory.values) {
    cards.shuffle(rng);
    picks.add(cards.first);
  }
  picks.shuffle(rng);

  // Guard: pad if pool was tiny (all weapons maxed, no nova, no mobility).
  if (picks.length < 3) {
    final chosen = picks.toSet();
    final leftovers = pool.where((c) => !chosen.contains(c)).toList()..shuffle(rng);
    picks.addAll(leftovers.take(3 - picks.length));
  }

  return picks.take(3).toList();
}

// Rolls 0–2 bonus HP cards (each 20% chance). Caller applies and displays them.
List<StatBuffCard> rollBonusCards(NovaboltGame game) {
  final result = <StatBuffCard>[];
  final rng = math.Random();
  if (rng.nextDouble() < 0.20) {
    result.add(StatBuffCard(
      title: '+25 Hull Plating',
      description: 'Reinforce hull for +25 max HP',
      category: UpgradeCategory.mobility,
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
      category: UpgradeCategory.mobility,
      icon: '♥',
      apply: (g) {
        g.player.currentHp = (g.player.currentHp + 40).clamp(0, g.player.maxHp);
      },
    ));
  }
  return result;
}
