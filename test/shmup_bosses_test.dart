// Rift Runner's four guardians (one per stage): each keeps its core covered
// while a guard lives, is beatable with real bullets, and does its own thing
// (the Prism's facets orbit, the Hauler's claws strike along a lit lane and
// its reactor pulls, the Maw's throat is only open while the jaw is).
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/shmup/shmup_level.dart';
import 'package:novabolt/arcade/shmup/shmup_levels.dart';
import 'package:novabolt/arcade/shmup/shmup_sim.dart';

const dt = 1 / 60;
const h = 216.0;

ShmupSim arrive(ShmupBossKind kind, {int seed = 5}) {
  final s = ShmupSim(height: h, seed: seed, levels: [
    ShmupLevel(
      name: 't',
      terrain: (TerrainBuilder(ceil: 0.05, floor: 0.05)..flat(6000)).build(),
      spawns: const [],
      bossAt: 60,
      bossStyle: kind.index,
    ),
  ]);
  s.start();
  s.ship.fireCd = 1e9;
  s.ship.x = 6;
  s.ship.y = 20;
  for (var i = 0; i < 20 * 60 && !(s.boss?.entered ?? false); i++) {
    s.step(dt);
  }
  expect(s.boss?.entered, isTrue);
  expect(s.boss!.kind, kind);
  s.ship.fireCd = 0;
  return s;
}

/// Bot: invulnerable, sits 60 units left of the boss, lines up with the first
/// living guard (else the core) and fires a level-3 spread.
void bot(ShmupSim s) {
  final b = s.boss!;
  final t = b.guards.firstWhere((g) => g.alive, orElse: () => b.core);
  s.ship
    ..invuln = 999
    ..weapon = WeaponKind.spread
    ..weaponLevel = 3
    ..x = math.max(8, b.x - 60)
    ..y = (b.y + t.dy).clamp(6.0, h - 6.0);
}

void main() {
  test('the shipped stages each end with a different guardian', () {
    final kinds = ShmupLevels.all.map((l) => ShmupBossKind.values[l.bossStyle % 4]).toList();
    expect(kinds.length, greaterThanOrEqualTo(4));
    expect(kinds.toSet().length, kinds.length, reason: 'no guardian repeats inside one loop: $kinds');
    expect(ShmupLevels.all.map((l) => l.theme).toSet().length, ShmupLevels.all.length, reason: 'each stage has its own look');
  });

  for (final kind in ShmupBossKind.values) {
    test('${kind.name}: core covered while a guard lives, then beatable with real bullets', () {
      final s = arrive(kind);
      final b = s.boss!;
      var steps = 0;
      var sawPhase3 = false;
      while (s.phase == ShmupPhase.playing && steps++ < 60 * 150) {
        bot(s);
        s.step(dt);
        if (!b.guardsDown) expect(b.core.hp, b.core.maxHp, reason: 'core hit while a guard lived');
        if (b.phase == 3) sawPhase3 = true;
      }
      expect(b.guardsDown, isTrue, reason: 'steps $steps, guards ${b.guards.map((g) => g.hp)}');
      expect(sawPhase3, isTrue, reason: 'steps $steps core ${b.core.hp}/${b.core.maxHp} phase ${b.phase}');
      expect(b.core.alive, isFalse, reason: '${kind.name} never died');
      expect(s.phase, ShmupPhase.stageClear);
    });
  }

  test('prism: the facets orbit the heart just outside the shell', () {
    final s = arrive(ShmupBossKind.prism);
    final b = s.boss!;
    final before = [for (final g in b.guards) math.atan2(g.dy, g.dx)];
    for (var i = 0; i < 60; i++) {
      s.step(dt);
    }
    for (var i = 0; i < b.guards.length; i++) {
      final g = b.guards[i];
      expect(math.sqrt(g.dx * g.dx + g.dy * g.dy), greaterThan(b.shellR));
      expect(math.atan2(g.dy, g.dx), isNot(closeTo(before[i], 0.2)));
    }
  });

  test('prism: once the facets break, the heart sprays beam arms in bursts', () {
    final s = arrive(ShmupBossKind.prism);
    final b = s.boss!;
    s.ship.invuln = 999;
    for (final g in b.guards) {
      g.hp = 0;
    }
    var streamed = false, rested = false;
    for (var i = 0; i < 60 * 8; i++) {
      s.step(dt);
      if (b.streaming) streamed = true;
      if (streamed && !b.streaming) rested = true;
    }
    expect(b.phase, 2);
    expect(streamed && rested, isTrue, reason: 'streamed $streamed, rested $rested');
    expect(s.enemyBullets.where((e) => e.style == 2), isNotEmpty);
  });

  test('hauler: a claw lights a lane at the ship, strikes along it and comes back', () {
    final s = arrive(ShmupBossKind.hauler);
    final b = s.boss!;
    s.ship
      ..invuln = 999
      ..y = 60;
    BossPart? c;
    for (var i = 0; i < 60 * 4 && c == null; i++) {
      s.step(dt);
      for (final g in b.guards) {
        if (g.state == 1) c = g;
      }
    }
    expect(c, isNotNull, reason: 'no claw ever lit a lane');
    expect(c!.laneY, closeTo(60, 0.01));
    var reachedLeft = false;
    for (var i = 0; i < 60 * 4; i++) {
      s.ship.y = 150; // dodge: the lane does not follow the ship
      s.step(dt);
      if (c.state == 2) expect(b.y + c.dy, closeTo(60, 0.01));
      if (b.x + c.dx < 12) reachedLeft = true;
      if (reachedLeft && c.state == 0) break;
    }
    expect(reachedLeft, isTrue);
    expect(c.state, 0);
    expect(c.dx, closeTo(c.homeDx, 0.01));
  });

  test('hauler: a claw touching the ship hurts it', () {
    final s = arrive(ShmupBossKind.hauler);
    final b = s.boss!;
    final c = b.upper;
    s.ship
      ..invuln = 0
      ..x = b.x + c.dx
      ..y = b.y + c.dy;
    final hull = s.ship.hull;
    s.step(dt);
    expect(s.ship.hull, hull - 1);
  });

  test('hauler: with the claws gone the reactor pulls the ship in', () {
    final s = arrive(ShmupBossKind.hauler);
    final b = s.boss!;
    for (final g in b.guards) {
      g.hp = 0;
    }
    s.step(dt);
    expect(b.phase, 2);
    s.ship
      ..invuln = 999
      ..x = 20
      ..y = b.y;
    final x0 = s.ship.x;
    for (var i = 0; i < 60; i++) {
      s.step(dt);
    }
    expect(b.pull, greaterThan(0.5));
    expect(s.ship.x, greaterThan(x0 + 4));
  });

  test('hauler enraged drops mines', () {
    final s = arrive(ShmupBossKind.hauler);
    final b = s.boss!;
    for (final g in b.guards) {
      g.hp = 0;
    }
    b.core.hp = b.core.maxHp * 0.3;
    s.ship
      ..invuln = 999
      ..x = 8;
    var mines = false;
    for (var i = 0; i < 60 * 6 && !mines; i++) {
      s.ship.x = 8;
      s.step(dt);
      mines = s.enemies.any((e) => e.kind == EnemyKind.mine);
    }
    expect(b.phase, 3);
    expect(mines, isTrue);
  });

  test('maw: the throat only takes damage while the jaw is open', () {
    final s = arrive(ShmupBossKind.maw);
    final b = s.boss!;
    for (final g in b.guards) {
      g.hp = 0;
    }
    s.ship.invuln = 999;
    var hitShut = false, hitOpen = false, sawShut = false, sawOpen = false;
    for (var i = 0; i < 60 * 12; i++) {
      final before = b.core.hp;
      // A point-blank shot at the throat every frame.
      s.playerBullets.add(ShmupBullet(b.x + b.core.dx - 3, b.y + b.core.dy, 300, 0, dmg: 0.01, life: 0.5));
      s.step(dt);
      final open = b.mouth >= 0.6; // what the collision saw this tick
      if (open) {
        sawOpen = true;
      } else {
        sawShut = true;
      }
      if (b.core.hp < before) {
        if (open) {
          hitOpen = true;
        } else {
          hitShut = true;
        }
      }
    }
    expect(sawShut && sawOpen, isTrue);
    expect(hitOpen, isTrue);
    expect(hitShut, isFalse);
  });

  test('maw enraged releases spore drones when the jaw opens', () {
    final s = arrive(ShmupBossKind.maw);
    final b = s.boss!;
    for (final g in b.guards) {
      g.hp = 0;
    }
    b.core.hp = b.core.maxHp * 0.3;
    s.ship.invuln = 999;
    var drones = false;
    for (var i = 0; i < 60 * 8 && !drones; i++) {
      s.step(dt);
      drones = s.enemies.any((e) => e.kind == EnemyKind.drone);
    }
    expect(b.phase, 3);
    expect(drones, isTrue);
  });
}
