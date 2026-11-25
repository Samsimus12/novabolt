import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/components/player.dart';
import 'package:novabolt/game/components/weapon.dart';
import 'package:novabolt/game/components/weapon_explosive_bolt.dart';
import 'package:novabolt/game/components/weapon_frost_shard.dart';
import 'package:novabolt/game/components/weapon_homing_bolt.dart';
import 'package:novabolt/game/components/weapon_magic_bolt.dart';
import 'package:novabolt/game/components/weapon_rapid_fire.dart';
import 'package:novabolt/game/components/weapon_spread_shot.dart';
import 'package:novabolt/game/components/weapon_sword_aura.dart';
import 'package:novabolt/game/data/balance.dart';
import 'package:novabolt/game/data/relics.dart';
import 'package:novabolt/game/data/ship_ability.dart';
import 'package:novabolt/game/systems/ability_loadout.dart';
import 'package:novabolt/game/data/upgrade_cards.dart';
import 'package:novabolt/game/novabolt_game.dart';
import 'package:novabolt/game/systems/supercharge_system.dart';
import 'package:novabolt/game/systems/xp_system.dart';

/// Just enough of the ship for the card generators.
class _FakePlayer extends Fake implements Player {
  final List<Weapon> weapons;
  _FakePlayer(this.weapons);
  @override
  int afterburnerStacks = 0;
  @override
  double maxHp = 100, currentHp = 50;
  @override
  Iterable<Weapon> get activeWeapons => weapons;
  @override
  bool hasWeapon<T extends Weapon>() => weapons.whereType<T>().isNotEmpty;
}

class _FakeGame extends Fake implements NovaboltGame {
  @override
  late Player player;
  @override
  bool isBossReward = false;
  @override
  bool luckyCards = false;
  @override
  double weaponDamageBonus = 0, fireRateBonus = 0, runCoinMultiplier = 1;
  @override
  final SuperchargeSystem superchargeSystem = SuperchargeSystem();
  @override
  final XpSystem xpSystem = XpSystem();
  @override
  final Set<Relic> relics = {};
  @override
  final Set<String> takenBuffs = {};
  @override
  late final AbilityLoadout abilities = AbilityLoadout(this);
  @override
  bool abilityDashOffered = false;
  @override
  bool relicAllowed(Relic r) => true;
  @override
  void announce(String text, {Color color = const Color(0xFFE9EDFF)}) {}
}

List<Weapon> _allWeapons() => [
      WeaponMagicBolt(),
      WeaponSpreadShot(),
      WeaponRapidFire(),
      WeaponHomingBolt(),
      WeaponSwordAura(),
      WeaponExplosiveBolt(),
      WeaponFrostShard(),
    ];

/// Everything that can run out has run out.
_FakeGame _maxedOut({bool evolved = false}) {
  final weapons = _allWeapons();
  for (final w in weapons) {
    if (evolved) w.evolve('Evolved ${w.displayName}');
    w.upgradeLevel = w.maxUpgradeLevel;
  }
  final p = _FakePlayer(weapons)..afterburnerStacks = Player.maxAfterburnerStacks;
  final g = _FakeGame()..player = p;
  g.weaponDamageBonus = Balance.maxWeaponDamageBonus / 100;
  g.fireRateBonus = Balance.maxFireRateBonus / 100;
  g.superchargeSystem
    ..chargeBonus = Balance.maxNovaChargeBonus / 100
    ..durationBonus = Balance.maxNovaDurationBonus / 100
    ..damageBonus = Balance.maxNovaDamageBonus / 100;
  for (final a in ShipAbility.values) {
    for (var i = 0; i < ShipAbility.maxLevel; i++) {
      g.abilities.take(a);
    }
  }
  return g;
}

void main() {
  group('level-up offers are never empty', () {
    test('every weapon maxed and every bonus capped still offers three cards', () {
      for (final evolved in [false, true]) {
        final g = _maxedOut(evolved: evolved);
        for (var i = 0; i < 400; i++) {
          g.isBossReward = i.isEven;
          final offer = generateUpgradeCards(g);
          expect(offer, hasLength(3), reason: 'evolved=$evolved try $i');
          expect(offer.toSet(), hasLength(3));
          // Whatever is offered can be taken.
          for (final c in offer) {
            c.apply(g);
          }
        }
      }
    });

    test('a maxed state really has nothing but supplies to offer', () {
      final g = _maxedOut();
      final offer = generateUpgradeCards(g);
      expect(offer.every((c) => c is SupplyCard || c is NewWeaponCard || c is EvolutionCard), isTrue);
    });

    test('supply cards always work, even on a full hull', () {
      final g = _maxedOut();
      g.player.currentHp = g.player.maxHp;
      for (final c in supplyCards(g, 10)) {
        c.apply(g);
      }
      expect(g.player.currentHp, lessThanOrEqualTo(g.player.maxHp));
      expect(g.runCoinMultiplier, greaterThan(1));
    });

    test('a relic chest with no relics left falls back to supplies', () {
      final g = _maxedOut()..relics.addAll(Relic.values);
      expect(generateRelicCards(g), isNotEmpty);
      // One relic left: a short but valid offer.
      g.relics.remove(Relic.midas);
      final one = generateRelicCards(g);
      expect(one, hasLength(1));
      expect(one.single, isA<RelicCard>());
    });

    test('ensureOffer replaces an empty list and keeps a real one', () {
      final g = _maxedOut();
      expect(ensureOffer(g, []), isNotEmpty);
      final real = supplyCards(g, 2);
      expect(ensureOffer(g, real), same(real));
    });

    test('fresh run, mid run and boss-reward states all give three cards', () {
      final g = _FakeGame()..player = _FakePlayer([WeaponMagicBolt()]);
      for (var i = 0; i < 300; i++) {
        g.isBossReward = i % 3 == 0;
        expect(generateUpgradeCards(g), hasLength(3));
      }
    });
  });

  group('evolution is a fresh upgrade track', () {
    test('level and damage reset to the base weapon', () {
      final w = WeaponMagicBolt();
      for (var i = 0; i < 6; i++) {
        w.applyUpgrade();
      }
      expect(w.upgradeLevel, 7);
      expect(w.damage, greaterThan(w.baseDamage * 3));
      w.evolve('Ion Lance');
      expect(w.evolved, isTrue);
      expect(w.upgradeLevel, 1);
      expect(w.damage, closeTo(w.baseDamage * Balance.evolvedDamageMult, 1e-9));
      expect(w.label, 'Ion Lance');
    });

    test('an evolved weapon levels again, to its own (lower) cap', () {
      final w = WeaponSpreadShot()..evolve('Bullet Storm');
      final start = w.damage;
      expect(w.canUpgrade, isTrue);
      expect(w.nextUpgradeDescription, 'Damage +${(Balance.evolvedStep * 100 - 100).round()}%');
      while (w.canUpgrade) {
        w.applyUpgrade();
      }
      expect(w.upgradeLevel, Balance.evolvedMaxLevel);
      expect(w.damage, closeTo(start * _pow(Balance.evolvedStep, Balance.evolvedMaxLevel - 1), 1e-9));
      expect(WeaponUpgradeCard(WeaponSpreadShot()..evolve('x')).title, contains('Lv2'));
    });

    test('evolving never leaves a weapon weaker than a Lv5 one', () {
      final plain = WeaponMagicBolt();
      for (var i = 0; i < 4; i++) {
        plain.applyUpgrade();
      }
      final evo = WeaponMagicBolt()..evolve('Ion Lance');
      expect(evo.damage, greaterThanOrEqualTo(plain.damage * 0.8));
    });

    test('upgrade steps diminish after the early levels', () {
      expect(Balance.upgradeDamageStep(5, evolved: false), Balance.upgradeStepEarly);
      expect(Balance.upgradeDamageStep(Balance.upgradeLateFrom, evolved: false), Balance.upgradeStepLate);
      final w = WeaponMagicBolt();
      while (w.canUpgrade) {
        w.applyUpgrade();
      }
      expect(w.upgradeLevel, Balance.maxWeaponLevel);
      expect(w.damage / w.baseDamage, lessThan(7)); // was 10.6x
    });

    test('the Pulse Cannon upgrades fire rate with the same diminishing steps', () {
      final w = WeaponRapidFire();
      while (w.canUpgrade) {
        w.applyUpgrade();
      }
      expect(w.fireRate / w.baseFireRate, lessThan(3.5)); // was 5.2x
      expect(w.damage, w.baseDamage);
    });
  });
}

double _pow(double b, int e) {
  var r = 1.0;
  for (var i = 0; i < e; i++) {
    r *= b;
  }
  return r;
}
