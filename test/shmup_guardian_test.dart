// A1 verification: the Rift Runner guardian must be beatable (real bullets,
// no placed hits) and must still be armoured while a cannon lives.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/shmup/shmup_level.dart';
import 'package:novabolt/arcade/shmup/shmup_levels.dart';
import 'package:novabolt/arcade/shmup/shmup_sim.dart';

const dt = 1 / 60;
const h = 216.0;

ShmupLevel lvl(int style) => ShmupLevel(
      name: 't',
      terrain: (TerrainBuilder(ceil: 0.05, floor: 0.05)..flat(6000)).build(),
      spawns: const [],
      bossAt: 60,
      bossStyle: style,
    );

/// A sim with the boss arrived. [stages] guardians in a row.
ShmupSim bossSim({int stages = 1, int seed = 3}) {
  final s = ShmupSim(
      height: h, seed: seed, levels: [for (var i = 0; i < stages; i++) lvl(i % 4)]);
  s.start();
  s.ship.fireCd = 1e9;
  s.ship.x = 6;
  s.ship.y = 20;
  _until(s, () => s.boss != null && s.boss!.entered, 20);
  return s;
}

void _until(ShmupSim s, bool Function() c, double max) {
  for (var i = 0; i < max * 60 && !c(); i++) {
    s.step(dt);
  }
}

void kill(BossPart p) => p.hp = 0;

/// Bot ship: sits left of the boss and lines up with a living guard, else the core.
void aim(ShmupSim s) {
  final b = s.boss!;
  final t = b.guards.firstWhere((g) => g.alive, orElse: () => b.core);
  s.ship.invuln = 999;
  s.ship.x = b.x - 70;
  s.ship.y = b.y + t.dy;
  s.ship.fireCd = 0;
}

/// A real bullet fired at the core from [deg] degrees around the boss.
bool fireAtCore(ShmupSim s, double deg, {double dmg = 4, bool pierce = false}) {
  final b = s.boss!;
  final cx = b.x + b.core.dx, cy = b.y + b.core.dy;
  final a = deg * math.pi / 180;
  const dist = 30.0, speed = 300.0; // fast, so the moving boss barely moves meanwhile
  final x = cx + math.cos(a) * dist, y = cy + math.sin(a) * dist;
  if (x < 0 || x > s.width || y < 0 || y > s.height) return false; // can't start off-screen
  s.playerBullets.add(ShmupBullet(x, y, -math.cos(a) * speed, -math.sin(a) * speed,
      dmg: dmg, pierce: pierce, life: 2));
  return true;
}

void main() {
  test('shell deflects core-aimed shots from every angle while BOTH cannons live', () {
    final s = bossSim();
    final b = s.boss!;
    s.ship.invuln = 999;
    for (var deg = 0; deg < 360; deg += 15) {
      fireAtCore(s, deg.toDouble());
    }
    for (var i = 0; i < 40; i++) {
      s.step(dt);
    }
    expect(b.core.hp, b.core.maxHp);
    expect(b.phase, 1);
    expect(b.dying, isFalse);
  });

  for (final dead in ['upper', 'lower']) {
    test('shell still deflects with only the $dead cannon dead', () {
      final s = bossSim();
      final b = s.boss!;
      s.ship.invuln = 999;
      kill(dead == 'upper' ? b.upper : b.lower);
      expect(b.exposed(b.core), isFalse);
      for (var deg = 0; deg < 360; deg += 15) {
        fireAtCore(s, deg.toDouble(), dmg: 1);
      }
      for (var i = 0; i < 40; i++) {
        s.step(dt);
      }
      expect(b.core.hp, b.core.maxHp, reason: 'core must stay covered');
      expect(b.dying, isFalse);
      // The living cannon is still hittable.
      final live = dead == 'upper' ? b.lower : b.upper;
      expect(live.alive, isTrue);
    });
  }

  test('piercing (laser) shots are also stopped by the shell while a cannon lives', () {
    final s = bossSim();
    final b = s.boss!;
    s.ship.invuln = 999;
    kill(b.upper);
    for (var deg = 0; deg < 360; deg += 30) {
      fireAtCore(s, deg.toDouble(), dmg: 1, pierce: true);
    }
    for (var i = 0; i < 40; i++) {
      s.step(dt);
    }
    expect(b.core.hp, b.core.maxHp);
  });

  test('once both cannons are dead, a shot from EVERY angle damages the core', () {
    var fired = 0;
    for (var deg = 0; deg < 360; deg += 10) {
      final s = bossSim();
      final b = s.boss!;
      s.ship.invuln = 999;
      kill(b.upper);
      kill(b.lower);
      for (var i = 0; i < 30; i++) {
        s.step(dt); // let the boss settle (its y eases after the phase change)
      }
      final before = b.core.hp;
      if (!fireAtCore(s, deg.toDouble(), dmg: 4)) continue;
      fired++;
      for (var i = 0; i < 30; i++) {
        s.step(dt);
      }
      expect(b.core.hp, lessThan(before), reason: 'angle $deg never reached the core');
    }
    expect(fired, greaterThan(20)); // most angles are on-screen
  });

  test('a lone cannon-less boss can be killed by a stream of shots from one side', () {
    final s = bossSim();
    final b = s.boss!;
    s.ship.invuln = 999;
    kill(b.upper);
    kill(b.lower);
    for (var i = 0; i < 1200 && !b.dying; i++) {
      final cx = b.x + b.core.dx, cy = b.y + b.core.dy;
      if (i % 6 == 0) s.playerBullets.add(ShmupBullet(cx - 45, cy, 160, 0, dmg: 4, life: 2));
      s.step(dt);
    }
    expect(b.dying, isTrue);
    expect(s.phase, ShmupPhase.stageClear);
  });

  test('the boss cannot die before both cannons are down, however much is fired', () {
    final s = bossSim();
    final b = s.boss!;
    s.ship.invuln = 999;
    kill(b.lower); // one cannon down only
    for (var i = 0; i < 600; i++) {
      for (final deg in <double>[0, 90, 180, 270, 45, 225]) {
        if (i % 10 == 0) fireAtCore(s, deg, dmg: 1);
      }
      s.step(dt);
      expect(b.core.alive, isTrue);
      expect(b.dying, isFalse);
      if (!b.upper.alive) break; // random hits may legitimately finish it
    }
    expect(s.phase, isNot(ShmupPhase.stageClear));
  });

  // Real weapons fired by the ship itself.
  for (final w in WeaponKind.values) {
    for (final lvlN in [1, 3]) {
      test('ship firing ${w.name} L$lvlN from the left beats the guardian and clears the stage', () {
        final s = bossSim();
        final b = s.boss!;
        s.ship.weapon = w;
        s.ship.weaponLevel = lvlN;
        var guard = 0;
        // Cannons die first, never the core while a cannon lives.
        while (s.phase == ShmupPhase.playing && guard++ < 60 * 90) {
          aim(s);
          s.step(dt);
          if (b.upper.alive || b.lower.alive) {
            expect(b.core.hp, b.core.maxHp, reason: 'core hit while a cannon lived');
          }
        }
        expect(b.upper.alive, isFalse);
        expect(b.lower.alive, isFalse);
        expect(b.core.alive, isFalse, reason: '${w.name} L$lvlN never killed the core');
        expect(s.phase, ShmupPhase.stageClear);
      });
    }
  }

  test('stage clear -> next stage starts, across several guardians (all four kinds, rising HP)', () {
    final s = bossSim(stages: 4);
    for (var stage = 1; stage <= 4; stage++) {
      expect(s.stage, stage);
      var guard = 0;
      while (s.phase == ShmupPhase.playing && guard++ < 60 * 120) {
        aim(s);
        s.ship.weapon = WeaponKind.spread;
        s.ship.weaponLevel = 3;
        s.step(dt);
      }
      expect(s.phase, ShmupPhase.stageClear, reason: 'stage $stage did not clear');
      _until(s, () => s.phase == ShmupPhase.playing, 10);
      expect(s.phase, ShmupPhase.playing);
      expect(s.stage, stage + 1);
      if (stage < 4) {
        s.ship.x = 6;
        s.ship.y = 20;
        _until(s, () => s.boss != null && s.boss!.entered && !s.boss!.dying && s.boss!.core.alive, 30);
      }
    }
  });

  test('the real shipped levels still reach a guardian with the standard geometry', () {
    for (final l in ShmupLevels.all) {
      final s = ShmupSim(height: h, seed: 1, levels: [
        ShmupLevel(name: l.name, terrain: l.terrain, spawns: const [], bossAt: 60, bossStyle: l.bossStyle)
      ]);
      s.start();
      s.ship.fireCd = 1e9;
      _until(s, () => s.boss != null && s.boss!.entered, 20);
      final b = s.boss!;
      expect(b.shellR, 24);
      // Core wholly inside the shell (the premise of the fix).
      expect(math.sqrt(b.core.dx * b.core.dx + b.core.dy * b.core.dy) + b.core.r, lessThanOrEqualTo(b.shellR));
    }
  });
}
