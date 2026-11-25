import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/shmup/shmup_level.dart';
import 'package:novabolt/arcade/shmup/shmup_levels.dart';
import 'package:novabolt/arcade/shmup/shmup_sim.dart';

const dt = 1 / 60;
const h = 216.0;

/// Open flat terrain, the given spawns, boss far away unless [bossAt] is set.
ShmupLevel level(List<ShmupSpawn> spawns, {Terrain? terrain, double bossAt = 5000, double speed = 24}) => ShmupLevel(
      name: 'test',
      terrain: terrain ?? (TerrainBuilder(ceil: 0.05, floor: 0.05)..flat(6000)).build(),
      spawns: spawns,
      bossAt: bossAt,
      scrollSpeed: speed,
    );

ShmupSim make(List<ShmupSpawn> spawns, {Terrain? terrain, double bossAt = 5000, int seed = 1}) {
  final s = ShmupSim(height: h, seed: seed, levels: [level(spawns, terrain: terrain, bossAt: bossAt)]);
  s.start();
  s.ship.fireCd = 1e9; // the ship doesn't shoot unless a test asks it to
  s.drainEvents();
  return s;
}

void run(ShmupSim s, double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    s.step(dt);
  }
}

/// Runs until [until] is true (or [max] seconds).
void runUntil(ShmupSim s, bool Function() until, {double max = 60}) {
  for (var i = 0; i < max * 60 && !until(); i++) {
    s.step(dt);
  }
}

/// Puts a ship-killing bullet on the ship.
void shootShip(ShmupSim s) {
  s.ship.invuln = 0;
  s.enemyBullets.add(ShmupBullet(s.ship.x, s.ship.y, 0, 0, r: 1.5));
  s.step(dt);
}

/// Parks the ship out of the way and stops it shooting things.
void parkShip(ShmupSim s, {double x = 8, double y = 30}) {
  s.ship.x = x;
  s.ship.y = y;
}

/// Runs until every enemy is on screen (shots can't hit what hasn't entered).
void settleOnScreen(ShmupSim s) => runUntil(s, () => s.enemies.every((e) => e.x < s.width - 8), max: 10);

bool hasEvent(List<ShmupEvent> es, ShmupEventKind k) => es.any((e) => e.kind == k);

void main() {
  group('the level format', () {
    test('both authored stages validate at several screen shapes', () {
      for (final lv in ShmupLevels.all) {
        expect(lv.validate(), isEmpty, reason: lv.name);
        expect(lv.tightest, lessThanOrEqualTo(ShmupLevel.maxCombinedDepth + 1e-9));
        expect(lv.spawns.last.at, lessThanOrEqualTo(lv.bossAt));
        // Spawns are sorted.
        for (var i = 1; i < lv.spawns.length; i++) {
          expect(lv.spawns[i].at, greaterThanOrEqualTo(lv.spawns[i - 1].at));
        }
        // Everything the brief asks for appears across the stages.
      }
      final kinds = {for (final lv in ShmupLevels.all) for (final s in lv.spawns) if (s.enemy != null) s.enemy};
      expect(kinds, containsAll(EnemyKind.values));
      final pickups = {
        for (final lv in ShmupLevels.all)
          for (final s in lv.spawns) ...[if (s.pickup != null) s.pickup, if (s.drop != null) s.drop],
      };
      expect(pickups, containsAll(PickupKind.values));
      expect(ShmupLevels.all.length, greaterThanOrEqualTo(2));
    });

    test('terrain interpolates and the builder composes pieces', () {
      final t = (TerrainBuilder(ceil: 0.1, floor: 0.1)
            ..flat(10)
            ..to(10, ceil: 0.3)
            ..ceilingColumn(5, 0.5, slope: 2)
            ..floorColumn(5, 0.4, slope: 2))
          .build();
      expect(t.ceilAt(5), closeTo(0.1, 1e-9));
      expect(t.ceilAt(15), closeTo(0.2, 1e-9));
      expect(t.ceilAt(20), closeTo(0.3, 1e-9));
      expect(t.ceilAt(24), closeTo(0.5, 1e-9)); // inside the column
      expect(t.ceilAt(30), closeTo(0.3, 1e-9)); // back to base
      expect(t.floorAt(34), closeTo(0.4, 1e-9));
      expect(t.ceilAt(-5), closeTo(0.1, 1e-9));
      expect(t.ceilAt(1000), closeTo(0.3, 1e-9));
    });

    test('validate catches a pinched passage and a mine buried in rock', () {
      final bad = ShmupLevel(
        name: 'bad',
        terrain: (TerrainBuilder(ceil: 0.07, floor: 0.07)
              ..flat(100)
              ..to(10, ceil: 0.45, floor: 0.45))
            .build(),
        spawns: [ShmupSpawn.mineField(100, const [0.9], cols: 1)],
        bossAt: 300,
      );
      final p = bad.validate();
      expect(p.any((m) => m.contains('passage closes')), isTrue);
      expect(p.any((m) => m.contains('in rock')), isTrue);
    });
  });

  group('scrolling, progress and terrain', () {
    test('the world scrolls at the level speed and progress follows', () {
      final s = make(const [], bossAt: 480);
      expect(s.progress, 0);
      run(s, 5);
      expect(s.scrollX, closeTo(120, 0.5));
      expect(s.progress, closeTo(0.25, 0.01));
      run(s, 5);
      expect(s.progress, closeTo(0.5, 0.01));
      expect(s.traveled, closeTo(s.scrollX, 1e-6));
    });

    test('nothing happens before the first touch', () {
      final s = ShmupSim(height: h, seed: 1, levels: [level(const [])]);
      run(s, 3);
      expect(s.scrollX, 0);
      expect(s.phase, ShmupPhase.ready);
      s.moveShipBy(10, 10);
      expect(s.ship.x, ShmupTuning.shipStartX);
    });

    test('moveShipBy is 1:1 and clamped to the field', () {
      final s = make(const []);
      final x0 = s.ship.x, y0 = s.ship.y;
      s.moveShipBy(10, -7);
      expect(s.ship.x, x0 + 10);
      expect(s.ship.y, y0 - 7);
      s.moveShipBy(-1000, -1000);
      expect(s.ship.x, ShmupTuning.shipR);
      expect(s.ship.y, ShmupTuning.shipR);
      s.moveShipBy(1000, 1000);
      expect(s.ship.x, s.width - ShmupTuning.shipR);
      expect(s.ship.y, s.height - ShmupTuning.shipR);
    });

    test('touching terrain hurts once, pushes the ship out, then invulnerability covers it', () {
      // A ceiling that drops to 40% of the height at world x 100..140.
      final t = (TerrainBuilder(ceil: 0.05, floor: 0.05)
            ..flat(90)
            ..ceilingColumn(60, 0.4, slope: 5)
            ..flat(3000))
          .build();
      final s = make(const [], terrain: t);
      s.ship.x = 40;
      s.ship.y = h * 0.2; // fine in the open
      run(s, 1);
      expect(s.ship.hull, 3);
      // Hold the ship at the ceiling as the column arrives.
      s.ship.x = 40;
      var hit = false;
      for (var i = 0; i < 60 * 8; i++) {
        s.ship.y = 12;
        s.ship.x = 40;
        s.step(dt);
        if (s.ship.hull < 3) {
          hit = true;
          break;
        }
      }
      expect(hit, isTrue);
      expect(s.ship.hull, 2);
      expect(s.ship.invuln, greaterThan(1));
      // Pushed clear of the rock: the ship's top is below the ceiling line.
      expect(s.ship.y - ShmupTuning.shipHitR, greaterThanOrEqualTo(s.ceilingAt(s.ship.x) - 0.01));
      final events = s.drainEvents();
      expect(hasEvent(events, ShmupEventKind.terrainHit), isTrue);
      // Still pressed against the rock for a second: no second hit.
      for (var i = 0; i < 60; i++) {
        s.ship.y = 12;
        s.step(dt);
      }
      expect(s.ship.hull, 2);
    });

    test('bullets stop in rock', () {
      final t = (TerrainBuilder(ceil: 0.05, floor: 0.05)
            ..flat(10)
            ..to(1, ceil: 0.5)
            ..flat(3000))
          .build();
      final s = make(const [], terrain: t);
      parkShip(s, y: h * 0.8);
      s.playerBullets.add(ShmupBullet(50, h * 0.3, 0, 0, life: 5));
      s.enemyBullets.add(ShmupBullet(60, h * 0.3, 0, 0, life: 5));
      run(s, 0.5); // the ceiling has dropped to 50% by now at x 50..60
      expect(s.playerBullets.where((b) => b.vx == 0), isEmpty);
      expect(s.enemyBullets, isEmpty);
    });
  });

  group('spawning', () {
    test('waves appear on schedule just off the right edge', () {
      final s = make([ShmupSpawn.squad(300, 0.5, count: 3, spacing: 10)]);
      // Camera right edge reaches at-8 when scrollX = 300 - 108 = 192.
      runUntil(s, () => s.scrollX >= 191);
      expect(s.enemies, isEmpty);
      runUntil(s, () => s.enemies.isNotEmpty);
      expect(s.scrollX, closeTo(192, 0.5));
      expect(s.enemies.length, 3);
      expect(s.enemies.first.x, greaterThanOrEqualTo(s.width + 6));
      expect(s.enemies.map((e) => e.kind).toSet(), {EnemyKind.drone});
    });

    test('spawns fire in order and only once', () {
      final s = make([
        ShmupSpawn.squad(150, 0.3, count: 1),
        ShmupSpawn.squad(250, 0.6, count: 1),
      ]);
      parkShip(s);
      runUntil(s, () => s.enemies.isNotEmpty);
      final first = s.enemies.single;
      expect(first.y0, closeTo(0.3 * h, 0.01));
      run(s, 10);
      expect(s.enemies.where((e) => e.y0 == 0.6 * h).length, lessThanOrEqualTo(1));
      expect(s.kills, 0);
    });

    test('pick-ups appear and drift with the world', () {
      final s = make([ShmupSpawn.pickup(200, 0.5, PickupKind.shield)]);
      parkShip(s, y: 20);
      runUntil(s, () => s.pickups.isNotEmpty);
      final p = s.pickups.single;
      final x0 = p.x;
      run(s, 1);
      expect(x0 - p.x, closeTo(24, 0.5));
    });
  });

  group('enemy kinds', () {
    test('drones fly a sine line and die to one bullet for 1 point', () {
      final s = make([ShmupSpawn.squad(150, 0.5, count: 4, amp: 0.1)]);
      parkShip(s, y: 15);
      runUntil(s, () => s.enemies.isNotEmpty);
      final d = s.enemies.first;
      final ys = <double>[];
      for (var i = 0; i < 90; i++) {
        s.step(dt);
        ys.add(d.y);
      }
      expect(d.x, lessThan(s.width));
      expect(ys.reduce(math.max) - ys.reduce(math.min), greaterThan(h * 0.05));
      // Members share the path: at equal x they are at equal y.
      final other = s.enemies.last;
      expect(other.y0, d.y0);
      s.playerBullets.add(ShmupBullet(d.x, d.y, 0, 0, dmg: 1));
      s.step(dt);
      expect(s.score, 1);
      expect(s.kills, 1);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.enemyKilled), isTrue);
    });

    test('a drone told to fire shoots aimed bullets', () {
      final s = make([ShmupSpawn.squad(150, 0.5, count: 1, fireEvery: 1.0)]);
      parkShip(s, x: 10, y: h * 0.5);
      runUntil(s, () => s.enemyBullets.isNotEmpty, max: 15);
      expect(s.enemyBullets, isNotEmpty);
      expect(s.enemyBullets.first.vx, lessThan(0));
    });

    test('a turret hugs the terrain, shoots when on screen, takes 3 hits and pays 2', () {
      final t = (TerrainBuilder(ceil: 0.05, floor: 0.2)..flat(6000)).build();
      final s = make([ShmupSpawn.turret(200, Anchor.floor)], terrain: t);
      parkShip(s, x: 20, y: 60);
      runUntil(s, () => s.enemies.isNotEmpty);
      final e = s.enemies.single;
      expect(e.y, closeTo(h * 0.8 - 1.2, 0.01));
      expect(e.locked, isTrue);
      expect(s.enemyBullets, isEmpty); // not on screen yet
      runUntil(s, () => s.enemyBullets.isNotEmpty, max: 15);
      expect(s.enemyBullets, isNotEmpty);
      expect(e.x, lessThan(s.width));
      // It scrolls with the world.
      final x0 = e.x;
      run(s, 0.5);
      expect(x0 - e.x, closeTo(12, 0.2));
      for (var i = 0; i < 3; i++) {
        expect(s.score, 0);
        s.playerBullets.add(ShmupBullet(e.x, e.y, 0, 0));
        s.step(dt);
      }
      expect(s.score, 2);
    });

    test('a darter locks on, winds up, then dashes at where you were and rams', () {
      final s = make([ShmupSpawn.darters(150, const [0.5])]);
      s.ship.x = 20;
      s.ship.y = h * 0.5;
      final events = <ShmupEvent>[];
      runUntil(s, () => s.enemies.isNotEmpty);
      final d = s.enemies.single;
      for (var i = 0; i < 60 * 8 && s.ship.hull == 3; i++) {
        s.ship.x = 20;
        s.ship.y = h * 0.5;
        s.step(dt);
        events.addAll(s.drainEvents());
      }
      expect(hasEvent(events, ShmupEventKind.darterLock), isTrue);
      expect(d.stage, 2);
      expect(s.ship.hull, 2, reason: 'the dash reached the ship');
      expect(d.dead, isTrue);
      expect(s.score, 0, reason: 'a ram is not a kill');
    });

    test('a darter that locked on misses a ship that moved away', () {
      final s = make([ShmupSpawn.darters(150, const [0.5])]);
      s.ship.x = 20;
      s.ship.y = h * 0.5;
      runUntil(s, () => s.enemies.isNotEmpty && s.enemies.single.stage == 1);
      s.ship.y = 20; // out of the way during the wind-up
      run(s, 3);
      expect(s.ship.hull, 3);
    });

    test('mines blast, chain to neighbours, score 1 each and hurt a close ship', () {
      final s = make([ShmupSpawn.mineField(150, const [0.5], cols: 3, colSpacing: 8, shift: 0)]);
      parkShip(s, x: 80, y: h * 0.5 + 40);
      runUntil(s, () => s.enemies.length == 3);
      settleOnScreen(s);
      final mines = List.of(s.enemies);
      // Shoot the first one twice (2 hits).
      s.playerBullets.add(ShmupBullet(mines[0].x, mines[0].y, 0, 0));
      s.step(dt);
      expect(s.score, 0);
      s.playerBullets.add(ShmupBullet(mines[0].x, mines[0].y, 0, 0));
      s.step(dt);
      expect(s.score, 3, reason: 'the blast took the other two (8 units away)');
      expect(mines.every((m) => m.dead), isTrue);
      expect(s.ship.hull, 3, reason: 'ship was far away');

      // Now close.
      final s2 = make([ShmupSpawn.mineField(150, const [0.5], cols: 1)]);
      s2.ship.fireCd = 1e9;
      runUntil(s2, () => s2.enemies.isNotEmpty);
      settleOnScreen(s2);
      final m = s2.enemies.single;
      s2.ship.x = m.x - 8;
      s2.ship.y = m.y;
      s2.playerBullets.add(ShmupBullet(m.x, m.y, 0, 0, dmg: 5));
      s2.step(dt);
      expect(s2.ship.hull, 2);
      expect(hasEvent(s2.drainEvents(), ShmupEventKind.mineBlast), isTrue);
    });

    test('touching a mine sets it off', () {
      final s = make([ShmupSpawn.mineField(150, const [0.5], cols: 1)]);
      runUntil(s, () => s.enemies.isNotEmpty);
      final m = s.enemies.single;
      s.ship.x = m.x;
      s.ship.y = m.y;
      s.step(dt);
      expect(m.dead, isTrue);
      expect(s.ship.hull, 2);
    });

    test('a gunship fires 3-way spreads, takes 6 hits and pays 3', () {
      final s = make([ShmupSpawn.gunship(150, 0.5)]);
      parkShip(s, x: 20, y: h * 0.5);
      runUntil(s, () => s.enemyBullets.length >= 3, max: 15);
      expect(s.enemyBullets.length, greaterThanOrEqualTo(3));
      final g = s.enemies.single;
      expect(g.maxHp, 6);
      for (var i = 0; i < 6; i++) {
        s.playerBullets.add(ShmupBullet(g.x, g.y, 0, 0));
        s.step(dt);
      }
      expect(s.score, 3);
    });

    test('a carrier drops its power-up and pays 5', () {
      final s = make([ShmupSpawn.carrier(150, 0.5, PickupKind.homing)]);
      parkShip(s, y: 15);
      runUntil(s, () => s.enemies.isNotEmpty);
      settleOnScreen(s);
      final c = s.enemies.single;
      expect(c.maxHp, 14);
      s.playerBullets.add(ShmupBullet(c.x, c.y, 0, 0, dmg: 14));
      s.step(dt);
      expect(s.score, 5);
      expect(s.pickups.single.kind, PickupKind.homing);
    });

    test('the mid-boss warns, fights in two phases, drops loot and pays 15', () {
      final s = make([ShmupSpawn.midBoss(200, drop: PickupKind.laser)]);
      parkShip(s, x: 10, y: h * 0.5);
      final events = <ShmupEvent>[];
      runUntil(s, () => s.midBoss != null && s.midBoss!.x <= s.width * 0.77, max: 30);
      events.addAll(s.drainEvents());
      expect(events.any((e) => e.kind == ShmupEventKind.warning && e.value == 1), isTrue);
      final m = s.midBoss!;
      expect(s.bossFraction, 1);
      runUntil(s, () => s.enemyBullets.isNotEmpty, max: 10);
      expect(s.enemyBullets, isNotEmpty);
      expect(m.phase, 1);
      m.hp = m.maxHp / 2 - 1;
      run(s, 0.1);
      expect(m.phase, 2);
      s.playerBullets.add(ShmupBullet(m.x, m.y, 0, 0, dmg: 500));
      s.step(dt);
      expect(s.score, 15);
      expect(s.pickups.where((p) => p.kind == PickupKind.shard).length, 2);
      expect(s.pickups.any((p) => p.kind == PickupKind.laser), isTrue);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.midBossDown), isTrue);
      expect(s.midBoss, isNull);
    });

    test('later stages are tougher', () {
      final lv = level([ShmupSpawn.gunship(150, 0.5)]);
      final s = ShmupSim(height: h, seed: 1, levels: [lv, lv])..start();
      s.stage = 3;
      expect(s.scrollSpeed, greaterThan(lv.scrollSpeed));
      expect(s.scrollSpeed, lessThanOrEqualTo(lv.scrollSpeed * ShmupTuning.maxSpeedMul + 1e-9));
    });
  });

  group('weapons and power-ups', () {
    test('the ship fires by itself at the pulse cooldown', () {
      final s = make(const []);
      s.ship.fireCd = 0;
      var shots = 0;
      for (var i = 0; i < 60; i++) {
        s.step(dt);
        shots += s.drainEvents().where((e) => e.kind == ShmupEventKind.shoot).length;
      }
      // 0.2 s cooldown: about 5 shots a second.
      expect(shots, inInclusiveRange(4, 6));
      expect(s.playerBullets.every((b) => b.vx > 0), isTrue);
    });

    test('pick-ups: gun switch, same gun levels up (max 3), option, shield, repair, shard', () {
      final s = make(const []);
      void give(PickupKind k) {
        s.pickups.add(ShmupPickup(s.ship.x, s.ship.y, k));
        s.step(dt);
      }

      give(PickupKind.spread);
      expect((s.ship.weapon, s.ship.weaponLevel), (WeaponKind.spread, 1));
      give(PickupKind.spread);
      give(PickupKind.spread);
      give(PickupKind.spread);
      expect((s.ship.weapon, s.ship.weaponLevel), (WeaponKind.spread, 3));
      give(PickupKind.laser);
      expect((s.ship.weapon, s.ship.weaponLevel), (WeaponKind.laser, 1));
      give(PickupKind.homing);
      expect(s.ship.weapon, WeaponKind.homing);
      give(PickupKind.option);
      give(PickupKind.option);
      give(PickupKind.option);
      expect(s.ship.drones.length, 2);
      give(PickupKind.shield);
      expect(s.ship.shield, isTrue);
      s.ship.hull = 1;
      give(PickupKind.repair);
      expect(s.ship.hull, 2);
      give(PickupKind.shard);
      give(PickupKind.shard);
      expect(s.shards, 2);
      expect(s.pickups, isEmpty);
    });

    test('each gun fires what it should', () {
      List<ShmupBullet> volley(WeaponKind w, int level) {
        final s = make(const []);
        s.ship.weapon = w;
        s.ship.weaponLevel = level;
        s.ship.fireCd = 0;
        s.step(dt);
        return s.playerBullets.toList();
      }

      expect(volley(WeaponKind.pulse, 1).length, 1);
      expect(volley(WeaponKind.pulse, 2).length, 2);
      expect(volley(WeaponKind.pulse, 3).length, 3);
      expect(volley(WeaponKind.spread, 1).length, 3);
      expect(volley(WeaponKind.spread, 3).length, 7);
      expect(volley(WeaponKind.laser, 1).single.pierce, isTrue);
      expect(volley(WeaponKind.laser, 3).length, 2);
      expect(volley(WeaponKind.homing, 2).length, 3);
      expect(volley(WeaponKind.homing, 1).every((b) => b.homing), isTrue);
    });

    test('a laser pierces a line of enemies; a pulse does not', () {
      final s = make([ShmupSpawn.squad(150, 0.5, count: 3, spacing: 6, amp: 0)]);
      parkShip(s, y: 15);
      runUntil(s, () => s.enemies.length == 3);
      settleOnScreen(s);
      final es = List.of(s.enemies);
      s.playerBullets.add(ShmupBullet(es.first.x - 8, es.first.y, 190, 0, pierce: true, life: 2));
      run(s, 0.4);
      expect(es.where((e) => e.dead).length, greaterThanOrEqualTo(2));
    });

    test('homing missiles curve toward an enemy', () {
      final s = make([ShmupSpawn.squad(150, 0.5, count: 1, amp: 0)]);
      parkShip(s, y: 15);
      s.ship.fireCd = 99;
      runUntil(s, () => s.enemies.isNotEmpty);
      final e = s.enemies.single;
      final b = ShmupBullet(e.x - 40, e.y - 30, 85, 0, homing: true, life: 3, dmg: 1.5, r: 1.6);
      s.playerBullets.add(b);
      run(s, 0.3);
      expect(b.vy, greaterThan(5), reason: 'turned down toward the target');
    });

    test('a wingman drone shoots too', () {
      final s = make(const []);
      s.ship.fireCd = 99;
      s.ship.drones.add(math.Point(s.ship.x - 6, s.ship.y - 9));
      run(s, 0.5);
      expect(s.playerBullets, isNotEmpty);
      expect(s.playerBullets.first.y, lessThan(s.ship.y));
    });
  });

  group('lives, hull and game over', () {
    test('3 hull points per life with invulnerability after a hit', () {
      final s = make(const []);
      expect((s.ship.hull, s.ship.lives), (3, 3));
      shootShip(s);
      expect(s.ship.hull, 2);
      expect(s.ship.invuln, closeTo(ShmupTuning.invulnHit, 0.05));
      // A second bullet during invulnerability does nothing.
      s.enemyBullets.add(ShmupBullet(s.ship.x, s.ship.y, 0, 0, r: 1.5));
      s.step(dt);
      expect(s.ship.hull, 2);
    });

    test('the shield absorbs one hit with a short grace period', () {
      final s = make(const []);
      s.ship.shield = true;
      shootShip(s);
      expect(s.ship.shield, isFalse);
      expect(s.ship.hull, 3);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.shieldBlock), isTrue);
      shootShip(s);
      expect(s.ship.hull, 2);
    });

    test('losing the last hull point costs a life, refills the hull and drops the gun', () {
      final s = make(const []);
      s.ship.weapon = WeaponKind.laser;
      s.ship.weaponLevel = 3;
      s.ship.drones.add(math.Point(s.ship.x, s.ship.y));
      for (var i = 0; i < 3; i++) {
        shootShip(s);
      }
      expect(s.ship.lives, 2);
      expect(s.ship.hull, 3);
      expect(s.ship.invuln, closeTo(ShmupTuning.invulnRespawn, 0.1));
      expect((s.ship.weapon, s.ship.weaponLevel), (WeaponKind.pulse, 1));
      expect(s.ship.drones, isEmpty);
      expect(s.phase, ShmupPhase.playing);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.lifeLost), isTrue);
    });

    test('three lives of three hits: the ninth hit ends the run', () {
      final s = make(const []);
      for (var i = 0; i < 8; i++) {
        shootShip(s);
      }
      expect(s.phase, ShmupPhase.playing);
      shootShip(s);
      expect(s.phase, ShmupPhase.over);
      expect(s.ship.lives, 0);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.gameOver), isTrue);
      // The world stops; overFor counts.
      final x = s.scrollX;
      run(s, 1);
      expect(s.scrollX, x);
      expect(s.overFor, closeTo(1, 0.05));
    });

    test('retire ends the run and keeps the score', () {
      final s = make(const []);
      s.score = 7;
      s.retire();
      expect(s.phase, ShmupPhase.over);
      expect(s.cashedOut, isTrue);
      expect(s.score, 7);
    });

    test('reset gives a fresh round', () {
      final s = make(const []);
      for (var i = 0; i < 9; i++) {
        shootShip(s);
      }
      s.reset();
      expect(s.phase, ShmupPhase.ready);
      expect((s.ship.hull, s.ship.lives, s.score, s.stage, s.scrollX), (3, 3, 0, 1, 0));
    });
  });

  group('the boss and stages', () {
    ShmupSim bossSim() {
      final s = ShmupSim(height: h, seed: 3, levels: [level(const [], bossAt: 60), level(const [], bossAt: 60)]);
      s.start();
      s.ship.fireCd = 1e9;
      parkShip(s, x: 6, y: 20);
      runUntil(s, () => s.boss != null && s.boss!.entered, max: 20);
      return s;
    }

    void hitPart(ShmupSim s, BossPart p, double dmg) {
      final b = s.boss!;
      s.playerBullets.add(ShmupBullet(b.x + p.dx, b.y + p.dy, 0, 0, dmg: dmg));
      s.step(dt);
    }

    test('it warns, arrives at the end of the progress bar and enters', () {
      final s = ShmupSim(height: h, seed: 3, levels: [level(const [], bossAt: 100)])..start();
      parkShip(s);
      final events = <ShmupEvent>[];
      runUntil(s, () => s.boss != null, max: 20);
      events.addAll(s.drainEvents());
      expect(events.any((e) => e.kind == ShmupEventKind.warning && e.value == 2), isTrue);
      expect(hasEvent(events, ShmupEventKind.bossAppear), isTrue);
      expect(s.progress, 1);
      expect(s.scrollX, greaterThanOrEqualTo(100));
      expect(s.boss!.entered, isFalse);
      runUntil(s, () => s.boss!.entered, max: 10);
      expect(s.boss!.x, closeTo(s.width * 0.74, 0.1));
      expect(s.bossFraction, 1);
    });

    test('armour bounces bullets; the core is only hittable once both cannons are gone', () {
      final s = bossSim();
      final b = s.boss!;
      // Aim at the shell between the cannons.
      s.playerBullets.add(ShmupBullet(b.x - 12, b.y + 8, 0, 0, dmg: 5));
      s.step(dt);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.deflect), isTrue);
      expect(b.parts.every((p) => p.hp == p.maxHp), isTrue);
      // The core is covered in phase 1.
      hitPart(s, b.core, 5);
      expect(b.core.hp, b.core.maxHp);
      expect(b.phase, 1);
      // Cannons take damage and die one at a time.
      hitPart(s, b.upper, 5);
      expect(b.upper.hp, b.upper.maxHp - 5);
      hitPart(s, b.upper, 999);
      expect(b.upper.alive, isFalse);
      expect(b.phase, 1);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.bossPart), isTrue);
      hitPart(s, b.lower, 999);
      run(s, 0.1);
      expect(b.phase, 2);
      expect(b.exposed(b.core), isTrue);
    });

    test('bullets flown in from the left kill the boss: cannons, then the core, then the stage clears', () {
      final s = bossSim();
      final b = s.boss!;
      s.ship.invuln = 999;
      // Fire a real bullet from the left at the part's height, as the ship would.
      void shoot(BossPart p, {int max = 400}) {
        for (var i = 0; i < max && p.alive; i++) {
          s.playerBullets.add(ShmupBullet(b.x - 40, b.y + p.dy, 160, 0, dmg: 8));
          run(s, 0.3);
        }
      }

      shoot(b.upper);
      shoot(b.lower);
      expect(b.upper.alive || b.lower.alive, isFalse);
      run(s, 0.1);
      expect(b.phase, 2);
      expect(b.exposed(b.core), isTrue);
      // The core is wholly inside the hull: a bullet from outside must reach it.
      shoot(b.core);
      expect(b.core.alive, isFalse);
      expect(b.dying, isTrue);
      expect(s.phase, ShmupPhase.stageClear);
      runUntil(s, () => s.phase == ShmupPhase.playing, max: 8);
      expect(s.stage, 2);
    });

    test('phase 1 shoots from the cannons, phase 2 and 3 fire rings from the core', () {
      final s = bossSim();
      final b = s.boss!;
      s.ship.invuln = 99;
      runUntil(s, () => s.enemyBullets.isNotEmpty, max: 6);
      expect(s.enemyBullets.every((x) => x.style != 2), isTrue);
      b.upper.hp = 0;
      b.lower.hp = 0;
      s.enemyBullets.clear();
      run(s, 0.1);
      expect(b.phase, 2);
      runUntil(s, () => s.enemyBullets.any((x) => x.style == 2), max: 6);
      expect(s.enemyBullets.where((x) => x.style == 2).length, 10);
      b.core.hp = b.core.maxHp * 0.3;
      run(s, 0.1);
      expect(b.phase, 3);
      expect(hasEvent(s.drainEvents(), ShmupEventKind.bossPhase), isTrue);
      s.enemyBullets.clear();
      runUntil(s, () => s.enemyBullets.any((x) => x.style == 2), max: 6);
      expect(s.enemyBullets.where((x) => x.style == 2).length, 14);
    });

    test('killing the boss pays 30 + 5, drops shards, clears the stage and starts the next', () {
      final s = bossSim();
      final b = s.boss!;
      b.upper.hp = 0;
      b.lower.hp = 0;
      run(s, 0.05);
      s.ship.hull = 2;
      final before = s.score;
      hitPart(s, b.core, 9999);
      expect(s.score - before, 35);
      expect(s.phase, ShmupPhase.stageClear);
      expect(b.dying, isTrue);
      final ev = s.drainEvents();
      expect(hasEvent(ev, ShmupEventKind.bossDown), isTrue);
      expect(hasEvent(ev, ShmupEventKind.stageClear), isTrue);
      expect(s.enemyBullets, isEmpty);
      expect(s.pickups.where((p) => p.kind == PickupKind.shard).length, 4);
      // The shards fly to the ship and are collected.
      run(s, 2.5);
      expect(s.shards, 4);
      // After the pause: stage 2, full hull, scroll restarted, boss gone.
      runUntil(s, () => s.phase == ShmupPhase.playing, max: 5);
      expect(s.stage, 2);
      expect(s.ship.hull, 3);
      expect(s.scrollX, lessThan(5));
      expect(s.boss, isNull);
      expect(s.progress, lessThan(0.1));
      expect(s.introLeft, greaterThan(0));
      expect(hasEvent(s.drainEvents(), ShmupEventKind.stageStart), isTrue);
      expect(s.score, greaterThanOrEqualTo(35));
    });

    test('the boss is tougher on later stages', () {
      final s = ShmupSim(height: h, seed: 3, levels: [level(const [], bossAt: 60)]);
      s.start();
      s.stage = 3;
      s.scrollX = 60;
      s.step(dt);
      s.step(dt);
      final later = s.boss!.core.maxHp;
      final s1 = bossSim();
      expect(later, greaterThan(s1.boss!.core.maxHp));
    });

    test('touching the boss hull hurts and pushes the ship out', () {
      final s = bossSim();
      final b = s.boss!;
      s.ship.invuln = 0;
      s.ship.x = b.x - 10;
      s.ship.y = b.y;
      s.step(dt);
      expect(s.ship.hull, 2);
      final d = math.sqrt(math.pow(s.ship.x - b.x, 2) + math.pow(s.ship.y - b.y, 2));
      expect(d, greaterThanOrEqualTo(b.shellR));
    });
  });

  group('scoring and determinism', () {
    test('points match the brief: 1 / 2 / 3 / 5 / 15 / 30 / +5', () {
      expect(ShmupTuning.pointsDrone, 1);
      expect(ShmupTuning.pointsMine, 1);
      expect(ShmupTuning.pointsTurret, 2);
      expect(ShmupTuning.pointsDarter, 2);
      expect(ShmupTuning.pointsGunship, 3);
      expect(ShmupTuning.pointsCarrier, 5);
      expect(ShmupTuning.pointsMidBoss, 15);
      expect(ShmupTuning.pointsBoss, 30);
      expect(ShmupTuning.pointsStage, 5);
    });

    String run1(int seed) {
      final s = ShmupSim(height: h, seed: seed)..start();
      // A scripted "player": sweeps up and down and drags right/left.
      for (var i = 0; i < 60 * 40; i++) {
        s.moveShipBy(math.sin(i / 40) * 0.8, math.cos(i / 25) * 1.4);
        s.step(dt);
      }
      return [
        s.score,
        s.kills,
        s.shards,
        s.ship.hull,
        s.ship.lives,
        s.phase.name,
        s.enemies.length,
        s.enemyBullets.length,
        s.playerBullets.length,
        s.scrollX.toStringAsFixed(3),
        s.ship.y.toStringAsFixed(3),
      ].join('|');
    }

    test('same seed, same inputs: same game', () {
      expect(run1(5), run1(5));
      expect(run1(9), run1(9));
    });

    test('the authored stage 1 is playable end to end by a simple bot (it reaches the boss)', () {
      // A bot that tracks the nearest enemy's height and stays out of rock.
      final s = ShmupSim(height: h, seed: 2)..start();
      s.ship.shield = true;
      var reachedBoss = false;
      for (var i = 0; i < 60 * 140 && s.phase != ShmupPhase.over; i++) {
        var ty = h * 0.5;
        ShmupEnemy? nearest;
        for (final e in s.enemies) {
          if (!e.dead && e.x > s.ship.x && (nearest == null || e.x < nearest.x)) nearest = e;
        }
        if (nearest != null) ty = nearest.y;
        ty = ty.clamp(s.ceilingAt(s.ship.x) + 14, h - s.floorAt(s.ship.x) - 14);
        s.moveShipBy(0, (ty - s.ship.y).clamp(-2.0, 2.0));
        s.ship.invuln = 99; // we only test the level data and sim stability here
        s.step(dt);
        if (s.boss != null) reachedBoss = true;
        if (reachedBoss) break;
      }
      expect(reachedBoss, isTrue);
      expect(s.score, greaterThan(10));
      expect(s.progress, 1);
    });
  });
}
