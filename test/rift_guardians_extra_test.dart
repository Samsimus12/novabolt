// Rift Runner's four guardians, checked independently of the designer's own
// tests (test/shmup_bosses_test.dart): weakest gun, every stage's real
// multipliers, phases in order, longest stall with a ship firing at the right
// target, field/arena fit, the Hauler's pull and the contact rules.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/shmup/shmup_level.dart';
import 'package:novabolt/arcade/shmup/shmup_levels.dart';
import 'package:novabolt/arcade/shmup/shmup_overlays.dart';
import 'package:novabolt/arcade/shmup/shmup_sim.dart';

const dt = 1 / 60;
const h = 216.0;

/// A sim sitting on the real stage [stageNo]'s open boss arena, boss just
/// arrived. Uses that stage's terrain and the stage number's real HP scaling.
ShmupSim arena(int stageNo, {int seed = 4}) {
  final lv = ShmupLevels.all[(stageNo - 1) % ShmupLevels.all.length];
  final s = ShmupSim(height: h, seed: seed, levels: [
    ShmupLevel(
      name: lv.name,
      terrain: lv.terrain,
      spawns: const [],
      bossAt: lv.bossAt,
      scrollSpeed: lv.scrollSpeed,
      theme: lv.theme,
      bossStyle: lv.bossStyle,
    ),
  ]);
  s.stage = stageNo;
  s.start();
  s.scrollX = lv.bossAt - 1;
  s.ship
    ..x = 6
    ..y = h / 2
    ..fireCd = 1e9
    ..invuln = 1e9;
  for (var i = 0; i < 60 * 20 && !(s.boss?.entered ?? false); i++) {
    s.step(dt);
  }
  expect(s.boss?.entered, isTrue, reason: 'the boss never arrived');
  s.ship.fireCd = 0;
  return s;
}

/// The ship lines up with the leftmost living guard (the one a bullet from the
/// left can reach), else the core, and fires the weakest gun (pulse level 1).
void aim(ShmupSim s, {double x = 8}) {
  final b = s.boss!;
  BossPart? t;
  for (final g in b.guards) {
    if (!g.alive) continue;
    if (t == null || g.dx < t.dx) t = g;
  }
  t ??= b.core;
  s.ship
    ..invuln = 1e9
    ..weapon = WeaponKind.pulse
    ..weaponLevel = 1
    ..x = x
    ..y = (b.y + t.dy).clamp(6.0, h - 6.0);
}

void main() {
  group('every guardian dies to the weakest gun at every stage multiplier', () {
    for (final kind in ShmupBossKind.values) {
      for (final stageNo in [kind.index + 1, kind.index + 5]) {
        test('${kind.name} at stage $stageNo (pulse level 1, aimed, 6 minutes at most)', () {
          final s = arena(stageNo);
          final b = s.boss!;
          expect(b.kind, kind);
          final seen = <int>[b.phase];
          var lastDamage = 0.0, longestStall = 0.0;
          var hpBefore = b.parts.fold<double>(0, (a, p) => a + p.hp);
          var steps = 0;
          while (s.phase == ShmupPhase.playing && steps++ < 60 * 360) {
            aim(s);
            s.step(dt);
            if (b.phase != seen.last) seen.add(b.phase);
            final hp = b.parts.fold<double>(0, (a, p) => a + p.hp);
            if (hp < hpBefore) lastDamage = s.time;
            hpBefore = hp;
            longestStall = math.max(longestStall, s.time - lastDamage);
          }
          // ignore: avoid_print
          print('${kind.name} stage $stageNo: dead in ${steps ~/ 60}s, phases $seen, longest stretch with no damage ${longestStall.toStringAsFixed(1)}s');
          expect(s.phase, ShmupPhase.stageClear, reason: '${kind.name} survived 6 minutes: ${b.parts.map((p) => p.hp)}');
          expect(seen, [1, 2, 3], reason: 'phases must advance in order, once each');
          // A guard (or the open throat) must always come into reach soon:
          // nothing may stay untouchable for long.
          expect(longestStall, lessThan(14), reason: 'something stayed unhittable for ${longestStall.toStringAsFixed(1)}s');
        });
      }
    }
  });

  group('phases and enrage', () {
    for (final kind in ShmupBossKind.values) {
      test('${kind.name}: all guards down -> phase 2; core under 35% -> phase 3; both exactly once', () {
        final s = arena(kind.index + 1);
        final b = s.boss!;
        final events = <int>[];
        void drain() {
          for (final e in s.drainEvents()) {
            if (e.kind == ShmupEventKind.bossPhase) events.add(e.value);
          }
        }

        for (var i = 0; i < 30; i++) {
          s.step(dt);
        }
        expect(b.phase, 1);
        for (final g in b.guards) {
          g.hp = 0;
        }
        for (var i = 0; i < 10; i++) {
          s.step(dt);
        }
        drain();
        expect(b.phase, 2);
        b.core.hp = b.core.maxHp * 0.35; // at the line (<=)
        s.step(dt);
        drain();
        expect(b.phase, 3);
        for (var i = 0; i < 60 * 5; i++) {
          s.step(dt);
        }
        drain();
        expect(events, [2, 3]);
      });
    }

    test('the core cannot be hurt while any guard lives, for every kind (a bullet at every guard-covered angle)', () {
      for (final kind in ShmupBossKind.values) {
        final s = arena(kind.index + 1);
        final b = s.boss!;
        final hp = b.core.hp;
        // Leave one guard alive; hammer the hull from every height.
        for (var i = 0; i < b.guards.length - 1; i++) {
          b.guards[i].hp = 0;
        }
        for (var y = 6.0; y < h; y += 3) {
          s.playerBullets.add(ShmupBullet(b.x - 30, y, 300, 0, dmg: 5, life: 1.0));
        }
        for (var i = 0; i < 90; i++) {
          s.step(dt);
        }
        expect(b.core.hp, hp, reason: '${kind.name}: core damaged with a guard alive');
        expect(b.phase, 1);
      }
    });
  });

  group('the Maw', () {
    test('the jaw cycles forever: shut 2.4 s, open >= 2.4 s, at most 7 s per cycle (phase 3 too)', () {
      final s = arena(4);
      final b = s.boss!;
      for (final g in b.guards) {
        g.hp = 0;
      }
      s.ship.invuln = 1e9;
      for (final enraged in [false, true]) {
        if (enraged) b.core.hp = b.core.maxHp * 0.3;
        var openStart = -1.0;
        final opens = <double>[], gaps = <double>[];
        var lastClose = s.time;
        var wasOpen = false;
        for (var i = 0; i < 60 * 40; i++) {
          s.step(dt);
          final open = b.mouth >= 0.6;
          if (open && !wasOpen) {
            openStart = s.time;
            gaps.add(s.time - lastClose);
          }
          if (!open && wasOpen) {
            opens.add(s.time - openStart);
            lastClose = s.time;
          }
          wasOpen = open;
        }
        expect(opens.length, greaterThanOrEqualTo(5), reason: 'enraged=$enraged: the jaw stopped cycling');
        expect(opens.reduce(math.min), greaterThan(2.3), reason: 'enraged=$enraged open $opens');
        expect(gaps.skip(1).reduce(math.max), lessThan(4.0), reason: 'enraged=$enraged shut $gaps');
      }
    });

    test('a bullet from the far left reaches the throat while the jaw is open, and is stopped while it is shut', () {
      final s = arena(4);
      final b = s.boss!;
      for (final g in b.guards) {
        g.hp = 0;
      }
      s.ship.invuln = 1e9;
      var through = 0, blocked = 0;
      for (var round = 0; round < 80; round++) {
        for (var i = 0; i < 20; i++) {
          s.step(dt);
        }
        final open = b.mouth >= 0.6;
        final before = b.core.hp;
        s.playerBullets.add(ShmupBullet(2, b.y + b.core.dy, 260, 0, dmg: 0.5, life: 1.2));
        // Flight time to the throat ~0.3 s: the jaw may change meanwhile, so
        // only count the clear-cut cases (open now and still open at the end).
        var openThroughout = open;
        var shutThroughout = !open && b.mouth < 0.3;
        for (var i = 0; i < 24; i++) {
          s.step(dt);
          openThroughout &= b.mouth >= 0.6;
          shutThroughout &= b.mouth < 0.3;
        }
        if (openThroughout && b.core.hp < before) through++;
        if (shutThroughout) {
          blocked++;
          expect(b.core.hp, before, reason: 'damaged through a shut jaw');
        }
      }
      expect(through, greaterThan(3), reason: 'no shot ever reached the open throat');
      expect(blocked, greaterThan(3));
    });
  });

  group('the Hauler', () {
    ShmupSim pulling({double x = 20, double y = 108, bool enraged = false}) {
      final s = arena(3);
      final b = s.boss!;
      for (final g in b.guards) {
        g.hp = 0;
      }
      if (enraged) b.core.hp = b.core.maxHp * 0.3;
      s.step(dt);
      s.ship
        ..invuln = 0
        ..hull = 3
        ..x = x
        ..y = y
        ..fireCd = 1e9;
      return s;
    }

    for (final enraged in [false, true]) {
      test('the pull is escapable from the edges and corners at a gentle 20 u/s drag (enraged: $enraged)', () {
        for (final (x, y) in [(5.0, 22.0), (5.0, 108.0), (5.0, 194.0), (50.0, 24.0), (50.0, 192.0), (98.0, 60.0), (96.0, 30.0), (96.0, 190.0)]) {
          final s = pulling(x: x, y: y, enraged: enraged);
          final b = s.boss!;
          var pulledIn = false;
          for (var i = 0; i < 60 * 12; i++) {
            s.ship.invuln = 1e9; // measure motion only
            // The player drags directly away from the boss at 20 u/s.
            final dx = s.ship.x - b.x, dy = s.ship.y - b.y;
            final d = math.max(0.01, math.sqrt(dx * dx + dy * dy));
            s.moveShipBy(dx / d * (20 * dt), dy / d * (20 * dt));
            s.step(dt);
            expect(s.ship.x.isFinite && s.ship.y.isFinite, isTrue);
            if (dx * dx + dy * dy < math.pow(b.shellR + 3, 2)) pulledIn = true;
          }
          expect(pulledIn, isFalse, reason: 'start ($x,$y) was dragged into the hull even while fleeing at 20 u/s');
        }
      });
    }

    test('an idle ship pressed against the hull loses at most one hull per invulnerability window', () {
      final s = pulling(x: 40, y: 108, enraged: true);
      final b = s.boss!;
      var hits = 0;
      for (var i = 0; i < 60 * 10; i++) {
        s.step(dt);
        for (final e in s.drainEvents()) {
          if (e.kind == ShmupEventKind.shipHit) hits++;
        }
        if (s.ship.lives < 3) break;
        // never inside the shell after the push-out
        final d = math.sqrt(math.pow(s.ship.x - b.x, 2) + math.pow(s.ship.y - b.y, 2));
        expect(d, greaterThan(b.shellR), reason: 'ship ended inside the shell at ${i / 60}s');
      }
      // The pull lasts 3 of every 5 s; the ship arrives after ~2 s: <= ~5 touches (1.6 s apart) in 10 s.
      expect(hits, lessThanOrEqualTo(6));
    });

    test('a claw lights its lane 0.85 s before striking, long enough to leave it from any height', () {
      for (final y in [26.0, 40.0, 108.0, 180.0, 190.0]) {
        final s = arena(3);
        final b = s.boss!;
        s.ship
          ..invuln = 0
          ..hull = 3
          ..x = 30
          ..y = y
          ..fireCd = 1e9;
        BossPart? c;
        for (var i = 0; i < 60 * 6 && c == null; i++) {
          s.ship.y = y; // sit still until a claw locks on
          s.enemyBullets.clear(); // (only the claw is on trial here)
          s.step(dt);
          for (final g in b.guards) {
            if (g.state == 1) c = g;
          }
        }
        expect(c, isNotNull);
        final claw = c!;
        final lit = s.time;
        final hull0 = s.ship.hull;
        // Leave the lane by 22 units at 100 u/s, which takes 0.22 s.
        final away = y < h / 2 ? 1.0 : -1.0;
        var struck = false;
        for (var i = 0; i < 60 * 3; i++) {
          final t = s.time - lit;
          s.ship.y = (y + away * math.min(22.0, t * 100)).clamp(4.5, h - 4.5);
          s.enemyBullets.clear();
          s.step(dt);
          if (claw.state == 2) struck = true;
        }
        expect(struck, isTrue);
        expect(s.ship.hull, hull0, reason: 'fled the lane from y=$y and still got hit');
      }
    });
  });

  group('fit', () {
    for (final kind in ShmupBossKind.values) {
      test('${kind.name}: every part stays inside the open arena and the field for a whole fight', () {
        final s = arena(kind.index + 1);
        final b = s.boss!;
        final lo = s.ceilingAt(s.width / 2), hi = h - s.floorAt(s.width / 2);
        for (var i = 0; i < 60 * 60; i++) {
          aim(s);
          s.step(dt);
          if (s.phase != ShmupPhase.playing) break;
          for (final p in b.parts) {
            final x = b.x + p.dx, y = b.y + p.dy;
            expect(y - p.r, greaterThanOrEqualTo(lo - 0.5), reason: '${p.id} above the ceiling at ${s.time}');
            expect(y + p.r, lessThanOrEqualTo(hi + 0.5), reason: '${p.id} under the floor at ${s.time}');
            // (the Prism's facets swing behind the right edge, up to ~14 units off screen)
            expect(x + p.r, lessThanOrEqualTo(s.width + 16), reason: '${p.id} past the right edge');
            expect(x - p.r, greaterThanOrEqualTo(-5), reason: '${p.id} left of the field');
          }
        }
      });
    }
  });

  group('contact', () {
    test('touching a guard costs one hull, then the 1.6 s grace; standing on it for 10 s costs <= 7', () {
      for (final kind in ShmupBossKind.values) {
        final s = arena(kind.index + 1);
        final b = s.boss!;
        final g = b.guards.first;
        s.ship
          ..invuln = 0
          ..hull = 3
          ..lives = 1; // so hull loss shows up as lives at the end
        var hits = 0;
        for (var i = 0; i < 60 * 10 && s.phase == ShmupPhase.playing; i++) {
          s.ship
            ..x = b.x + g.dx
            ..y = b.y + g.dy;
          s.step(dt);
          for (final e in s.drainEvents()) {
            if (e.kind == ShmupEventKind.shipHit) hits++;
          }
          if (s.ship.hull <= 0) break;
        }
        expect(hits, greaterThanOrEqualTo(1), reason: '${kind.name}: guard contact did nothing');
        expect(hits, lessThanOrEqualTo(3), reason: 'dies after 3 hull, one per 1.6 s window');
      }
    });
  });

  group('copy', () {
    test('boss, mid-boss and accent names are distinct per stage', () {
      final names = [for (var i = 0; i < 4; i++) shmupBossName(i)];
      expect(names, ['The Breaker', 'The Prism', 'The Hauler', 'The Maw']);
      expect({for (var i = 0; i < 4; i++) shmupMidBossName(i)}.length, 4);
      expect({for (var i = 0; i < 4; i++) shmupThemeAccent(i)}.length, 4);
      expect(shmupBossName(6), 'The Hauler', reason: 'wraps by 4');
    });

    test('the four authored stages are named Asteroid Belt, Crystal Vein, Wreck Field, Bone Reef', () {
      expect([for (final l in ShmupLevels.all) l.name], ['Asteroid Belt', 'Crystal Vein', 'Wreck Field', 'Bone Reef']);
      expect([for (final l in ShmupLevels.all) l.bossStyle], [0, 1, 2, 3]);
      expect([for (final l in ShmupLevels.all) l.theme], [0, 1, 2, 3]);
    });

    test('stages 3 and 4 follow the sim\'s stage counter and loop back after 4', () {
      final s = ShmupSim(height: h, seed: 1);
      final byStage = <int, String>{};
      for (var st = 1; st <= 9; st++) {
        s.stage = st;
        byStage[st] = s.level.name;
      }
      expect(byStage[3], 'Wreck Field');
      expect(byStage[4], 'Bone Reef');
      expect(byStage[5], 'Asteroid Belt');
      expect(byStage[8], 'Bone Reef');
    });
  });
}
