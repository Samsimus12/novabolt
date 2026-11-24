import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/invaders/invaders_sim.dart';

InvadersSim fresh({int seed = 1}) => InvadersSim(height: 216, seed: seed);

/// Starts the round and lets the wave intro finish.
InvadersSim playing({int seed = 1}) {
  final s = fresh(seed: seed);
  s.start();
  _run(s, InvadersSim.waveIntroSeconds + 0.05, fire: false);
  return s;
}

void _run(InvadersSim s, double seconds, {bool fire = true}) {
  for (var t = 0.0; t < seconds; t += 1 / 60) {
    s.step(1 / 60);
  }
}

void main() {
  test('starts ready with a full formation, 4 bunkers and 3 lives', () {
    final s = fresh();
    expect(s.phase, InvadersPhase.ready);
    expect(s.aliens.length, 40);
    expect(s.aliveAliens, 40);
    expect(s.bunkers.length, 4);
    expect(s.lives, 3);
    s.step(1);
    expect(s.time, 0, reason: 'nothing runs before the first touch');
    expect(s.aliens.where((a) => a.kind == AlienKind.elite).length, 8);
    expect(s.aliens.where((a) => a.kind == AlienKind.guard).length, 16);
    expect(s.aliens.where((a) => a.kind == AlienKind.grunt).length, 16);
  });

  test('the wave intro keeps the formation frozen and the ship safe', () {
    final s = fresh()..start();
    final x0 = s.aliens.first.x;
    _run(s, 1.0);
    expect(s.aliens.first.x, x0);
    expect(s.alienShots, isEmpty);
    _run(s, 2.0);
    expect(s.aliens.first.x, isNot(x0));
  });

  test('the formation marches sideways, drops at the edge and reverses', () {
    final s = playing();
    final y0 = s.aliens.first.y;
    final x0 = s.aliens.first.x;
    var dropped = false;
    var reversed = false;
    var lastX = x0;
    var lastDir = 0;
    for (var i = 0; i < 60 * 40 && s.phase == InvadersPhase.playing; i++) {
      s.step(1 / 60);
      s.shipShots.clear();
      s.alienShots.clear();
      final a = s.aliens.first;
      if (a.y > y0 + 1) dropped = true;
      final d = (a.x - lastX).sign.toInt();
      if (d != 0) {
        if (lastDir != 0 && d != lastDir) reversed = true;
        lastDir = d;
      }
      lastX = a.x;
      if (dropped && reversed) break;
    }
    expect(dropped, isTrue);
    expect(reversed, isTrue);
    // Never leaves the field.
    for (final a in s.aliens) {
      expect(a.x - InvadersSim.alienHw, greaterThanOrEqualTo(0));
      expect(a.x + InvadersSim.alienHw, lessThanOrEqualTo(s.width));
    }
  });

  test('the swarm speeds up as aliens die and on later waves', () {
    final s = playing();
    final full = s.stepInterval;
    for (var i = 0; i < 30; i++) {
      s.aliens[i].alive = false;
    }
    expect(s.aliveAliens, 10);
    expect(s.stepInterval, lessThan(full));
    final w1 = InvadersSim(height: 216, seed: 1)..start();
    final w2 = InvadersSim(height: 216, seed: 1)..start();
    w2.wave = 3;
    expect(w2.stepInterval, lessThan(w1.stepInterval));
  });

  test('the ship moves, is clamped to the screen and fires on its own', () {
    final s = playing();
    s.moveShipBy(-500);
    expect(s.shipX, InvadersSim.shipHw);
    s.moveShipBy(1000);
    expect(s.shipX, s.width - InvadersSim.shipHw);
    s.moveShipBy(-s.width / 2);
    final events = <InvadersEventKind>[];
    s.step(1 / 60);
    events.addAll(s.drainEvents().map((e) => e.kind));
    expect(events, contains(InvadersEventKind.shoot));
    expect(s.shipShots.length, 1);
  });

  test('only one ship shot at a time, two with the twin power-up', () {
    final s = playing();
    for (final a in s.aliens) {
      a.y = 20; // keep them out of the way
    }
    for (var i = 0; i < 30; i++) {
      s.step(1 / 60);
      expect(s.shipShots.length, lessThanOrEqualTo(1));
    }
    s.twinLeft = 10;
    var most = 0;
    for (var i = 0; i < 60; i++) {
      s.step(1 / 60);
      if (s.shipShots.length > most) most = s.shipShots.length;
    }
    expect(most, 2);
  });

  test('a ship shot kills an alien and scores by kind', () {
    final s = playing();
    s.drainEvents();
    final elite = s.aliens.firstWhere((a) => a.kind == AlienKind.elite);
    final guard = s.aliens.firstWhere((a) => a.kind == AlienKind.guard);
    final grunt = s.aliens.firstWhere((a) => a.kind == AlienKind.grunt);
    for (final a in [grunt, guard, elite]) {
      s.shipShots.add(Shot(a.x, a.y + 1, fromShip: true));
    }
    final before = s.score;
    s.step(1 / 600);
    expect(s.score - before, 1 + 2 + 3);
    expect(elite.alive || guard.alive || grunt.alive, isFalse);
    expect(s.aliveAliens, 37);
    expect(s.drainEvents().where((e) => e.kind == InvadersEventKind.alienKilled).length, 3);
  });

  test('accuracy counters, hit flash and march counter', () {
    final s = playing();
    final a = s.aliens.first;
    s.shipShots.add(Shot(a.x, a.y + 1, fromShip: true));
    s.step(1 / 600);
    expect(s.shotsHit, 1);
    expect(a.alive, isFalse);
    expect(a.flash, greaterThan(0));
    s.step(0.3);
    expect(a.flash, 0);
    expect(s.shotsFired, greaterThanOrEqualTo(1));
    final m = s.marchCount;
    _run(s, 1.0, fire: false);
    expect(s.marchCount, greaterThan(m));
    expect(s.aliens.where((x) => x.alive).every((x) => x.frame == s.marchFrame), isTrue);
  });

  test('alien shots come from the bottom alien of a column', () {
    final s = playing(seed: 5);
    var seen = 0;
    for (var i = 0; i < 60 * 6 && seen < 3; i++) {
      s.step(1 / 60);
      s.shipShots.clear();
      for (final e in s.drainEvents()) {
        if (e.kind != InvadersEventKind.alienShot) continue;
        seen++;
        final shooter = s.aliens.where((a) => a.alive && (a.x - e.x).abs() < 0.01).toList();
        final lowest = shooter.map((a) => a.y).reduce((a, b) => a > b ? a : b);
        expect(e.y, closeTo(lowest + InvadersSim.alienHh, 4));
      }
      s.alienShots.clear();
    }
    expect(seen, greaterThan(0));
    expect(s.maxAlienShots, 1); // wave 1 is gentler: one alien shot at a time
  });

  test('bunkers chip from both sides and the shot is consumed', () {
    final s = playing();
    final b = s.bunkers[1];
    final full = b.aliveCount;
    // From below (ship shot) at the left leg.
    final x = b.left + 1.5;
    s.shipShots.add(Shot(x, b.top + b.height + 2, fromShip: true));
    for (var i = 0; i < 30; i++) {
      s.step(1 / 120);
    }
    final afterShip = b.aliveCount;
    expect(afterShip, lessThan(full));
    expect(s.shipShots.where((q) => (q.x - x).abs() < 0.01), isEmpty);
    // From above (alien shot).
    s.alienShots.add(Shot(b.left + 8.5, b.top - 3, fromShip: false));
    for (var i = 0; i < 30; i++) {
      s.step(1 / 120);
    }
    expect(b.aliveCount, lessThan(afterShip));
    expect(s.drainEvents().where((e) => e.kind == InvadersEventKind.bunkerChip), isNotEmpty);
  });

  test('an alien shot hitting the ship costs a life, then invulnerability', () {
    final s = playing();
    s.shipShots.clear();
    s.alienShots.add(Shot(s.shipX, s.shipY - 6, fromShip: false));
    for (var i = 0; i < 20; i++) {
      s.step(1 / 60);
    }
    expect(s.lives, 2);
    expect(s.invulnerable, greaterThan(1));
    expect(s.alienShots, isEmpty);
    s.alienShots.add(Shot(s.shipX, s.shipY - 3, fromShip: false));
    s.step(1 / 60);
    expect(s.lives, 2, reason: 'invulnerable right after a hit');
  });

  test('a shield absorbs one hit', () {
    final s = playing();
    s.shieldLeft = 10;
    s.alienShots.add(Shot(s.shipX, s.shipY - 3, fromShip: false));
    s.step(1 / 60);
    expect(s.lives, 3);
    expect(s.shielded, isFalse);
    expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.shieldBlock));
  });

  test('three hits end the game and report it once', () {
    final s = playing();
    for (var i = 0; i < 3; i++) {
      s.invulnerable = 0;
      s.alienShots.add(Shot(s.shipX, s.shipY - 3, fromShip: false));
      s.step(1 / 60);
    }
    expect(s.phase, InvadersPhase.over);
    expect(s.lives, 0);
    expect(s.landed, isFalse);
    expect(s.drainEvents().where((e) => e.kind == InvadersEventKind.gameOver).length, 1);
    final score = s.score;
    s.step(1);
    s.moveShipBy(10);
    expect(s.score, score);
    expect(s.overFor, greaterThan(0.9));
  });

  test('the swarm reaching the ship ends the game', () {
    final s = playing();
    for (final a in s.aliens) {
      a.y += s.shipY - s.aliens.last.y - 2;
    }
    s.shipShots.clear();
    for (var i = 0; i < 60 && s.phase == InvadersPhase.playing; i++) {
      s.step(1 / 60);
    }
    expect(s.phase, InvadersPhase.over);
    expect(s.landed, isTrue);
    expect(s.lives, 0);
  });

  test('aliens eat the bunker cells they walk through', () {
    final s = playing();
    final b = s.bunkers[0];
    final before = b.aliveCount;
    s.aliens.first
      ..x = b.centerX
      ..y = b.top + 2;
    s.shipShots.clear();
    _runSteps(s);
    expect(b.aliveCount, lessThan(before));
  });

  test('the mothership crosses the top, shooting it pays 10 and a bonus', () {
    final s = playing(seed: 3);
    s.drainEvents();
    var appeared = false;
    for (var i = 0; i < 60 * 30 && !appeared; i++) {
      s.step(1 / 60);
      s.shipShots.clear();
      s.alienShots.clear();
      appeared = s.mothership != null;
    }
    expect(appeared, isTrue);
    expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.mothershipAppear));
    final m = s.mothership!;
    final x0 = m.x;
    s.step(0.5);
    s.shipShots.clear();
    expect((s.mothership!.x - x0).abs(), greaterThan(5));
    final before = s.score;
    s.shipShots.add(Shot(s.mothership!.x, s.mothership!.y + 1, fromShip: true));
    s.step(1 / 600);
    expect(s.score - before, InvadersSim.mothershipPoints);
    expect(s.bonus, 1);
    expect(s.mothership, isNull);
  });

  test('the mothership leaves the screen when missed', () {
    final s = playing(seed: 3);
    s.shipShots.clear();
    for (var i = 0; i < 60 * 30 && s.mothership == null; i++) {
      s.step(1 / 60);
      s.shipShots.clear();
      s.alienShots.clear();
    }
    expect(s.mothership, isNotNull);
    for (var i = 0; i < 60 * 8; i++) {
      s.step(1 / 60);
      s.shipShots.clear();
      s.alienShots.clear();
    }
    expect(s.mothership, isNull);
    expect(s.bonus, 0);
  });

  test('clearing the formation scores +5 and starts a lower, faster wave', () {
    final s = playing();
    final top1 = s.aliens.first.y;
    for (final a in s.aliens.skip(1)) {
      a.alive = false;
    }
    s.aliens.first.alive = true;
    s.shipShots.clear();
    final last = s.aliens.first;
    s.shipShots.add(Shot(last.x, last.y + 1, fromShip: true));
    final before = s.score;
    s.step(1 / 600);
    expect(s.wave, 2);
    expect(s.score - before, 3 + InvadersSim.waveClearBonus);
    expect(s.aliens.every((a) => a.alive), isTrue);
    expect(s.aliens.first.y, greaterThan(top1));
    expect(s.intro, greaterThan(1));
    expect(s.bunkers.every((b) => b.aliveCount > 60), isTrue);
    expect(s.maxAlienShots, 2);
  });

  test('later waves start lower (capped), shoot faster and allow more shots', () {
    final s = fresh();
    final y1 = s.aliens.first.y;
    s.wave = 6;
    expect(s.maxAlienShots, 4);
    s.wave = 20;
    expect(s.maxAlienShots, 5);
    // Build via clearing waves.
    final t = playing();
    for (var w = 0; w < 7; w++) {
      for (final a in t.aliens) {
        a.alive = false;
      }
      _killLast(t);
    }
    expect(t.wave, 8);
    expect(t.aliens.first.y, greaterThan(y1));
    expect(
      t.aliens.first.y,
      lessThanOrEqualTo(y1 + 5 * 5.0 + 6 + 0.01),
      reason: 'the lowering is capped (+6 on a boss wave)',
    );
  });

  test('a power-up drops from the mothership and is caught by the ship', () {
    final s = playing();
    s.powerups.add(Powerup(s.shipX, s.shipY - 20, PowerupKind.twin));
    for (var i = 0; i < 60; i++) {
      s.step(1 / 60);
      s.alienShots.clear();
    }
    expect(s.powerups, isEmpty);
    expect(s.twin, isTrue);
    s.powerups.add(Powerup(s.shipX, s.shipY - 5, PowerupKind.shield));
    s.step(1 / 30);
    expect(s.shielded, isTrue);
    // Times out.
    s.twinLeft = 0.05;
    s.step(0.1);
    expect(s.twin, isFalse);
  });

  test('reset gives a fresh round', () {
    final s = playing();
    s.score = 50;
    s.lives = 1;
    s.wave = 4;
    s.reset();
    expect(s.phase, InvadersPhase.ready);
    expect(s.score, 0);
    expect(s.lives, 3);
    expect(s.wave, 1);
    expect(s.aliveAliens, 40);
  });

  test('same seed, same game', () {
    List<int> trace(int seed) {
      final s = playing(seed: seed);
      final out = <int>[];
      for (var i = 0; i < 600; i++) {
        s.step(1 / 60);
        s.moveShipBy(i % 120 < 60 ? 0.4 : -0.4);
        out.add(s.alienShots.length * 1000 + s.score);
      }
      return out;
    }

    expect(trace(7), trace(7));
  });

  test('a leading, dodging bot clears wave 1 (seeds 1 and 3)', () {
    for (final seed in [1, 3]) {
      final s = InvadersSim(height: 216, seed: seed)..start();
      for (var i = 0; i < 60 * 300 && s.phase == InvadersPhase.playing && s.wave < 2; i++) {
        botFrame(s);
        s.step(1 / 60);
      }
      expect(s.wave, greaterThanOrEqualTo(2), reason: 'seed $seed');
      expect(s.score, greaterThanOrEqualTo(40 + InvadersSim.waveClearBonus - 10));
    }
  });

  // ── Variety pass ──────────────────────────────────────────────────────

  group('enemy variety', () {
    test('wave 1 only has the three basic kinds; the rest arrive by wave', () {
      Set<AlienKind> kinds(int w) => atWave(w).aliens.map((a) => a.kind).toSet();
      const basic = {AlienKind.elite, AlienKind.guard, AlienKind.grunt};
      expect(kinds(1), basic);
      expect(kinds(2), {...basic, AlienKind.armored}.difference({AlienKind.guard}).union({AlienKind.guard}));
      expect(kinds(2).contains(AlienKind.diver), isFalse);
      expect(kinds(3).contains(AlienKind.diver), isTrue);
      expect(kinds(3).contains(AlienKind.splitter), isFalse);
      expect(kinds(5).contains(AlienKind.splitter), isTrue);
      expect(kinds(5).contains(AlienKind.shielder), isFalse);
      expect(kinds(6).contains(AlienKind.shielder), isTrue);
      final w1 = atWave(1);
      expect(w1.carrier, isNull);
      expect(w1.isBossWave, isFalse);
    });

    test('wave 2 stays gentle: two armoured aliens, one alien shot, no divers or boss', () {
      final s = atWave(2);
      expect(s.aliens.where((a) => a.kind == AlienKind.armored).length, 2);
      expect(s.aliens.length, 40);
      expect(s.maxAlienShots, 2);
      expect(s.carrier, isNull);
    });

    test('an armoured alien takes two hits, cracks and pays 4 once', () {
      final s = atWave(2);
      final a = s.aliens.firstWhere((a) => a.kind == AlienKind.armored);
      expect(a.hp, 2);
      expect(a.cracked, isFalse);
      s.drainEvents();
      final before = s.score;
      s.shipShots.add(Shot(a.x, a.y + 1, fromShip: true));
      s.step(1 / 600);
      expect(a.alive, isTrue);
      expect(a.hp, 1);
      expect(a.cracked, isTrue);
      expect(a.hurt, greaterThan(0));
      expect(s.score, before);
      expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.alienHit));
      s.shipShots.add(Shot(a.x, a.y + 1, fromShip: true));
      s.step(1 / 600);
      expect(a.alive, isFalse);
      expect(s.score - before, AlienKind.armored.points);
      expect(AlienKind.armored.points, 4);
    });

    test('a splitter leaves two minis worth 1 each', () {
      final s = atWave(5);
      final sp = s.aliens.firstWhere((a) => a.kind == AlienKind.splitter);
      final n = s.aliens.length;
      s.drainEvents();
      final before = s.score;
      s.shipShots.add(Shot(sp.x, sp.y + 1, fromShip: true));
      s.step(1 / 600);
      expect(s.score - before, 3);
      expect(s.aliens.length, n + 2);
      final minis = s.aliens.where((a) => a.alive && a.kind == AlienKind.mini).toList();
      expect(minis.length, 2);
      expect(minis[0].x, isNot(minis[1].x));
      expect(minis[0].hw, lessThan(InvadersSim.alienHw));
      expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.alienSplit));
      final b2 = s.score;
      s.shipShots.add(Shot(minis[0].x, minis[0].y + 1, fromShip: true));
      s.step(1 / 600);
      expect(s.score - b2, 1);
      expect(s.aliens.where((a) => a.alive && a.kind == AlienKind.mini).length, 1, reason: 'minis do not split again');
    });

    test('a shield-bearer covers its row neighbours until it is shot', () {
      final s = atWave(6);
      final sh = s.aliens.firstWhere((a) => a.kind == AlienKind.shielder);
      final nb = s.aliens.firstWhere((a) => a.row == sh.row && a.col == sh.col + 1);
      expect(
        s.aliens.where((a) => a.kind == AlienKind.shielder && a.covered),
        isEmpty,
        reason: 'bearers are not adjacent',
      );
      s.step(1 / 600);
      expect(nb.covered, isTrue);
      expect(s.aliens.firstWhere((a) => a.row == sh.row && a.col == sh.col - 1).covered, isTrue);
      s.drainEvents();
      final shots = s.shotsHit;
      s.shipShots.add(Shot(nb.x, nb.y + 1, fromShip: true));
      s.step(1 / 600);
      expect(nb.alive, isTrue);
      expect(s.shipShots.where((q) => (q.x - nb.x).abs() < 0.01), isEmpty, reason: 'the shot is absorbed');
      expect(s.shotsHit, shots);
      expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.alienShielded));
      // The bearer is on the bottom row, so it can be shot directly.
      s.shipShots.add(Shot(sh.x, sh.y + 1, fromShip: true));
      s.step(1 / 600);
      expect(sh.alive, isFalse);
      s.step(1 / 600);
      expect(nb.covered, isFalse);
      s.shipShots.add(Shot(nb.x, nb.y + 1, fromShip: true));
      s.step(1 / 600);
      expect(nb.alive, isFalse);
    });

    test('a diver winds up, dives at the ship, and crashes into it', () {
      final s = atWave(3, seed: 2);
      Alien? d;
      var crash = false, start = false;
      for (var i = 0; i < 60 * 40 && s.phase == InvadersPhase.playing && !crash; i++) {
        s.step(1 / 60);
        s.shipShots.clear();
        s.alienShots.clear();
        for (final e in s.drainEvents()) {
          if (e.kind == InvadersEventKind.diveStart) start = true;
          if (e.kind == InvadersEventKind.crash) crash = true;
        }
        d ??= s.aliens.where((a) => a.diving).firstOrNull;
        if (d != null && d.dive == DiveState.windup) {
          expect(d.kind, AlienKind.diver);
          expect(d.homeX, closeTo(d.x, 0.001));
        }
      }
      expect(start, isTrue);
      expect(crash, isTrue);
      expect(s.lives, 2);
      expect(d!.alive, isFalse);
    });

    test('a dodged diver leaves the screen, re-enters and rejoins the formation', () {
      final s = atWave(3, seed: 2);
      Alien? d;
      var sawReturn = false;
      for (var i = 0; i < 60 * 60 && s.phase == InvadersPhase.playing; i++) {
        s.step(1 / 60);
        s.shipShots.clear();
        s.alienShots.clear();
        s.drainEvents();
        d ??= s.aliens.where((a) => a.diving).firstOrNull;
        if (d != null) {
          if (d.dive == DiveState.diving && d.y > s.shipY - 40) {
            // Dodge: slide away to the far side.
            s.moveShipBy(d.x < s.width / 2 ? 80 : -80);
          }
          if (d.dive == DiveState.returning) sawReturn = true;
          if (sawReturn && d.dive == DiveState.none) break;
        }
      }
      expect(sawReturn, isTrue);
      expect(d!.alive, isTrue);
      expect(d.dive, DiveState.none);
      expect(d.y, closeTo(d.homeY, 0.001));
      expect(s.lives, 3);
    });

    test('divers fire nothing and wave 4 (boss) has none', () {
      final s = atWave(3);
      final a = s.aliens.firstWhere((a) => a.kind == AlienKind.diver);
      a.dive = DiveState.diving;
      a.homeX = a.x;
      a.homeY = a.y;
      expect(s.aliens.where((x) => x.alive && !x.diving && x.col == a.col).isNotEmpty, isTrue);
      expect(atWave(4).aliens.any((a) => a.kind == AlienKind.diver), isFalse);
    });
  });

  group('boss wave', () {
    test('every 4th wave has a carrier over a small formation and no mothership', () {
      final s = atWave(4);
      expect(s.isBossWave, isTrue);
      final c = s.carrier!;
      expect(c.hp, c.maxHp);
      expect(c.maxHp, greaterThan(5));
      expect(s.aliens.length, 16);
      expect(atWave(8).aliens.length, 24);
      expect(atWave(8).carrier!.maxHp, greaterThan(c.maxHp));
      for (var i = 0; i < 60 * 30; i++) {
        s.step(1 / 60);
        s.shipShots.clear();
        s.alienShots.clear();
        s.drones.clear();
        expect(s.mothership, isNull);
      }
      expect(atWave(5).carrier, isNull);
    });

    test('the carrier slides, launches drones and fires shells', () {
      final s = atWave(4);
      final c = s.carrier!;
      final x0 = c.x;
      var drones = 0, shells = 0, maxDrones = 0;
      for (var i = 0; i < 60 * 12 && s.phase == InvadersPhase.playing; i++) {
        s.step(1 / 60);
        s.shipShots.clear();
        s.moveShipBy(i % 200 < 100 ? 0.5 : -0.5);
        s.invulnerable = 5;
        if (s.drones.length > maxDrones) maxDrones = s.drones.length;
        for (final e in s.drainEvents()) {
          if (e.kind == InvadersEventKind.droneSpawn) drones++;
        }
        shells += s.alienShots.where((q) => q.kind == ShotKind.shell).length;
      }
      expect((c.x - x0).abs(), greaterThan(1));
      expect(drones, greaterThanOrEqualTo(2));
      expect(maxDrones, lessThanOrEqualTo(4));
      expect(shells, greaterThan(0));
      expect(s.lives, 3, reason: 'invulnerable the whole time');
    });

    test('shots wear the carrier down; it pays 20, a NOVA shard and a power-up, and the wave ends', () {
      final s = atWave(4);
      final c = s.carrier!;
      for (final a in s.aliens) {
        a.alive = false;
      }
      s.drainEvents();
      s.shipShots.add(Shot(c.x, c.y + 3, fromShip: true));
      s.step(1 / 600);
      expect(c.hp, c.maxHp - 1);
      expect(c.flash, greaterThan(0));
      expect(s.wave, 4, reason: 'not over while the carrier lives');
      expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.carrierHit));
      c.hp = 1;
      final before = s.score;
      s.shipShots.add(Shot(c.x, c.y + 3, fromShip: true));
      s.step(1 / 600);
      final ev = s.drainEvents().map((e) => e.kind).toList();
      expect(ev, contains(InvadersEventKind.carrierDown));
      expect(ev, contains(InvadersEventKind.powerupDrop));
      expect(s.bonus, 1);
      expect(s.score - before, InvadersSim.carrierPoints + InvadersSim.waveClearBonus);
      expect(s.wave, 5);
      expect(s.carrier, isNull);
    });

    test('a drone can be shot (1 pt) or rams the ship', () {
      final s = atWave(4);
      s.drones.add(Drone(20, 100, 0));
      s.drainEvents();
      final before = s.score;
      s.shipShots.add(Shot(20, 101, fromShip: true));
      s.step(1 / 600);
      expect(s.drones, isEmpty);
      expect(s.score - before, 1);
      s.drones.add(Drone(s.shipX, s.shipY - 2, 0));
      s.step(1 / 60);
      expect(s.lives, 2);
      expect(s.drones, isEmpty);
      expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.crash));
    });
  });

  group('gun drops', () {
    InvadersSim withGun(PowerupKind k, {int wave = 3}) {
      final s = atWave(wave);
      s.powerups.add(Powerup(s.shipX, s.shipY - 4, k));
      s.step(1 / 60);
      return s;
    }

    test('catching a gun sets it for its time; a new gun replaces the old one', () {
      for (final k in [
        PowerupKind.twin,
        PowerupKind.spread,
        PowerupKind.laser,
        PowerupKind.rapid,
        PowerupKind.homing,
      ]) {
        final s = withGun(k);
        expect(s.gun, k);
        expect(s.gunLeft, closeTo(k.seconds, 0.1));
        expect(s.gunSeconds, k.seconds);
        expect(k.isGun, isTrue);
      }
      final s = withGun(PowerupKind.spread);
      s.powerups.add(Powerup(s.shipX, s.shipY - 4, PowerupKind.rapid));
      s.step(1 / 60);
      expect(s.gun, PowerupKind.rapid);
      expect(s.gunLeft, closeTo(10, 0.1));
      // Shield and slow are not guns and do not replace it.
      s.powerups.add(Powerup(s.shipX, s.shipY - 4, PowerupKind.shield));
      s.step(1 / 60);
      expect(s.gun, PowerupKind.rapid);
      expect(s.shielded, isTrue);
      expect(PowerupKind.shield.isGun, isFalse);
    });

    test('guns time out and a hit takes the gun away', () {
      final s = withGun(PowerupKind.laser);
      s.gunLeft = 0.05;
      s.step(0.1);
      expect(s.gun, isNull);
      final t = withGun(PowerupKind.spread);
      t.shieldLeft = 0;
      t.alienShots.add(Shot(t.shipX, t.shipY - 3, fromShip: false));
      t.step(1 / 60);
      expect(t.lives, 2);
      expect(t.gun, isNull);
    });

    test('spread fires a three-way volley (two volleys at most)', () {
      final s = playing();
      s.gun = PowerupKind.spread;
      s.gunLeft = 10;
      for (final a in s.aliens) {
        a.y = 20;
      }
      s.shipShots.clear();
      for (var i = 0; i < 30 && s.shipShots.isEmpty; i++) {
        s.step(1 / 60);
      }
      final xs = s.shipShots.map((q) => q.vx).toList()..sort();
      expect(xs.length, 3);
      expect(xs.first, lessThan(0));
      expect(xs[1], 0);
      expect(xs.last, greaterThan(0));
      expect(s.shipShots.every((q) => q.kind == ShotKind.spread), isTrue);
      var most = 0;
      for (var i = 0; i < 90; i++) {
        s.step(1 / 60);
        if (s.shipShots.length > most) most = s.shipShots.length;
        s.alienShots.clear();
      }
      expect(most, lessThanOrEqualTo(s.maxShots));
      expect(most, 6);
      expect(s.shotsFired, greaterThanOrEqualTo(6), reason: 'counted per shot, three at a time');
    });

    test('rapid fire has a faster cooldown and four shots', () {
      int fired(PowerupKind? gun) {
        final s = playing();
        s.gun = gun;
        s.gunLeft = gun == null ? 0 : 10;
        // One alien parked out of the ship's lane so every shot flies off the top.
        for (final a in s.aliens) {
          a.alive = false;
        }
        s.aliens.first
          ..alive = true
          ..x = 6
          ..y = 20;
        s.moveShipBy(60);
        s.shipShots.clear();
        s.shotsFired = 0;
        for (var i = 0; i < 180; i++) {
          s.step(1 / 60);
          s.alienShots.clear();
        }
        return s.shotsFired;
      }

      expect(fired(PowerupKind.rapid), greaterThan(fired(null) * 2));
      expect(withGun(PowerupKind.rapid, wave: 1).maxShots, 4);
    });

    test('the laser pierces a whole column, ignores cover and bunkers, and one-shots armour', () {
      final s = atWave(6);
      s.gun = PowerupKind.laser;
      s.gunLeft = 8;
      // Pick a column with a bearer; stack: every alien in it dies from one beam.
      final col = s.aliens.firstWhere((a) => a.kind == AlienKind.shielder).col;
      final column = s.aliens.where((a) => a.col == col).toList();
      final armored = s.aliens.where((a) => a.kind == AlienKind.armored && a.col == col).length;
      s.moveShipBy(column.first.x - s.shipX);
      s.shipShots.clear();
      final bunkerCells = [for (final b in s.bunkers) b.aliveCount];
      for (var i = 0; i < 40 && s.shipShots.isEmpty; i++) {
        s.step(1 / 60);
      }
      final beam = s.shipShots.single;
      expect(beam.kind, ShotKind.laser);
      expect(beam.pierce, isTrue);
      s.invulnerable = 99;
      for (var i = 0; i < 60 && s.shipShots.contains(beam); i++) {
        s.step(1 / 60);
        s.alienShots.clear();
        // Stay put while the beam flies.
        s.moveShipBy(column.first.x - s.shipX);
        s.shipShots.removeWhere((q) => q != beam);
      }
      final dead = column.where((a) => !a.alive).length;
      expect(dead, column.length, reason: 'incl. $armored armoured in the column');
      expect(
        [for (final b in s.bunkers) b.aliveCount].fold<int>(0, (a, b) => a + b),
        bunkerCells.fold<int>(0, (a, b) => a + b),
      );
    });

    test('the laser hits each target once and counts as one hit for accuracy', () {
      final s = atWave(1);
      final col = s.aliens.where((a) => a.col == 0).toList();
      s.shipShots.clear();
      s.shotsHit = 0;
      final beam = Shot(col.first.x, s.shipY - 10, fromShip: true, kind: ShotKind.laser, speed: InvadersSim.laserSpeed);
      s.shipShots.add(beam);
      for (var i = 0; i < 60; i++) {
        s.step(1 / 60);
        s.alienShots.clear();
        s.shipShots.removeWhere((q) => q != beam);
      }
      expect(col.where((a) => a.alive), isEmpty);
      expect(s.shotsHit, 1);
    });

    test('homing missiles bend toward an enemy', () {
      final s = atWave(3);
      for (final a in s.aliens) {
        a.alive = false;
      }
      final target = s.aliens.first
        ..alive = true
        ..hp = 1
        ..x = 62
        ..y = 80;
      s.shipShots.clear();
      s.moveShipBy(30 - s.shipX);
      s.gun = PowerupKind.homing;
      s.gunLeft = 10;
      final before = s.score;
      var vxSeen = 0.0;
      for (var i = 0; i < 120 && target.alive; i++) {
        s.step(1 / 60);
        s.alienShots.clear();
        for (final q in s.shipShots) {
          expect(q.kind, ShotKind.missile);
          if (q.vx.abs() > vxSeen) vxSeen = q.vx;
        }
        // Keep the target where it was (no march).
        target
          ..x = 62
          ..y = 80;
      }
      expect(vxSeen, greaterThan(10));
      expect(target.alive, isFalse, reason: 'the missile steered 32 units sideways into it');
      expect(s.score, greaterThan(before));
    });

    test('a missile does not bend without enemies', () {
      final s = atWave(3);
      final q = Shot(40, 100, fromShip: true, kind: ShotKind.missile, speed: InvadersSim.missileSpeed);
      for (final a in s.aliens) {
        a.alive = false;
      }
      s.carrier = null;
      s.shipShots.add(q);
      s.step(1 / 60);
      expect(q.vx, 0);
    });

    test('the smart bomb clears shots and drones, and hits the two bottom rows', () {
      final s = atWave(3);
      final n = s.aliveAliens;
      s.alienShots.add(Shot(10, 100, fromShip: false));
      s.drones.add(Drone(10, 60, 0));
      s.drainEvents();
      final before = s.score;
      s.powerups.add(Powerup(s.shipX, s.shipY - 4, PowerupKind.bomb));
      s.step(1 / 60);
      expect(s.alienShots, isEmpty);
      expect(s.drones, isEmpty);
      expect(s.aliveAliens, lessThan(n));
      expect(s.aliveAliens, greaterThanOrEqualTo(n - 16));
      expect(s.score, greaterThan(before));
      expect(s.drainEvents().map((e) => e.kind), contains(InvadersEventKind.smartBomb));
      expect(s.gun, isNull, reason: 'the bomb is instant, not a gun');
      // Top rows survive.
      expect(s.aliens.where((a) => a.row == 0 && a.alive).length, 8);
    });

    test('the smart bomb hurts the carrier (3) without ending it early', () {
      final s = atWave(4);
      final c = s.carrier!;
      s.powerups.add(Powerup(s.shipX, s.shipY - 4, PowerupKind.bomb));
      s.step(1 / 60);
      expect(c.hp, c.maxHp - 3);
    });

    test('slow halves the swarm for six seconds', () {
      int marches(bool slow) {
        final s = playing();
        for (final a in s.aliens) {
          a.y = 30;
        }
        if (slow) {
          s.powerups.add(Powerup(s.shipX, s.shipY - 4, PowerupKind.slow));
          s.step(1 / 60);
          expect(s.slowed, isTrue);
        }
        final m = s.marchCount;
        for (var i = 0; i < 120; i++) {
          s.step(1 / 60);
          s.alienShots.clear();
          s.shipShots.clear();
        }
        return s.marchCount - m;
      }

      expect(marches(true), lessThan(marches(false) * 0.7));
      final s = playing();
      s.slowLeft = 0.05;
      s.step(0.1);
      expect(s.slowed, isFalse);
    });

    test('drops are more frequent, guaranteed by the pity timer, and wave 1 stays simple', () {
      final seen = <PowerupKind>{};
      var drops = 0, kills = 0;
      for (var seed = 1; seed <= 12; seed++) {
        final s = playing(seed: seed);
        s.shipShots.clear();
        for (final a in List<Alien>.of(s.aliens)) {
          s.powerups.clear();
          s.shipShots.add(Shot(a.x, a.y + 1, fromShip: true));
          s.step(1 / 600);
          s.shipShots.clear();
          kills++;
          for (final e in s.drainEvents()) {
            if (e.kind == InvadersEventKind.powerupDrop) {
              drops++;
              seen.add(e.powerup!);
            }
          }
          if (s.wave > 1) break;
        }
      }
      expect(drops / kills, greaterThan(0.06));
      expect(seen.difference({PowerupKind.twin, PowerupKind.shield, PowerupKind.spread, PowerupKind.rapid}), isEmpty);
      expect(seen.length, greaterThanOrEqualTo(3));
    });

    test('later waves can drop every kind', () {
      final seen = <PowerupKind>{};
      for (var seed = 1; seed <= 40; seed++) {
        final s = atWave(4, seed: seed);
        for (var i = 0; i < 6; i++) {
          s.powerups.clear();
          final a = s.aliens.firstWhere((a) => a.alive, orElse: () => s.aliens.first);
          a.alive = true;
          a.hp = 1;
          s.shipShots.add(Shot(a.x, a.y + 1, fromShip: true));
          s.step(1 / 600);
          for (final e in s.drainEvents()) {
            if (e.kind == InvadersEventKind.powerupDrop) seen.add(e.powerup!);
          }
        }
      }
      expect(seen, containsAll(PowerupKind.values));
    });
  });

  test('every kill is worth 1-5 points and the carrier 20', () {
    for (final k in AlienKind.values) {
      expect(k.points, inInclusiveRange(1, 5));
    }
    expect(InvadersSim.carrierPoints, 20);
  });

  test('long bot game with the new enemies stays sane and deterministic', () {
    List<int> run(int seed) {
      final s = InvadersSim(height: 216, seed: seed)..start();
      var maxWave = 1;
      for (var i = 0; i < 60 * 240 && s.phase == InvadersPhase.playing; i++) {
        s.lives = 3;
        botFrame(s);
        s.step(1 / 60);
        s.drainEvents();
        maxWave = s.wave;
        for (final a in s.aliens) {
          if (!a.alive) continue;
          expect(a.x.isNaN || a.y.isNaN, isFalse);
          expect(a.x, inInclusiveRange(-1, s.width + 1));
        }
        expect(s.drones.length, lessThanOrEqualTo(6));
        expect(s.shipShots.length, lessThanOrEqualTo(8));
      }
      return [maxWave, s.score];
    }

    final a = run(11);
    expect(a[0], greaterThanOrEqualTo(4), reason: 'reaches the first boss wave');
    expect(run(11), a);
  });
}

/// A reasonable "human": leads its target, dodges shots.
void botFrame(InvadersSim s, {double speed = 1.6}) {
  final alive = s.aliens.where((a) => a.alive).toList();
  var target = s.shipX;
  if (alive.isNotEmpty) {
    alive.sort((p, q) => (p.x - s.shipX).abs().compareTo((q.x - s.shipX).abs()));
    final a = alive.first;
    final t = (s.shipY - a.y) / InvadersSim.shipShotSpeed;
    target = a.x + s.marchDirection * InvadersSim.marchStepX / s.stepInterval * t;
  }
  var bestX = s.shipX, bestCost = double.infinity;
  for (var dx = -speed; dx <= speed + 0.001; dx += speed / 4) {
    final x = (s.shipX + dx).clamp(4.0, 96.0);
    var cost = 0.02 * (x - target).abs();
    for (final sh in s.alienShots) {
      final dy = s.shipY - sh.y;
      if (dy < -2 || dy > 70) continue;
      final w = (7 - (sh.x - x).abs());
      if (w > 0) cost += w * (1 + (70 - dy) / 30);
    }
    if (cost < bestCost) {
      bestCost = cost;
      bestX = x;
    }
  }
  s.moveShipBy(bestX - s.shipX);
}

/// A fresh round advanced to wave [w], past its intro (earlier waves are
/// cleared by fiat).
InvadersSim atWave(int w, {int seed = 1}) {
  final s = playing(seed: seed);
  while (s.wave < w) {
    for (final a in s.aliens) {
      a.alive = false;
    }
    s.shipShots.clear();
    _killLast(s);
  }
  for (var t = 0.0; t < InvadersSim.waveIntroSeconds + 0.05; t += 1 / 60) {
    s.step(1 / 60);
    s.shipShots.clear(); // the ship auto-fires: keep its shots out of the setup
  }
  s.shipShots.clear();
  s.alienShots.clear();
  s.powerups.clear();
  s.drainEvents();
  return s;
}

void _runSteps(InvadersSim s) {
  for (var i = 0; i < 5; i++) {
    s.step(0.2);
    s.shipShots.clear();
    s.alienShots.clear();
  }
}

/// Leaves one alien and shoots it, which clears the wave (a boss wave's
/// carrier is dropped first).
void _killLast(InvadersSim s) {
  s.carrier = null;
  s.drones.clear();
  final a = s.aliens.first
    ..alive = true
    ..hp = 1;
  s.shipShots.add(Shot(a.x, a.y + 1, fromShip: true));
  s.step(1 / 600);
}
