// A3/A4 verification: Void Mines, Event Horizon, per-mode charge/duration
// scaling, and old saves, against the real game.
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/components/boss_projectile.dart';
import 'package:novabolt/game/components/caster_projectile.dart';
import 'dart:ui' show Color;
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:novabolt/game/components/monster.dart';
import 'package:novabolt/game/data/monster_data.dart';
import 'package:novabolt/game/components/nova_attacks.dart';
import 'package:novabolt/game/components/weapon_magic_bolt.dart';
import 'package:novabolt/game/data/nova_mode.dart';
import 'package:novabolt/game/systems/supercharge_system.dart';
import 'package:novabolt/stats/stats_manager.dart';

import 'ability_game_test.dart' show boot, frame, Dummy;

void fullNova(dynamic g, NovaMode m) {
  g.nova.unlock(m);
  g.superchargeSystem.addCharge(SuperchargeSystem.maxCharge * 10);
  g.activateSupercharge();
}

double hp(Monster m) => m.currentHp;

void main() {
  group('per-mode scaling (SuperchargeSystem)', () {
    test('every mode has sane scales', () {
      for (final m in NovaMode.values) {
        expect(m.durationScale, inInclusiveRange(0.3, 3), reason: m.name);
        expect(m.chargeScale, inInclusiveRange(0.2, 3), reason: m.name);
      }
      expect(NovaMode.laser.durationScale, 1);
      expect(NovaMode.laser.chargeScale, 1);
    });

    test('charging uses the ARMED mode; a Nova lasts 5 s x durationScale x (1 + duration bonus)', () {
      for (final m in NovaMode.values) {
        final s = SuperchargeSystem()..modeSource = (() => m);
        s.addCharge(10);
        expect(s.charge, closeTo(10 * m.chargeScale, 1e-9), reason: '${m.name} charge');
        s.addCharge(1000);
        expect(s.isReady, isTrue, reason: m.name);
        s.activate();
        var secs = 0.0;
        while (!s.deplete(1 / 60) && secs < 60) {
          secs += 1 / 60;
        }
        expect(secs, closeTo(5 * m.durationScale, 0.1), reason: '${m.name} duration');
        // With the card bonuses on top (+50% duration, +30% charge, x2 daily).
        final b = SuperchargeSystem()
          ..modeSource = (() => m)
          ..durationBonus = 0.5
          ..chargeBonus = 0.3
          ..chargeBase = 2;
        b.addCharge(1);
        expect(b.charge, closeTo(1 * m.chargeScale * 1.3 * 2, 1e-9), reason: '${m.name} bonuses');
        b.addCharge(1000);
        b.activate();
        secs = 0;
        while (!b.deplete(1 / 60) && secs < 60) {
          secs += 1 / 60;
        }
        expect(secs, closeTo(5 * m.durationScale * 1.5, 0.12), reason: '${m.name} duration with bonus');
      }
    });

    test('switching the armed mode during a Nova does not change the one running', () {
      var armed = NovaMode.shadowReaper; // 1.6x
      final s = SuperchargeSystem()..modeSource = (() => armed);
      s.addCharge(1000);
      s.activate();
      armed = NovaMode.leviathan; // 0.5x, armed mid-run
      var secs = 0.0;
      while (!s.deplete(1 / 60) && secs < 60) {
        secs += 1 / 60;
      }
      expect(secs, closeTo(8, 0.15));
    });

    test('display names changed, enum names (persisted) did not', () {
      expect(NovaMode.voidTyrant.displayName, 'Void Mines');
      expect(NovaMode.singularity.displayName, 'Event Horizon');
      expect(NovaMode.voidTyrant.name, 'voidTyrant');
      expect(NovaMode.singularity.name, 'singularity');
      expect(NovaMode.voidTyrant.inheritTitle, 'Inherit VOID MINES');
      expect(NovaMode.singularity.inheritTitle, 'Inherit EVENT HORIZON');
    });
  });

  group('Void Mines (real game)', () {
    testWidgets('arm after a delay, blast whatever is close, leave far things alone, and clean up', (t) async {
      final g = await boot(t);
      final c = g.player.position.clone();
      // A dense ring of stationary dummies where the mines land (about 120 px out).
      final ring = <Dummy>[];
      for (var i = 0; i < 36; i++) {
        final a = i * 3.14159265 * 2 / 36;
        ring.add(Dummy(c + (Vector2(1, 0)..rotate(a)) * 120));
      }
      final far = Dummy(c + Vector2(0, -340)); // well outside blast + trigger
      g.world.addAll([...ring, far]);
      await frame(t, 2);
      final before = ring.map(hp).reduce((a, b) => a + b);
      fullNova(g, NovaMode.voidTyrant);
      await frame(t, 1);
      expect(g.world.children.whereType<VoidMinesNova>(), hasLength(1));
      // Mines scatter (0.35 s) then arm (0.45 s): nothing is hurt before ~0.8 s.
      await frame(t, 40); // ~0.67 s
      expect(ring.map(hp).reduce((a, b) => a + b), before, reason: 'unarmed mines do not blast');
      await frame(t, 40); // ~1.3 s
      final after = ring.map(hp).reduce((a, b) => a + b);
      expect(after, lessThan(before), reason: 'armed mines blast enemies that come close');
      expect(hp(far), 1e6, reason: 'far enemies are not hit');
      // Run out the Nova (2.5 s) and check everything is gone.
      await frame(t, 60 * 4);
      expect(g.superchargeSystem.isActive, isFalse);
      expect(g.world.children.whereType<VoidMinesNova>(), isEmpty);
      expect(hp(far), 1e6);
      await frame(t, 40); // blast flashes finish
      expect(g.world.children.where((c) => c.runtimeType.toString() == '_MineBlastFx'), isEmpty);
      expect(t.takeException(), isNull);
      await t.runAsync(StatsManager.instance.flush);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('with nothing around, leftover mines still pop at the end and nothing lingers', (t) async {
      final g = await boot(t);
      fullNova(g, NovaMode.voidTyrant);
      await frame(t, 60 * 4);
      expect(g.superchargeSystem.isActive, isFalse);
      expect(g.world.children.whereType<VoidMinesNova>(), isEmpty);
      await frame(t, 40);
      expect(g.world.children.where((c) => c.runtimeType.toString() == '_MineBlastFx'), isEmpty);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a second Nova right after works (no stale mines)', (t) async {
      final g = await boot(t);
      for (var k = 0; k < 2; k++) {
        fullNova(g, NovaMode.voidTyrant);
        await frame(t, 60 * 4);
        expect(g.superchargeSystem.isActive, isFalse, reason: 'run $k');
      }
      expect(g.world.children.whereType<VoidMinesNova>(), isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('Event Horizon (real game)', () {
    testWidgets('erases enemy shots (caster and boss) before they reach the ship, keeps player shots', (t) async {
      final g = await boot(t);
      g.player.maxHp = 1000;
      g.player.currentHp = 1000;
      g.player.invulnerable = 0;
      final p = g.player.position.clone();
      fullNova(g, NovaMode.singularity);
      await frame(t, 30); // ring fully grown (0.25 s)
      final caster = CasterProjectile(position: p + Vector2(0, -220), direction: Vector2(0, 1));
      final boss = BossProjectile(position: p + Vector2(200, 0), direction: Vector2(-1, 0), damage: 40);
      final mine = MagicBolt(position: p + Vector2(0, 60), direction: Vector2(0, 1), damage: 5, color: const Color(0xFF00E5FF));
      g.world.addAll([caster, boss, mine]);
      await frame(t, 60);
      expect(caster.isMounted, isFalse, reason: 'caster shot erased');
      expect(boss.isMounted, isFalse, reason: 'boss shot erased');
      expect(g.player.currentHp, 1000, reason: 'nothing reached the ship');
      expect(mine.isMounted || mine.position.y > p.y + 100, isTrue, reason: 'the ship\'s own shots fly out through the ring');
      await t.runAsync(StatsManager.instance.flush);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('damages and shoves enemies that touch the ring; leaves far ones; bosses take damage but are not shoved', (t) async {
      final g = await boot(t);
      final p = g.player.position.clone();
      fullNova(g, NovaMode.singularity);
      await frame(t, 30);
      final onRing = Dummy(p + Vector2(96, 0));
      final far = Dummy(p + Vector2(0, -250));
      final inside = Dummy(p + Vector2(0, 62));
      final bigOnRing = BigDummy(p + Vector2(-96, 0));
      g.world.addAll([onRing, far, inside, bigOnRing]);
      await frame(t, 4);
      expect(hp(onRing), lessThan(1e6), reason: 'touched the ring');
      expect(onRing.position.x, greaterThan(p.x + 96 + 20), reason: 'shoved outward');
      expect(hp(far), 1e6);
      expect(hp(inside), 1e6, reason: 'inside the ring: not touched');
      expect(hp(bigOnRing), lessThan(1e6), reason: 'bosses take damage');
      expect((bigOnRing.position - (p + Vector2(-96, 0))).length, lessThan(1), reason: 'but are not shoved');
      // Hit again only after the gap (0.35 s small / 0.8 s big).
      final first = hp(onRing);
      await frame(t, 6);
      expect(hp(onRing), first, reason: 'hit gap respected (and it was thrown clear)');
      await t.runAsync(StatsManager.instance.flush);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('ends with the Nova and removes its ring', (t) async {
      final g = await boot(t);
      fullNova(g, NovaMode.singularity);
      await frame(t, 60 * 5);
      expect(g.superchargeSystem.isActive, isFalse);
      expect(g.world.children.whereType<EventHorizonNova>(), isEmpty);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('old saves', () {
    for (final m in [NovaMode.voidTyrant, NovaMode.singularity]) {
      testWidgets('a save with ${m.name} armed and unlocked restores and can fire', (t) async {
        final g0 = await boot(t);
        g0.nova.unlock(NovaMode.voidTyrant);
        g0.nova.unlock(NovaMode.singularity);
        g0.activeNovaMode = m;
        final snap = Map<String, dynamic>.from(g0.snapshot());
        // Old saves carry the same plain names.
        expect((snap['nova'] as Map)['mode'], m.name);
        final g = await boot(t, resume: snap);
        await frame(t, 10);
        g.resumeEngine();
        await frame(t, 2);
        expect(g.activeNovaMode, m);
        expect(g.unlockedNovaModes, containsAll([NovaMode.laser, NovaMode.voidTyrant, NovaMode.singularity]));
        fullNova(g, m);
        await frame(t, 90);
        expect(g.superchargeSystem.isActive, isTrue);
        expect(t.takeException(), isNull);
        await t.runAsync(StatsManager.instance.flush);
        await t.pumpWidget(const SizedBox());
      });
    }

    testWidgets('an unknown mode name in a save falls back to the laser instead of crashing', (t) async {
      final g0 = await boot(t);
      final snap = Map<String, dynamic>.from(g0.snapshot());
      snap['nova'] = {...(snap['nova'] as Map), 'mode': 'voidWellX', 'unl': ['voidWellX', 'singularity']};
      final g = await boot(t, resume: snap);
      await frame(t, 10);
      expect(g.activeNovaMode, NovaMode.laser);
      expect(g.unlockedNovaModes, contains(NovaMode.singularity));
      await t.pumpWidget(const SizedBox());
    });
  });
}

/// A boss-sized dummy (size >= 70 counts as "big" for the ring).
const _bigStats = MonsterStats(maxHp: 1e6, speed: 0, contactDamagePerSecond: 0, size: 100, xpValue: 0, chargeValue: 0, shieldDropChance: 0, healthDropChance: 0);

class BigDummy extends Dummy {
  BigDummy(super.p);
  @override
  MonsterStats get stats => _bigStats;
}
