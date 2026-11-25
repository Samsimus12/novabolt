import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/cockpit/cockpit_sim.dart';

void main() {
  CockpitSim solved(int seed, int round) => CockpitSim(seed: seed, round: round);

  test('every generated round is satisfiable, non-trivial and non-contradictory', () {
    for (var round = 1; round <= 12; round++) {
      for (var seed = 0; seed < 150; seed++) {
        final s = solved(seed, round);
        final ctx = 'round $round seed $seed';
        expect(s.tasks.length, CockpitTuning.tasksFor(round), reason: ctx);
        expect(s.tasks.every((t) => !t.done), isTrue, reason: '$ctx: done at start');
        expect(s.activeModules.length, lessThanOrEqualTo(CockpitTuning.modulesFor(round)), reason: ctx);
        // Every order only touches active modules.
        for (final t in s.tasks) {
          expect(s.activeModules.containsAll(t.modules), isTrue, reason: '$ctx ${t.text}');
        }
        // No two orders share a control (so none can contradict another).
        final seen = <String>{};
        for (final t in s.tasks) {
          for (final id in t.controlIds) {
            expect(seen.add(id), isTrue, reason: '$ctx: $id used twice');
          }
        }
        s.start();
        expect(s.debugSolveAll(), isTrue, reason: ctx);
        expect(s.phase, CockpitPhase.roundClear, reason: ctx);
        expect(s.timeLeft, greaterThan(0), reason: ctx);
      }
    }
  });

  test('round 1 is 3 tasks in about 10 s (about 3 s each); difficulty ramps', () {
    var total = 0.0;
    for (var seed = 0; seed < 200; seed++) {
      final s = solved(seed, 1);
      expect(s.tasks.length, 3);
      expect(s.timeTotal, inInclusiveRange(8, 16));
      total += s.timeTotal;
    }
    expect(total / 200, inInclusiveRange(9, 12));
    expect(CockpitTuning.tasksFor(5), greaterThan(CockpitTuning.tasksFor(1)));
    expect(CockpitTuning.slackFor(8), lessThan(CockpitTuning.slackFor(1)));
    expect(CockpitTuning.slackFor(1), closeTo(1.4, 1e-9));
    expect(CockpitTuning.slackFor(12), greaterThanOrEqualTo(CockpitTuning.floorSlack));
  });

  test('the clock is built from the real orders and is never impossible', () {
    final avg = <int, double>{};
    for (var round = 1; round <= 12; round++) {
      var sum = 0.0;
      for (var seed = 0; seed < 150; seed++) {
        final s = solved(seed, round);
        final cost = s.tasks.fold<double>(0, (a, t) => a + CockpitTuning.taskSecs(t.parts));
        expect(s.modeledSecs, closeTo(cost, 1e-9));
        expect(s.timeTotal, greaterThanOrEqualTo(cost * CockpitTuning.floorSlack), reason: 'round $round seed $seed');
        expect(s.timeTotal, greaterThanOrEqualTo(CockpitTuning.minTotalSecs));
        // Seconds per task stays "do it now" early on.
        if (round == 1) expect(s.timeTotal / s.tasks.length, lessThan(5.5), reason: 'seed $seed');
        sum += s.timeTotal / s.tasks.length;
      }
      avg[round] = sum / 150;
    }
    // Average seconds per order: ~3.3 s early, tightening as the rounds go on.
    expect(avg[1]!, inInclusiveRange(2.8, 4.0));
    expect(avg[8]!, lessThan(avg[1]! * 1.7));
    // Total clock grows with the number of orders.
    final totals = [for (var r = 1; r <= 8; r++) solved(7, r).timeTotal];
    expect(totals.first, lessThan(totals.last));
  });

  test('a quick modelled player clears early rounds narrowly and fails by about round 5-8', () {
    // Simulated player: each order takes its modelled time x a noisy factor
    // (mean ~1.1, quick hands but human), an ALARM misclick in 12% of the
    // rounds that have the trap, and a wrong code now and then.
    var reachedTotal = 0;
    const games = 120;
    final reached = <int>[];
    var margin1 = 0.0, margin1n = 0;
    for (var g = 0; g < games; g++) {
      final rng = math.Random(g);
      final s = CockpitSim(seed: 1000 + g);
      var round = 1;
      while (round < 40) {
        var used = 0.0;
        for (final t in s.tasks) {
          // Roughly normal noise, sd 0.3 around 1.05.
          final z = (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) * 2;
          used += CockpitTuning.taskSecs(t.parts) * (1.1 + 0.35 * z).clamp(0.6, 2.0);
          if (t.kind == CondKind.keyCode && rng.nextDouble() < 0.15) used += CockpitTuning.wrongCodePenalty;
        }
        if (s.hasAlarm && rng.nextDouble() < 0.12) used += CockpitTuning.alarmPenalty;
        if (round == 1) {
          margin1 += (s.timeTotal - used) / s.timeTotal;
          margin1n++;
        }
        if (used >= s.timeTotal) break;
        reachedTotal++;
        s.start();
        s.debugSolveAll();
        s.nextRound();
        round = s.round;
      }
      reached.add(round);
    }
    final mean = reachedTotal / games;
    reached.sort();
    final median = reached[games ~/ 2];
    // ignore: avoid_print
    print('quick player: mean rounds cleared ${mean.toStringAsFixed(1)}, median died in $median, round-1 margin ${(margin1 / margin1n * 100).toStringAsFixed(0)}%');
    expect(median, inInclusiveRange(4, 9));
    expect(margin1 / margin1n, lessThan(0.4), reason: 'round 1 has little spare time');
    expect(margin1 / margin1n, greaterThan(0.1));
  });

  test('round 1 only uses simple orders; tricky ones appear later', () {
    final kinds = <CondKind>{};
    for (var seed = 0; seed < 100; seed++) {
      for (final t in solved(seed, 1).tasks) {
        kinds.addAll(t.parts.map((p) => p.kind));
        expect(t.isMulti, isFalse);
      }
    }
    expect(kinds.containsAll({CondKind.switchIs}), isTrue);
    expect(kinds.contains(CondKind.keyCode) || kinds.contains(CondKind.holdFor) || kinds.contains(CondKind.switchExcept), isFalse);
    final late = <CondKind>{};
    var multi = false;
    for (var seed = 0; seed < 200; seed++) {
      for (final t in solved(seed, 6).tasks) {
        late.addAll(t.parts.map((p) => p.kind));
        multi |= t.isMulti;
      }
    }
    expect(late.containsAll(CondKind.values), isTrue, reason: '$late');
    expect(multi, isTrue);
  });

  CockpitTask? find(CockpitSim s, CondKind k) => s.tasks.where((t) => !t.isMulti && t.kind == k).firstOrNull;

  CockpitSim withKind(CondKind k, {int round = 6}) {
    for (var seed = 0; seed < 500; seed++) {
      final s = solved(seed, round);
      if (find(s, k) != null) return s..start();
    }
    throw StateError('no $k found');
  }

  test('switch orders tick, un-tick and need the real state', () {
    final s = withKind(CondKind.switchIs);
    final t = find(s, CondKind.switchIs)!;
    final c = t.parts.first;
    s.setSwitch(c.ids.first, c.on);
    expect(t.done, isTrue);
    expect(s.tasksCompleted, 1);
    s.setSwitch(c.ids.first, !c.on);
    expect(t.done, isFalse, reason: 'breaking it again un-ticks');
    s.setSwitch(c.ids.first, c.on);
    expect(t.done, isTrue);
    expect(s.tasksCompleted, 1, reason: 'a task only scores once');
    final kinds = s.drainEvents().map((e) => e.kind).toList();
    expect(kinds.where((k) => k == CockpitEventKind.taskDone).length, 2);
    expect(kinds, contains(CockpitEventKind.taskUndone));
  });

  test('group and except orders', () {
    final g = withKind(CondKind.switchGroup);
    final gt = find(g, CondKind.switchGroup)!;
    final gc = gt.parts.first;
    for (final id in gc.ids) {
      g.setSwitch(id, gc.on);
    }
    expect(gt.done, isTrue);
    g.setSwitch(gc.ids.first, !gc.on);
    expect(gt.done, isFalse);
    expect(gt.progress, closeTo((gc.ids.length - 1) / gc.ids.length, 1e-9));

    final e = withKind(CondKind.switchExcept, round: 8);
    final et = find(e, CondKind.switchExcept)!;
    final ec = et.parts.first;
    for (final id in ec.ids) {
      e.setSwitch(id, id == ec.exceptId);
    }
    expect(et.done, isTrue);
    e.setSwitch(ec.exceptId!, false);
    expect(et.done, isFalse);
  });

  test('dial and slider orders', () {
    final s = withKind(CondKind.dialIs);
    final t = find(s, CondKind.dialIs)!;
    s.setDial(t.parts.first.ids.first, t.parts.first.value);
    expect(t.done, isTrue);
    s.setDial(t.parts.first.ids.first, 99); // clamped to the max
    expect(s.dialValue('dial_coolant'), 5);

    final r = withKind(CondKind.sliderIs);
    final rt = find(r, CondKind.sliderIs)!;
    r.setSlider(rt.parts.first.ids.first, rt.parts.first.value);
    expect(rt.done, isTrue);
  });

  test('press counts accumulate; the ALARM costs time but is never ordered', () {
    final s = withKind(CondKind.pressCount, round: 4);
    final t = find(s, CondKind.pressCount)!;
    final c = t.parts.first;
    for (var i = 0; i < c.value; i++) {
      expect(t.done, isFalse);
      s.press(c.ids.first);
    }
    expect(t.done, isTrue);

    for (var seed = 0; seed < 100; seed++) {
      for (final t in solved(seed, 8).tasks) {
        expect(t.controlIds, isNot(contains(CockpitPanelSpec.alarmId)));
      }
    }
    var s2 = solved(1, 4);
    for (var seed = 0; !s2.moduleActive(CockpitModule.buttons); seed++) {
      s2 = solved(seed, 4);
    }
    s2.start();
    final before = s2.timeLeft;
    s2.press(CockpitPanelSpec.alarmId);
    expect(s2.timeLeft, before - CockpitTuning.alarmPenalty);
    expect(s2.drainEvents().any((e) => e.kind == CockpitEventKind.penalty && e.reason == 'alarm'), isTrue);
  });

  test('hold needs a continuous hold; letting go resets', () {
    final s = withKind(CondKind.holdFor);
    final t = find(s, CondKind.holdFor)!;
    final c = t.parts.first;
    s.holdStart(c.ids.first);
    s.tick(c.seconds - 0.5);
    expect(t.done, isFalse);
    expect(t.progress, greaterThan(0));
    s.holdEnd(c.ids.first);
    expect(s.holdProgress(c.ids.first), 0);
    s.holdStart(c.ids.first);
    s.tick(c.seconds - 0.5);
    expect(t.done, isFalse, reason: 'two short holds do not add up');
    s.tick(0.6);
    expect(t.done, isTrue);
  });

  test('keypad: code, backspace, wrong code penalty', () {
    final s = withKind(CondKind.keyCode);
    final t = find(s, CondKind.keyCode)!;
    final code = t.parts.first.code;
    final before = s.timeLeft;
    s.enterKey((code.first + 1) % 10);
    s.backspace();
    expect(s.keyBuffer, isEmpty);
    s.enterKey(code.first);
    expect(t.progress, closeTo(1 / code.length, 1e-9));
    s.enterKey((code[1] + 1) % 10);
    s.submitKeys();
    expect(t.done, isFalse);
    expect(s.timeLeft, before - CockpitTuning.wrongCodePenalty);
    for (final d in code) {
      s.enterKey(d);
    }
    s.submitKeys();
    expect(t.done, isTrue);
    s.enterKey(code[0]);
    s.submitKeys(); // a different code un-ticks it
    expect(t.done, isFalse);
  });

  test('wires: plug, bump, unplug', () {
    final s = withKind(CondKind.wireTo);
    final t = find(s, CondKind.wireTo)!;
    final c = t.parts.first;
    s.connectWire(c.ids.first, c.value);
    expect(t.done, isTrue);
    final other = CockpitPanelSpec.wires.map((w) => w.id).firstWhere((w) => w != c.ids.first);
    s.connectWire(other, c.value); // bumps it
    expect(s.wirePort(c.ids.first), isNull);
    expect(t.done, isFalse);
    expect(s.portWire(c.value), other);
    s.connectWire(c.ids.first, c.value);
    expect(t.done, isTrue);
    s.disconnectWire(c.ids.first);
    expect(t.done, isFalse);
  });

  test('fuses reset; a healthy fuse ignores taps', () {
    final s = withKind(CondKind.fuseReset, round: 2);
    final t = find(s, CondKind.fuseReset)!;
    final id = t.parts.first.ids.first;
    expect(s.fuseBlown(id), isTrue);
    for (final f in CockpitPanelSpec.fuses.where((f) => !s.fuseBlown(f))) {
      s.replaceFuse(f);
      expect(s.fuseBlown(f), isFalse);
    }
    s.replaceFuse(id);
    expect(t.done, isTrue);
  });

  test('timer, rounds, pause, scoring', () {
    final s = solved(3, 1);
    expect(s.phase, CockpitPhase.ready);
    s.tick(5);
    expect(s.timeLeft, s.timeTotal, reason: 'the clock waits for start');
    s.toggle('sw_aux');
    expect(s.drainEvents(), isEmpty, reason: 'no input before start');
    s.start();
    s.tick(2);
    expect(s.timeLeft, closeTo(s.timeTotal - 2, 1e-9));
    s.pause();
    s.tick(3);
    expect(s.timeLeft, closeTo(s.timeTotal - 2, 1e-9));
    s.resume();
    // Clear fast (more than a third of the clock left): a clean repair.
    final n = s.tasks.length;
    s.debugSolveAll();
    expect(s.phase, CockpitPhase.roundClear);
    expect(s.lastRoundClean, isTrue);
    expect(s.cleanRepairs, 1);
    expect(s.score, n + CockpitTuning.roundClearPoints);
    expect(s.drainEvents().any((e) => e.kind == CockpitEventKind.roundCleared), isTrue);
    s.nextRound();
    expect(s.round, 2);
    expect(s.phase, CockpitPhase.playing);
    expect(s.tasks.length, CockpitTuning.tasksFor(2));
    // Clear slowly: not clean.
    s.tick(s.timeTotal * 0.8); // only a fifth left: not clean
    s.debugSolveAll();
    expect(s.phase, CockpitPhase.roundClear);
    expect(s.lastRoundClean, isFalse);
    expect(s.cleanRepairs, 1);
    expect(s.roundsCleared, 2);
    s.nextRound();
    // Run out of time: game over, partial tasks still score.
    final before = s.score;
    final t = s.tasks.first;
    if (t.parts.first.kind == CondKind.pressCount) s.press(t.parts.first.ids.first);
    s.tick(s.timeTotal + 1);
    expect(s.phase, CockpitPhase.over);
    expect(s.timeLeft, 0);
    expect(s.score, greaterThanOrEqualTo(before));
    s.toggle('sw_aux');
    expect(s.drainEvents().any((e) => e.kind == CockpitEventKind.gameOver), isTrue);
    s.reset();
    expect(s.round, 1);
    expect(s.score, 0);
    expect(s.phase, CockpitPhase.ready);
  });

  test('a penalty can end the game and low-time warnings fire once', () {
    final s = solved(5, 1)..start();
    s.tick(s.timeTotal - 10.5);
    s.tick(0.6);
    s.tick(0.1);
    final warns = s.drainEvents().where((e) => e.kind == CockpitEventKind.lowTime).toList();
    expect(warns.length, 1);
    expect(warns.first.amount, 10);
  });

  test('same seed, same round', () {
    final a = solved(42, 4);
    final b = solved(42, 4);
    expect(a.tasks.map((t) => t.text).toList(), b.tasks.map((t) => t.text).toList());
    expect(a.timeTotal, b.timeTotal);
  });
}
