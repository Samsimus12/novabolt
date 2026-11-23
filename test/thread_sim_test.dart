import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/thread/thread_sim.dart';

void main() {
  const dt = 1 / 60;

  ThreadSim sim(int seed) => ThreadSim(width: 430, height: 932, seed: seed);

  /// Flaps when the ship drops below the middle of the next gap.
  void autopilot(ThreadSim s) {
    final next = s.columns.where((c) => c.right > s.shipX - ThreadTuning.shipRadius).firstOrNull;
    final target = next?.gapCenter ?? s.height * 0.45;
    if (s.shipY > target + s.height * 0.03 && s.vy > 0) s.flap();
  }

  test('waits for the first tap, then starts', () {
    final s = sim(1);
    for (var i = 0; i < 120; i++) {
      s.step(dt);
    }
    expect(s.phase, ThreadPhase.ready);
    expect(s.columns, isEmpty);
    s.flap();
    expect(s.phase, ThreadPhase.playing);
    expect(s.columns, isNotEmpty);
    expect(s.drainEvents().single.kind, ThreadEventKind.flap);
  });

  test('without tapping you fall out of the field and crash', () {
    final s = sim(2)..flap();
    for (var i = 0; i < 60 * 5 && s.phase == ThreadPhase.playing; i++) {
      s.step(dt);
    }
    expect(s.phase, ThreadPhase.crashed);
    expect(s.score, 0);
  });

  test('every gap is reachable: no jump bigger than a ship can climb, all on screen', () {
    for (var seed = 0; seed < 30; seed++) {
      final s = sim(seed)..flap();
      final seen = <int, ThreadColumn>{};
      for (var i = 0; i < 60 * 120 && s.phase == ThreadPhase.playing; i++) {
        autopilot(s);
        s.step(dt);
        for (final c in s.columns) {
          seen[c.id] = c;
        }
      }
      final cols = seen.values.toList()..sort((a, b) => a.id.compareTo(b.id));
      for (var i = 0; i < cols.length; i++) {
        final c = cols[i];
        expect(c.gapRest - c.gapHalf - c.swing, greaterThanOrEqualTo(s.height * ThreadTuning.edgeMargin - 0.01));
        expect(c.gapRest + c.gapHalf + c.swing, lessThanOrEqualTo(s.height * (1 - ThreadTuning.edgeMargin) + 0.01));
        if (i > 0) {
          expect((c.gapRest - cols[i - 1].gapRest).abs(), lessThanOrEqualTo(s.height * ThreadTuning.maxGapJump + 0.01));
        }
      }
      // Before moving gaps start, even this crude autopilot never crashes.
      expect(s.score, greaterThanOrEqualTo(ThreadTuning.movingFrom), reason: 'seed $seed crashed at ${s.score}');
    }
  });

  test('it gets harder: faster, smaller gaps, moving gaps from 20', () {
    final s = sim(3)..flap();
    final startSpeed = s.speed;
    final startGap = s.columns.first.gapHalf;
    var sawMoving = false;
    for (var i = 0; i < 60 * 120 && s.phase == ThreadPhase.playing; i++) {
      autopilot(s);
      s.step(dt);
      if (s.columns.any((c) => c.moving)) sawMoving = true;
    }
    expect(s.speed, greaterThan(startSpeed));
    expect(s.columns.last.gapHalf, lessThan(startGap));
    expect(sawMoving, isTrue);
  });

  test('scoring and shards raise events, and reset clears everything', () {
    final s = sim(4)..flap();
    final kinds = <ThreadEventKind>{};
    for (var i = 0; i < 60 * 60 && s.phase == ThreadPhase.playing; i++) {
      autopilot(s);
      s.step(dt);
      kinds.addAll(s.drainEvents().map((e) => e.kind));
    }
    expect(kinds, containsAll([ThreadEventKind.flap, ThreadEventKind.score, ThreadEventKind.shard]));
    s.reset();
    expect(s.phase, ThreadPhase.ready);
    expect(s.score, 0);
    expect(s.columns, isEmpty);
  });
}
