import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/assault/assault_enemies.dart';
import 'package:novabolt/arcade/assault/assault_types.dart';
import 'package:novabolt/arcade/assault/assault_weapons.dart';

class FakeWorld implements AssaultWorld {
  @override
  final AssaultPilot pilot = AssaultPilot();
  @override
  final AssaultLevel level = const AssaultLevel(name: 't', width: 200, height: 13, tiles: [], spawns: []);
  @override
  final math.Random rng = math.Random(1);
  @override
  double time = 0;
  @override
  double cameraX = 0;

  /// Floor top is y = 10 everywhere except where [pit] says otherwise.
  bool Function(double x) pit = (x) => false;
  bool Function(double x, double y)? extraSolid;

  final bullets = <AssaultBullet>[];
  final enemies = <AssaultEnemy>[];
  final events = <AssaultEvent>[];

  @override
  bool solidAt(double x, double y) {
    if (extraSolid != null && extraSolid!(x, y)) return true;
    return y >= 10 && !pit(x);
  }

  @override
  bool groundAt(double x, double y) => solidAt(x, y);
  @override
  void addBullet(AssaultBullet b) => bullets.add(b);
  @override
  void addEnemy(AssaultEnemy e) => enemies.add(e);
  @override
  void emit(AssaultEvent e) => events.add(e);

  void run(AssaultEnemy e, double seconds, {void Function()? each}) {
    const dt = 1 / 60;
    for (var t = 0.0; t < seconds; t += dt) {
      time += dt;
      e.update(this, dt);
      each?.call();
    }
  }
}

AssaultEnemy make(String c, double x, [double y = 10]) => createAssaultEnemy(AssaultSpawn(c, x, y))!..awake = true;

void main() {
  group('weapons', () {
    test('blaster', () {
      final w = FakeWorld();
      final wp = assaultWeapon(WeaponKind.blaster);
      expect(identical(wp, assaultWeapon(WeaponKind.blaster)), isTrue);
      wp.fire(w, 5, 5, AimDir.upRight);
      expect(w.bullets.length, 1);
      final b = w.bullets.single;
      expect(b.fromPlayer, isTrue);
      expect(b.damage, 1);
      expect(b.vx, greaterThan(0));
      expect(b.vy, lessThan(0));
      expect(math.sqrt(b.vx * b.vx + b.vy * b.vy), closeTo(20, 1e-9));
      expect(wp.cooldown, closeTo(0.16, 1e-9));
      expect(w.events.single.kind, AssaultEventKind.shoot);
      expect(w.events.single.detail, 'blaster');
      // 3 hp grunt: 3 hits take 2 cooldowns + travel.
      expect(wp.cooldown * 2, lessThan(0.5));
    });

    test('spread fans 5 bolts +-24 deg', () {
      final w = FakeWorld();
      assaultWeapon(WeaponKind.spread).fire(w, 0, 0, AimDir.right);
      expect(w.bullets.length, 5);
      final angles = w.bullets.map((b) => math.atan2(b.vy, b.vx) * 180 / math.pi).toList()..sort();
      expect(angles.first, closeTo(-24, 1e-6));
      expect(angles.last, closeTo(24, 1e-6));
      expect(angles[2], closeTo(0, 1e-6));
      expect(w.bullets.every((b) => b.damage == 0.8), isTrue);
      expect(w.events.length, 1);
    });

    test('laser pierces, rockets splash and accelerate', () {
      final w = FakeWorld();
      assaultWeapon(WeaponKind.laser).fire(w, 0, 0, AimDir.left);
      final l = w.bullets.single;
      expect(l.pierce, isTrue);
      expect(l.damage, 1.4);
      expect(l.vx, lessThan(0));
      final w2 = FakeWorld();
      assaultWeapon(WeaponKind.rockets).fire(w2, 0, 0, AimDir.up);
      final r = w2.bullets.single as AssaultRocket;
      expect(r.splash, closeTo(1.3, 1e-9));
      expect(r.damage, 3);
      expect(r.vy, -8);
      for (var i = 0; i < 120; i++) {
        r.accelerate(1 / 60);
      }
      expect(r.vy, closeTo(-20, 1e-6));
      expect(assaultWeapon(WeaponKind.rockets).cooldown, 0.5);
    });
  });

  group('factory', () {
    test('known chars only', () {
      for (final c in ['g', 'r', 't', 'f', 'B']) {
        expect(createAssaultEnemy(AssaultSpawn(c, 3, 10)), isNotNull);
      }
      expect(createAssaultEnemy(const AssaultSpawn('x', 3, 10)), isNull);
      expect(make('g', 1).score, 1);
      expect(make('t', 1).score, 2);
      expect(make('B', 1).score, 15);
    });
  });

  group('grunt', () {
    test('turns at a ledge and does not fall', () {
      final w = FakeWorld()..pit = (x) => x >= 20;
      w.pilot.x = 500;
      final g = make('g', 18, 10) as AssaultCombatEnemy..facing = 1;
      w.run(g, 6);
      expect(g.dead, isFalse);
      expect(g.x, lessThan(20));
      expect(g.y, 10);
    });

    test('turns at a wall', () {
      final w = FakeWorld()..extraSolid = (x, y) => x >= 20 && y < 10;
      w.pilot.x = 500;
      final g = make('g', 18) as AssaultCombatEnemy..facing = 1;
      w.run(g, 3);
      expect(g.facing, -1);
      expect(g.x, lessThan(20));
    });

    test('telegraphs, then fires an aimed slow shot; not when far', () {
      final w = FakeWorld();
      w.pilot
        ..x = 14
        ..y = 10;
      final g = make('g', 10) as AssaultCombatEnemy;
      var sawTelegraph = false;
      w.run(g, 1.2, each: () {
        if (g.telegraph > 0.2 && w.bullets.isEmpty) sawTelegraph = true;
      });
      expect(sawTelegraph, isTrue);
      expect(w.bullets, isNotEmpty);
      final b = w.bullets.first;
      expect(b.fromPlayer, isFalse);
      expect(b.vx, greaterThan(0));
      expect(math.sqrt(b.vx * b.vx + b.vy * b.vy), closeTo(6, 1e-9));
      // Far away: no shot.
      final w2 = FakeWorld();
      w2.pilot
        ..x = 40
        ..y = 10;
      final g2 = make('g', 10);
      w2.run(g2, 5);
      expect(w2.bullets, isEmpty);
    });

    test('dies after 3 hits and emits enemyKilled', () {
      final w = FakeWorld();
      final g = make('g', 10);
      g.onHit(w, 1);
      g.onHit(w, 1);
      expect(g.dead, isFalse);
      g.onHit(w, 1);
      expect(g.dead, isTrue);
      expect(w.events.single.kind, AssaultEventKind.enemyKilled);
      expect(w.events.single.detail, 'grunt');
      g.onHit(w, 1);
      expect(w.events.length, 1);
    });
  });

  group('runner', () {
    test('charges the pilot fast after a short alert', () {
      final w = FakeWorld();
      w.pilot
        ..x = 2
        ..y = 10;
      final r = make('r', 20) as AssaultCombatEnemy;
      w.run(r, 0.2);
      expect(r.x, 20); // still alerting
      w.run(r, 0.8);
      expect(r.state, 'charge');
      expect(r.x, lessThan(20 - 4));
      expect(r.facing, -1);
    });

    test('hops a 1-tile step but is stopped by a 3-tile wall', () {
      final w = FakeWorld()..extraSolid = (x, y) => x >= 15 && x < 16 && y >= 9;
      w.pilot
        ..x = 0
        ..y = 10;
      final r = make('r', 18);
      w.run(r, 1.5);
      expect(r.x, lessThan(15));
      final w2 = FakeWorld()..extraSolid = (x, y) => x >= 15 && x < 16 && y >= 7;
      w2.pilot
        ..x = 0
        ..y = 10;
      final r2 = make('r', 18);
      w2.run(r2, 1.5);
      expect(r2.x, greaterThanOrEqualTo(16));
    });

    test('falls into a pit and dies without a kill event', () {
      final w = FakeWorld()..pit = (x) => x >= 10 && x < 14;
      w.pilot
        ..x = 30
        ..y = 10;
      final r = make('r', 8) as AssaultRunner;
      w.run(r, 3);
      expect(r.dead, isTrue);
      expect(r.fellInPit, isTrue);
      expect(w.events, isEmpty);
    });
  });

  group('turret', () {
    test('does not fire out of view; telegraphs then bursts 3 in view', () {
      final w = FakeWorld();
      w.pilot
        ..x = 8
        ..y = 10;
      final t = make('t', 60) as AssaultTurret;
      w.run(t, 6);
      expect(w.bullets, isEmpty);
      expect(t.contactDamage, isFalse);

      final w2 = FakeWorld();
      w2.pilot
        ..x = 4
        ..y = 10;
      final t2 = make('t', 9) as AssaultTurret;
      var teleBeforeFire = false;
      w2.run(t2, 3, each: () {
        if (t2.telegraph > 0.5 && w2.bullets.isEmpty) teleBeforeFire = true;
      });
      expect(teleBeforeFire, isTrue);
      expect(w2.bullets.length, 3);
      expect(w2.bullets.every((b) => b.vx < 0), isTrue);
      expect(t2.aimX, lessThan(-0.9));
    });
  });

  group('flyer', () {
    test('hovers, swoops at the pilot and returns', () {
      final w = FakeWorld()..cameraX = 0;
      w.pilot
        ..x = 5
        ..y = 10;
      final f = make('f', 5, 5) as AssaultFlyer;
      final states = <String>{};
      var lowest = 0.0;
      w.run(f, 8, each: () {
        states.add(f.state);
        lowest = math.max(lowest, f.y);
      });
      expect(states, containsAll(['hover', 'wind', 'swoop', 'return']));
      expect(lowest, greaterThan(8)); // dove towards the pilot
      expect(f.dead, isFalse);
      expect(f.contactDamage, isTrue);
      w.run(f, 4);
      expect(f.y, lessThan(7)); // back up near home
    });
  });

  group('boss', () {
    test('three phases, slam shockwaves, flyers in phase 3, death event', () {
      final w = FakeWorld();
      w.pilot
        ..x = 4
        ..y = 10;
      final b = make('B', 14) as AssaultBoss;
      expect(b.phase, 1);
      expect(b.maxHp, 60);
      // Keep the pilot alive and invulnerable to the bullets (nothing hits here).
      w.run(b, 4);
      expect(w.bullets, isNotEmpty);
      expect(b.contactDamage, isTrue);

      b.hp = 60 * 0.6;
      w.run(b, 0.1);
      expect(b.phase, 2);
      expect(b.state, 'roar');
      w.bullets.clear();
      var slammed = false;
      w.run(b, 8, each: () {
        if (w.bullets.any((x) => x.vy == 0 && x.radius > 0.3)) slammed = true;
      });
      expect(slammed, isTrue);
      expect(w.events.any((e) => e.kind == AssaultEventKind.explosion), isTrue);
      expect(w.enemies, isEmpty);

      b.hp = 60 * 0.3;
      w.run(b, 0.1);
      expect(b.phase, 3);
      w.run(b, 6);
      expect(w.enemies.length, 2);
      expect(w.enemies.every((e) => e.kind == 'flyer' && e.awake), isTrue);

      w.events.clear();
      b.onHit(w, 1000);
      expect(b.dead, isTrue);
      expect(w.events.first.detail, 'boss');
      expect(w.events.first.kind, AssaultEventKind.enemyKilled);
    });
  });
}
