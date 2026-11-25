// B5 verification: ship abilities inside the REAL NovaboltGame (headless widget
// test), not fakes. Complements test/ability_test.dart (unit level).
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/components/boss_projectile.dart';
import 'package:novabolt/game/components/caster_projectile.dart';
import 'package:novabolt/game/components/monster.dart';
import 'package:novabolt/game/components/monster_caster.dart';
import 'package:novabolt/game/components/ability_components.dart';
import 'package:novabolt/game/components/weapon_magic_bolt.dart';
import 'package:novabolt/game/data/ability_stats.dart';
import 'package:novabolt/game/data/balance.dart';
import 'package:novabolt/game/data/monster_data.dart';
import 'package:novabolt/game/data/nova_mode.dart';
import 'package:novabolt/game/data/ship_ability.dart';
import 'package:novabolt/game/data/upgrade_cards.dart';
import 'package:novabolt/game/novabolt_game.dart';
import 'package:novabolt/game/systems/supercharge_system.dart';
import 'package:novabolt/game/systems/wave_system.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> frame(WidgetTester t, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(microseconds: 16667));
  }
}

/// A dummy that stands still, never hurts, and (optionally) isn't tauntable (a boss).
const _stats = MonsterStats(maxHp: 1e6, speed: 0, contactDamagePerSecond: 0, size: 30, xpValue: 0, chargeValue: 0, shieldDropChance: 0, healthDropChance: 0);

class Dummy extends Monster {
  final bool boss;
  Dummy(Vector2 p, {this.boss = false}) : super(position: p, stats: _stats);
  @override
  bool get tauntable => !boss;
  @override
  Color get deathColor => const Color(0xFFFFFFFF);
  @override
  void render(Canvas canvas) {}
  @override
  void updateMovement(double dt) {}
}

Future<NovaboltGame> boot(WidgetTester t, {Map<String, dynamic>? resume}) async {
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final game = NovaboltGame(resume: resume);
  await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: GameWidget(game: game, key: UniqueKey(), overlayBuilderMap: {
        'Countdown': (c, g) => const SizedBox.shrink(),
        'LevelUp': (c, g) => const SizedBox.shrink(),
        'GameOver': (c, g) => const SizedBox.shrink(),
      })));
  await frame(t, 12);
  for (final w in game.world.children.whereType<WaveSystem>().toList()) {
    w.removeFromParent();
  }
  for (final m in game.world.children.whereType<Monster>().toList()) {
    m.removeFromParent();
  }
  await frame(t);
  game.player.maxHp = 1e6;
  game.player.currentHp = 1e6;
  return game;
}

const _biter = MonsterStats(maxHp: 1e6, speed: 0, contactDamagePerSecond: 50, size: 40, xpValue: 0, chargeValue: 0, shieldDropChance: 0, healthDropChance: 0);

class Biter extends Dummy {
  Biter(super.p);
  @override
  MonsterStats get stats => _biter;
}

void main() {
  testWidgets('a fresh run has no abilities: double-tap dash does nothing until Dash is owned', (t) async {
    final g = await boot(t);
    expect(g.abilities.owned, isEmpty);
    expect(g.tryDash(), isFalse);
    expect(g.player.isDashing, isFalse);
    expect(g.player.dashCooldown, 0);
    expect(g.tryUseAbility(), isFalse);
    g.abilities.take(ShipAbility.dash);
    expect(g.tryDash(), isTrue);
    expect(g.player.isDashing, isTrue);
    expect(g.player.dashCooldown, greaterThan(0));
    expect(g.tryDash(), isFalse, reason: 'cooling down');
    await frame(t, 30);
  });

  testWidgets('the first real level-up offer carries Dash; a later one does not force it', (t) async {
    final g = await boot(t);
    final first = generateUpgradeCards(g);
    expect(first.whereType<AbilityCard>().where((c) => c.ability == ShipAbility.dash), hasLength(1));
    expect(g.abilityDashOffered, isTrue);
    // Declining Dash: not guaranteed again.
    var forced = 0;
    for (var i = 0; i < 60; i++) {
      final o = generateUpgradeCards(g);
      if (o.whereType<AbilityCard>().any((c) => c.ability == ShipAbility.dash)) forced++;
    }
    expect(forced, lessThan(40), reason: 'only the ~30% random chance, not every time');
    // Taking the card works inside the real game.
    first.whereType<AbilityCard>().single.apply(g);
    expect(g.abilities.owned, [ShipAbility.dash]);
    expect(g.abilities.armed, ShipAbility.dash);
    expect(g.tryDash(), isTrue);
  });

  testWidgets('Cloak: ordinary enemies aim and fire at the last known spot; cooldown starts after it ends', (t) async {
    final g = await boot(t);
    g.abilities.take(ShipAbility.cloak);
    final caster = MonsterCaster(position: g.player.position + Vector2(0, -250));
    g.world.add(caster);
    await frame(t);
    final spot = g.player.position.clone();
    expect(g.abilities.use(ShipAbility.cloak), isTrue);
    expect(g.abilities.cloaked, isTrue);
    expect(g.abilities.cooldownLeft(ShipAbility.cloak), 0, reason: 'cooldown only starts when the effect ends');
    // The ship slips away.
    g.player.position.add(Vector2(150, 0));
    await frame(t);
    expect(caster.target.distanceTo(spot), lessThan(0.01));
    expect(caster.target.distanceTo(g.player.position), greaterThan(100));
    // Its shot flies at the spot, not the ship.
    CasterProjectile? shot;
    for (var i = 0; i < 200 && shot == null; i++) {
      await frame(t);
      shot = g.world.children.whereType<CasterProjectile>().firstOrNull;
    }
    expect(shot, isNotNull, reason: 'the caster fired');
    final want = (spot - caster.position)..normalize();
    expect(shot!.direction.dot(want), greaterThan(0.99));
    // Ends after its duration; cooldown then runs for the full time.
    await frame(t, (AbilityStats.duration(ShipAbility.cloak, 1) * 60).ceil() + 5);
    expect(g.abilities.cloaked, isFalse);
    expect(g.abilities.cloakSpot, isNull);
    expect(g.abilities.cooldownLeft(ShipAbility.cloak), inInclusiveRange(1, AbilityStats.cooldown(ShipAbility.cloak, 1)));
    expect(caster.target.distanceTo(g.player.position), lessThan(0.01), reason: 'enemies see the ship again');
    expect(g.abilities.use(ShipAbility.cloak), isFalse, reason: 'still cooling');
  });

  testWidgets('bosses (not tauntable) ignore Cloak and Decoy on purpose', (t) async {
    final g = await boot(t);
    g.abilities
      ..take(ShipAbility.cloak)
      ..take(ShipAbility.decoy);
    final boss = Dummy(g.player.position + Vector2(0, -300), boss: true);
    final grunt = Dummy(g.player.position + Vector2(0, -300));
    g.world.addAll([boss, grunt]);
    await frame(t);
    g.abilities.use(ShipAbility.cloak);
    g.player.position.add(Vector2(100, 0));
    await frame(t);
    expect(boss.target.distanceTo(g.player.position), lessThan(0.01));
    expect(grunt.target.distanceTo(g.player.position), greaterThan(50));
    g.abilities.arm(ShipAbility.decoy);
    await frame(t, 200); // let cloak run out
    expect(g.abilities.use(ShipAbility.decoy), isTrue);
    await frame(t);
    g.player.position.add(Vector2(-200, 0));
    await frame(t);
    expect(boss.target.distanceTo(g.player.position), lessThan(0.01));
    expect(grunt.target.distanceTo(g.abilities.decoyPosition!), lessThan(0.01));
  });

  testWidgets('Decoy: enemies chase it, caster shots hit it instead of the ship', (t) async {
    final g = await boot(t);
    g.abilities.take(ShipAbility.decoy);
    g.player.currentHp = 500;
    g.player.maxHp = 500;
    g.abilities.use(ShipAbility.decoy);
    await frame(t, 2);
    final decoyPos = g.abilities.decoyPosition!.clone();
    g.player.position.add(Vector2(0, 200)); // ship moves off
    final caster = MonsterCaster(position: decoyPos + Vector2(0, -200));
    g.world.add(caster);
    await frame(t);
    expect(caster.target.distanceTo(decoyPos), lessThan(0.01));
    // A shot flying straight at the decoy is swallowed; the ship takes nothing.
    final before = g.player.currentHp;
    final shot = CasterProjectile(position: decoyPos + Vector2(0, -60), direction: Vector2(0, 1));
    g.world.add(shot);
    await frame(t, 4);
    expect(shot.isMounted, isTrue);
    await frame(t, 16); // ~0.3 s: it reaches the decoy (60 px at 220 px/s) and is swallowed
    expect(shot.isMounted, isFalse, reason: 'the decoy swallowed the shot');
    expect(shot.lifetime, lessThan(1.0));
    expect(g.player.currentHp, before);
    // Ends with its timer and goes away.
    await frame(t, (AbilityStats.duration(ShipAbility.decoy, 1) * 60).ceil() + 5);
    expect(g.abilities.decoyPosition, isNull);
    expect(g.world.children.whereType<AbilityDecoy>(), isEmpty);
  });

  testWidgets('Aegis: caster and boss shots come back as player shots at 2x damage (cap 150); contact is not blocked', (t) async {
    final g = await boot(t);
    g.abilities.take(ShipAbility.aegis);
    g.player.currentHp = 1000;
    g.player.maxHp = 1000;
    expect(g.abilities.use(ShipAbility.aegis), isTrue);
    await frame(t, 12);
    final p = g.player.position;
    final far = Vector2(0, -70);
    // Caster shot (damage 12) straight at the ship.
    g.world.add(CasterProjectile(position: p + far, direction: Vector2(0, 1)));
    // A heavy boss shot (damage 100 -> 200 uncapped) and a light one (20 -> 40).
    g.world.add(BossProjectile(position: p + Vector2(70, 0), direction: Vector2(-1, 0), damage: 100));
    g.world.add(BossProjectile(position: p + Vector2(-70, 0), direction: Vector2(1, 0), damage: 20));
    final hp = g.player.currentHp;
    await frame(t, 12);
    expect(g.world.children.whereType<CasterProjectile>(), isEmpty);
    expect(g.world.children.whereType<BossProjectile>(), isEmpty);
    expect(g.player.currentHp, hp, reason: 'nothing got through');
    final bolts = g.world.children.whereType<MagicBolt>().toList();
    final dmgs = bolts.map((b) => b.damage).toList()..sort();
    expect(dmgs, containsAll([24.0, 40.0, 150.0]));
    // The reflected bolt travels outward and can hurt monsters.
    for (final b in bolts) {
      expect(b.direction.length, closeTo(1, 1e-6));
    }
    // Contact damage is NOT blocked: a hostile touching the ship still hurts.
    await frame(t, (AbilityStats.duration(ShipAbility.aegis, 1) * 60).ceil() + 5);
    expect(g.abilities.isActive(ShipAbility.aegis), isFalse);
    expect(g.world.children.whereType<AegisField>(), isEmpty);
    // After the bubble is gone shots hurt again.
    g.world.add(CasterProjectile(position: p + Vector2(0, -30), direction: Vector2(0, 1)));
    await frame(t, 10);
    expect(g.player.currentHp, lessThan(hp));
  });

  testWidgets('Overclock doubles the fire rate, then reverts; stacks with Overdrive multiplicatively', (t) async {
    final g = await boot(t);
    final w = g.player.activeWeapons.first;
    final base = w.effectiveFireRate;
    g.abilities.take(ShipAbility.overclock);
    g.abilities.use(ShipAbility.overclock);
    expect(w.effectiveFireRate, closeTo(base * 2, 1e-9));
    g.overdrive = 5; // Overdrive (the 50 combo) on top
    final withOd = w.effectiveFireRate;
    g.abilities.update(0); // no-op
    expect(withOd, closeTo(base * (1 + Balance.overdriveFireRate) * 2, 1e-9));
    g.overdrive = 0;
    await frame(t, (AbilityStats.duration(ShipAbility.overclock, 1) * 60).ceil() + 5);
    expect(w.effectiveFireRate, closeTo(base, 1e-9));
    expect(g.abilities.cooldownLeft(ShipAbility.overclock), greaterThan(15));
  });

  testWidgets('levels change duration and cooldown exactly as the card says', (t) async {
    final g = await boot(t);
    for (final a in [ShipAbility.cloak, ShipAbility.decoy, ShipAbility.aegis, ShipAbility.overclock]) {
      for (var lv = 1; lv <= ShipAbility.maxLevel; lv++) {
        final h = await boot(t);
        for (var i = 0; i < lv; i++) {
          h.abilities.take(a);
        }
        expect(h.abilities.levelOf(a), lv);
        h.abilities.use(a);
        expect(h.abilities.activeLeft(a), closeTo(AbilityStats.duration(a, lv), 1e-9), reason: '$a L$lv');
        // Run it out; cooldown must equal the table.
        await frame(t, (AbilityStats.duration(a, lv) * 60).ceil() + 3);
        expect(h.abilities.isActive(a), isFalse, reason: '$a L$lv');
        expect(h.abilities.cooldownLeft(a), closeTo(AbilityStats.cooldown(a, lv), 0.15), reason: '$a L$lv');
        expect(h.abilities.cooldownMax(a), closeTo(AbilityStats.cooldown(a, lv), 1e-9));
      }
    }
    // Card text matches the numbers (the "to" values are the next level's).
    for (final a in ShipAbility.values) {
      for (var lv = 1; lv < ShipAbility.maxLevel; lv++) {
        final text = AbilityCard(a, fromLevel: lv).description;
        final to = lv + 1;
        if (a != ShipAbility.dash) {
          expect(text, contains('${AbilityStats.fmt(AbilityStats.duration(a, to))} s'), reason: '$a $lv->$to');
        }
        expect(text, contains('${AbilityStats.fmt(AbilityStats.cooldown(a, to))} s'), reason: '$a $lv->$to');
      }
    }
    expect(g.abilities.owned, isEmpty);
  });

  testWidgets('Dash level lowers its cooldown through the real player', (t) async {
    final g = await boot(t);
    for (var i = 0; i < 3; i++) {
      g.abilities.take(ShipAbility.dash);
    }
    g.tryDash();
    expect(g.player.dashCooldown, closeTo(AbilityStats.cooldown(ShipAbility.dash, 3) * g.shipClass.dashCooldown, 1e-6));
  });

  testWidgets('save and exit then Continue restores abilities; an old save gets Dash level 1', (t) async {
    final g = await boot(t);
    g.abilities
      ..take(ShipAbility.aegis)
      ..take(ShipAbility.aegis)
      ..take(ShipAbility.overclock)
      ..arm(ShipAbility.overclock);
    final snap = Map<String, dynamic>.from(
        (await Future.value(g.snapshot())).map((k, v) => MapEntry(k, v))); // json-ish copy
    expect(snap['abil'], isNotNull);

    final h = await boot(t, resume: snap);
    await frame(t, 10);
    expect(h.abilities.owned, [ShipAbility.aegis, ShipAbility.overclock]);
    expect(h.abilities.levelOf(ShipAbility.aegis), 2);
    expect(h.abilities.armed, ShipAbility.overclock);
    expect(h.tryDash(), isFalse, reason: 'Dash was not owned');

    final old = Map<String, dynamic>.from(snap)..remove('abil');
    final o = await boot(t, resume: old);
    await frame(t, 10);
    expect(o.abilities.owned, [ShipAbility.dash]);
    expect(o.abilities.levelOf(ShipAbility.dash), 1);
    o.resumeEngine(); // the Countdown overlay does this in the real app
    await frame(t, 2);
    expect(o.tryDash(), isTrue);
  });

  testWidgets('the selector slows ability timers to 0.25x; it clears on restart and on death', (t) async {
    final g = await boot(t);
    g.abilities.take(ShipAbility.overclock);
    g.abilities.use(ShipAbility.overclock);
    final start = g.abilities.activeLeft(ShipAbility.overclock);
    await frame(t, 60); // 1 s normal
    final normal = start - g.abilities.activeLeft(ShipAbility.overclock);
    final mid = g.abilities.activeLeft(ShipAbility.overclock);
    g.abilitySelectorOpen = true;
    await frame(t, 60);
    final slow = mid - g.abilities.activeLeft(ShipAbility.overclock);
    expect(normal, closeTo(1.0, 0.1));
    expect(slow, closeTo(0.25, 0.06));
    // Death clears the flag.
    g.player.currentHp = 0;
    g.player.takeDamage(1e9);
    await frame(t, 5);
    expect(g.isGameOver, isTrue);
    expect(g.abilitySelectorOpen, isFalse);
    // Restart clears it too and wipes abilities.
    g.abilitySelectorOpen = true;
    g.restart();
    await frame(t, 3);
    expect(g.abilitySelectorOpen, isFalse);
    expect(g.abilities.owned, isEmpty);
    expect(g.abilityDashOffered, isFalse);
    expect(g.tryDash(), isFalse);
  });

  testWidgets('restart removes running effects (cloak marker, decoy, aegis) and cooldowns', (t) async {
    final g = await boot(t);
    for (final a in [ShipAbility.cloak, ShipAbility.decoy, ShipAbility.aegis]) {
      g.abilities.take(a);
      g.abilities.use(a);
    }
    await frame(t, 5);
    expect(g.world.children.whereType<AbilityDecoy>(), isNotEmpty);
    g.player.takeDamage(1e12);
    await frame(t, 5);
    g.restart();
    await frame(t, 5);
    expect(g.world.children.whereType<AbilityDecoy>(), isEmpty);
    expect(g.world.children.whereType<AegisField>(), isEmpty);
    expect(g.world.children.whereType<CloakMarker>(), isEmpty);
    expect(g.abilities.cloakSpot, isNull);
    expect(g.abilities.decoyPosition, isNull);
    expect(g.abilities.cooldownLeft(ShipAbility.cloak), 0);
  });

  testWidgets('all abilities at once plus Overdrive and a Nova: no exceptions, state stays sane', (t) async {
    final g = await boot(t);
    for (final a in ShipAbility.values) {
      g.abilities.take(a);
    }
    for (var i = 0; i < 6; i++) {
      g.world.add(Dummy(g.player.position + Vector2(40.0 * i - 100, -180)));
      g.world.add(MonsterCaster(position: g.player.position + Vector2(40.0 * i - 100, -260)));
    }
    g.overdrive = 5;
    g.activeNovaMode = NovaMode.laser;
    g.superchargeSystem.addCharge(SuperchargeSystem.maxCharge * 10);
    for (final a in ShipAbility.values) {
      g.abilities.use(a);
    }
    g.activateSupercharge();
    for (var i = 0; i < 60 * 8; i++) {
      await frame(t);
      if (i == 90) g.abilitySelectorOpen = true;
      if (i == 150) g.abilitySelectorOpen = false;
      if (i % 100 == 0) g.player.position.add(Vector2(20, 0));
    }
    expect(t.takeException(), isNull);
    expect(g.abilities.cooldownLeft(ShipAbility.cloak), greaterThanOrEqualTo(0));
    expect(g.abilities.cloakSpot == null || g.abilities.cloaked, isTrue, reason: 'cloak marker state matches the effect');
  });

  testWidgets('Aegis does not block contact damage', (t) async {
    final g = await boot(t);
    g.abilities.take(ShipAbility.aegis);
    g.player.currentHp = 1000;
    g.player.maxHp = 1000;
    g.player.invulnerable = 0;
    // (Flame only reports a contact when something moves into another, so the
    // ship drives into the monster.)
    Future<double> ram() async {
      final b = Biter(g.player.position + Vector2(60, 0));
      g.world.add(b);
      await frame(t, 2);
      final before = g.player.currentHp;
      for (var i = 0; i < 40; i++) {
        g.player.position.x += 2;
        await frame(t);
      }
      g.player.position.x -= 80;
      return before - g.player.currentHp;
    }

    final plain = await ram(); // control: no Aegis
    expect(plain, greaterThan(0), reason: 'harness: ramming a biter hurts');
    await frame(t, 90);
    g.player.invulnerable = 0;
    g.abilities.use(ShipAbility.aegis);
    final shielded = await ram();
    expect(g.abilities.isActive(ShipAbility.aegis), isTrue);
    expect(shielded, greaterThan(0), reason: 'Aegis must not stop contact damage');
    await t.runAsync(StatsManager.instance.flush); // cancel the kill-autosave timer (B1)
  });
}
