import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/components/player.dart';
import 'package:novabolt/game/components/weapon_magic_bolt.dart';
import 'package:novabolt/game/components/weapon.dart';
import 'package:novabolt/game/data/ability_stats.dart';
import 'package:novabolt/game/data/relics.dart';
import 'package:novabolt/game/data/ship_ability.dart';
import 'package:novabolt/game/data/ship_class.dart';
import 'package:novabolt/game/data/upgrade_cards.dart';
import 'package:novabolt/game/novabolt_game.dart';
import 'package:novabolt/game/systems/ability_loadout.dart';
import 'package:novabolt/game/systems/supercharge_system.dart';
import 'package:novabolt/game/systems/xp_system.dart';

class _Player extends Fake implements Player {
  double dash = 0;
  @override
  bool get isMounted => true;
  @override
  double get dashCooldown => dash;
  @override
  set dashCooldown(double v) => dash = v;
  @override
  bool tryDash() {
    if (dash > 0) return false;
    dash = 2.2;
    return true;
  }

  @override
  int afterburnerStacks = 0;
  @override
  double maxHp = 100, currentHp = 50;
  @override
  Iterable<Weapon> get activeWeapons => [WeaponMagicBolt()];
  @override
  bool hasWeapon<T extends Weapon>() => T == WeaponMagicBolt;
}

class _Game extends Fake implements NovaboltGame {
  @override
  late Player player = _Player();
  @override
  bool paused = false;
  @override
  bool isGameOver = false;
  @override
  ShipClass shipClass = ShipClass.vanguard;
  @override
  late final AbilityLoadout abilities = AbilityLoadout(this);
  @override
  bool abilityDashOffered = false;
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
  bool relicAllowed(Relic r) => true;
  final announced = <String>[];
  @override
  void announce(String text, {Color color = const Color(0xFFE9EDFF)}) => announced.add(text);
}

void main() {
  group('numbers and card text', () {
    test('levels run from the spec table', () {
      expect(AbilityStats.duration(ShipAbility.cloak, 1), 3);
      expect(AbilityStats.cooldown(ShipAbility.cloak, 1), 18);
      expect(AbilityStats.duration(ShipAbility.aegis, 5), 3);
      expect(AbilityStats.cooldown(ShipAbility.decoy, 5), 10);
      expect(AbilityStats.duration(ShipAbility.dash, 3), 0);
      expect(AbilityStats.cooldown(ShipAbility.dash, 1), closeTo(2.2, 1e-9));
      expect(AbilityStats.cooldown(ShipAbility.dash, 2), closeTo(1.98, 1e-9));
    });

    test('change lines', () {
      expect(AbilityStats.change(ShipAbility.cloak, 1), 'Lasts 3 s to 3.4 s, cooldown 18 s to 16.5 s');
      expect(AbilityStats.change(ShipAbility.dash, 1), 'Cooldown 2.2 s to 2 s');
      expect(AbilityStats.change(ShipAbility.cloak, 0), '');
      expect(AbilityStats.summary(ShipAbility.cloak), 'Lasts 3 s. Cooldown 18 s.');
    });
  });

  group('loadout', () {
    test('take, level up, cap, arm, cycle, notify only on real changes', () {
      final g = _Game();
      final a = g.abilities;
      var n = 0;
      a.addListener(() => n++);
      expect(a.owned, isEmpty);
      expect(a.armed, isNull);
      expect(a.useArmed(), isFalse);

      a.take(ShipAbility.cloak);
      expect((a.armed, a.levelOf(ShipAbility.cloak), n), (ShipAbility.cloak, 1, 1));
      a.take(ShipAbility.aegis);
      expect(a.armed, ShipAbility.cloak, reason: 'a new one does not steal the arm');
      a.arm(ShipAbility.cloak); // already armed: no notify
      expect(n, 2);
      a.cycle(1);
      expect(a.armed, ShipAbility.aegis);
      a.cycle(1);
      expect(a.armed, ShipAbility.cloak, reason: 'wraps');
      for (var i = 0; i < 10; i++) {
        a.take(ShipAbility.cloak);
      }
      expect(a.levelOf(ShipAbility.cloak), ShipAbility.maxLevel);
    });

    test('Overclock doubles fire rate for its duration, then cools down', () {
      final g = _Game();
      final a = g.abilities..take(ShipAbility.overclock);
      expect(a.fireRateMultiplier, 1);
      expect(a.useArmed(), isTrue);
      expect(a.fireRateMultiplier, AbilityStats.overclockFireRate);
      expect(a.activeFraction(ShipAbility.overclock), 1);
      expect(a.useArmed(), isFalse, reason: 'already running');
      a.update(2);
      expect(a.activeFraction(ShipAbility.overclock), closeTo(0.5, 1e-9));
      a.update(2.1);
      expect(a.fireRateMultiplier, 1);
      // Cooldown starts when the effect ends.
      expect(a.cooldownLeft(ShipAbility.overclock), closeTo(16, 1e-9));
      expect(a.cooldownFraction(ShipAbility.overclock), 1);
      expect(a.useArmed(), isFalse);
      a.update(16.1);
      expect(a.cooldownLeft(ShipAbility.overclock), 0);
      expect(a.useArmed(), isTrue);
    });

    test('not usable while paused or after death', () {
      final g = _Game();
      final a = g.abilities..take(ShipAbility.overclock);
      g.paused = true;
      expect(a.useArmed(), isFalse);
      g.paused = false;
      g.isGameOver = true;
      expect(a.useArmed(), isFalse);
    });

    test('Dash: cooldown is the player\'s, scaled by level and the ship class', () {
      final g = _Game()..shipClass = ShipClass.interceptor;
      final a = g.abilities..take(ShipAbility.dash);
      expect(a.cooldownMax(ShipAbility.dash), closeTo(2.2 * 0.6, 1e-9));
      a.take(ShipAbility.dash);
      expect(a.cooldownMax(ShipAbility.dash), closeTo(1.98 * 0.6, 1e-9));
      expect(a.use(ShipAbility.dash), isTrue);
      expect(a.cooldownLeft(ShipAbility.dash), greaterThan(0));
      expect(a.use(ShipAbility.dash), isFalse);
    });

    test('abilities you do not own can not be used', () {
      final g = _Game();
      expect(g.abilities.use(ShipAbility.dash), isFalse);
    });

    test('save and restore; an old save without abilities gets Dash', () {
      final g = _Game();
      g.abilities
        ..take(ShipAbility.aegis)
        ..take(ShipAbility.aegis)
        ..take(ShipAbility.decoy)
        ..arm(ShipAbility.decoy);
      final snap = g.abilities.snapshot();
      final h = _Game();
      h.abilities.restore(snap);
      expect(h.abilities.owned, [ShipAbility.aegis, ShipAbility.decoy]);
      expect(h.abilities.levelOf(ShipAbility.aegis), 2);
      expect(h.abilities.armed, ShipAbility.decoy);

      final old = _Game()..abilities.restore(null);
      expect(old.abilities.owned, [ShipAbility.dash]);
      final junk = _Game()..abilities.restore({'own': ['nope', 'cloak'], 'lv': {'cloak': 99}, 'armed': 'zzz'});
      expect(junk.abilities.owned, [ShipAbility.cloak]);
      expect(junk.abilities.levelOf(ShipAbility.cloak), ShipAbility.maxLevel);
      expect(junk.abilities.armed, ShipAbility.cloak);
    });
  });

  group('offers', () {
    test('the first offer of a run carries Dash, once, never on boss rewards', () {
      final g = _Game()..isBossReward = true;
      for (var i = 0; i < 50; i++) {
        expect(generateUpgradeCards(g).any((c) => c is AbilityCard && c.ability == ShipAbility.dash), isFalse);
      }
      g.isBossReward = false;
      final first = generateUpgradeCards(g);
      expect(first, hasLength(3));
      final dash = first.whereType<AbilityCard>().single;
      expect(dash.ability, ShipAbility.dash);
      expect(dash.isNew, isTrue);
      expect(dash.title, 'Dash');
      expect(dash.change, '');
      expect(g.abilityDashOffered, isTrue);
    });

    test('later offers sometimes carry an ability; owned ones level up; maxed ones vanish', () {
      final g = _Game()..abilityDashOffered = true;
      g.abilities.take(ShipAbility.dash);
      var seen = 0;
      for (var i = 0; i < 400; i++) {
        final o = generateUpgradeCards(g);
        expect(o, hasLength(3));
        seen += o.whereType<AbilityCard>().length;
        for (final c in o.whereType<AbilityCard>()) {
          expect(c.fromLevel, g.abilities.levelOf(c.ability));
        }
      }
      // ~30% of 400
      expect(seen, inInclusiveRange(70, 170));

      for (final a in ShipAbility.values) {
        for (var i = 0; i < 5; i++) {
          g.abilities.take(a);
        }
      }
      for (var i = 0; i < 100; i++) {
        expect(generateUpgradeCards(g).whereType<AbilityCard>(), isEmpty);
      }
    });

    test('taking a card adds or levels the ability', () {
      final g = _Game();
      AbilityCard(ShipAbility.cloak).apply(g);
      expect(g.abilities.levelOf(ShipAbility.cloak), 1);
      final up = AbilityCard(ShipAbility.cloak, fromLevel: 1);
      expect(up.change, isNotEmpty);
      expect(up.category, UpgradeCategory.ability);
      expect(up.glyph, CardGlyph.ability);
      up.apply(g);
      expect(g.abilities.levelOf(ShipAbility.cloak), 2);
      expect(g.announced.last, 'Cloak Lv2');
    });
  });
}
