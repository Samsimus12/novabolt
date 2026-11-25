import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/starport/starport_sim.dart';
import 'package:novabolt/arcade/starport/starport_types.dart';

StarShip ship(int id, int color, int col, int row,
        {Facing facing = Facing.right, ShipKind kind = ShipKind.shuttle}) =>
    StarShip(id: id, color: color, kind: kind, facing: facing, col: col, row: row);

StarportLevel lvl(List<StarShip> ships, List<int> queue,
        {int bays = 2, int number = 1, int cols = 6, int rows = 4}) =>
    StarportLevel(
      number: number,
      cols: cols,
      rows: rows,
      ships: ships,
      queue: queue,
      bays: bays,
      colorCount: 3,
    );

List<int> rep(int color, int n) => List.filled(n, color);

StarportSim simFor(StarportLevel Function(int n) f, {int seed = 1}) {
  final s = StarportSim(levelSource: (n, _) => f(n), seed: seed);
  s.start();
  s.drainEvents();
  return s;
}

void main() {
  test('start moves ready to playing and announces level 1', () {
    final s = StarportSim(levelSource: (n, _) => lvl([ship(0, 0, 0, 0)], rep(0, 4)), seed: 1);
    expect(s.phase, StarportPhase.ready);
    expect(s.tap(0), TapResult.ignored);
    s.start();
    expect(s.phase, StarportPhase.playing);
    final ev = s.drainEvents();
    expect(ev.single, isA<StarLevelStarted>());
    expect((ev.single as StarLevelStarted).levelNumber, 1);
  });

  test('blocked ship bumps, then launches once the blocker leaves', () {
    // 0 sits behind 1 (both face right on row 0).
    final s = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 2, 0)],
        [...rep(0, 4), ...rep(1, 4)]));
    expect(s.tap(0), TapResult.blocked);
    expect(s.power, closeTo(1 - StarportTuning.bumpCost, 1e-9));
    expect(s.levelClean, isFalse);
    final ev = s.drainEvents();
    expect((ev.single as StarBumped).blockerId, 1);
    expect(s.parked.length, 2);
    expect(s.tap(1), TapResult.launched);
    expect(s.tap(0), TapResult.launched);
  });

  test('unknown ship and taps outside playing are ignored', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0)], rep(0, 4)));
    expect(s.tap(99), TapResult.ignored);
    expect(s.tap(0), TapResult.launched);
    expect(s.phase, StarportPhase.levelClear);
    expect(s.tap(0), TapResult.ignored);
  });

  test('noBay when every bay is taken (zero-bay level), nothing changes', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0)], rep(0, 4), bays: 0));
    expect(s.tap(0), TapResult.noBay);
    expect(s.parked.length, 1);
    expect(s.drainEvents().single, isA<StarNoBay>());
    expect(s.power, 1);
  });

  test('boarding goes to the earliest-docked matching ship; departures free bays', () {
    // Two colour-0 shuttles and one colour-1; launch ship 1 first.
    final s = simFor((n) => lvl(
          [ship(0, 0, 0, 0), ship(1, 0, 0, 1), ship(2, 1, 0, 2)],
          [...rep(0, 8), ...rep(1, 4)],
          bays: 3,
        ));
    expect(s.tap(1), TapResult.launched);
    final ev = s.drainEvents();
    expect(ev.first, isA<StarLaunched>());
    final boards = ev.whereType<StarBoarded>().toList();
    expect(boards.length, 4);
    expect(boards.every((b) => b.shipId == 1), isTrue);
    expect([for (final b in boards) b.filled], [1, 2, 3, 4]);
    expect(boards.first.seats, 4);
    final dep = ev.whereType<StarDeparted>().single;
    expect(dep.shipId, 1);
    expect(s.bays.every((b) => b == null), isTrue);
    expect(s.score, StarportTuning.pointsPerDeparture);
    expect(s.queue.length, 8);
    // Event order: launched, boarded x4, departed.
    expect(ev.map((e) => e.runtimeType).toList(), [
      StarLaunched,
      StarBoarded,
      StarBoarded,
      StarBoarded,
      StarBoarded,
      StarDeparted,
    ]);
  });

  test('front passenger waits: nothing boards out of order', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 0, 1)],
        [...rep(1, 4), ...rep(0, 4)]));
    s.tap(0);
    expect(s.queue.length, 8);
    expect(s.bays.whereType<DockedShip>().single.filled, 0);
    expect(s.phase, StarportPhase.playing);
    s.tap(1);
    expect(s.phase, StarportPhase.levelClear);
  });

  test('level clear scores, counts a clean bonus; nextLevel loads the next', () {
    final s = simFor((n) => lvl(
          [ship(0, 0, 0, 0), ship(1, 1, 0, 1)],
          [...rep(0, 4), ...rep(1, 4)],
          number: n,
        ));
    s.step(10); // power 1 - 0.06
    s.tap(0);
    s.tap(1);
    expect(s.phase, StarportPhase.levelClear);
    expect(s.score, 2 * StarportTuning.pointsPerDeparture + StarportTuning.pointsPerLevel);
    expect(s.levelsCleared, 1);
    expect(s.bonus, 1);
    final ev = s.drainEvents();
    expect(ev.last, isA<StarLevelCleared>());
    expect((ev.last as StarLevelCleared).clean, isTrue);

    final before = s.power;
    s.nextLevel();
    expect(s.phase, StarportPhase.playing);
    expect(s.levelNumber, 2);
    expect(s.level.number, 2);
    expect(s.parked.length, 2);
    expect(s.power, closeTo((before + StarportTuning.clearRefill).clamp(0, 1), 1e-9));
    expect(s.undosLeft, StarportTuning.undosPerLevel);
    expect(s.levelClean, isTrue);
    expect((s.drainEvents().single as StarLevelStarted).levelNumber, 2);
    s.nextLevel(); // not in levelClear: no-op
    expect(s.levelNumber, 2);
  });

  test('a bump or an undo means no clean bonus', () {
    final bumped = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 2, 0)],
        [...rep(0, 4), ...rep(1, 4)]));
    bumped.tap(0); // bump
    bumped.tap(1);
    bumped.tap(0);
    expect(bumped.phase, StarportPhase.levelClear);
    expect(bumped.bonus, 0);
    expect(bumped.levelsCleared, 1);
    expect((bumped.drainEvents().last as StarLevelCleared).clean, isFalse);

    final undone = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 0, 1)],
        [...rep(0, 4), ...rep(1, 4)]));
    undone.tap(0);
    expect(undone.undo(), isTrue);
    undone.tap(0);
    undone.tap(1);
    expect(undone.bonus, 0);
  });

  test('gridlock: bays full and front passenger cannot board', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 0, 1)],
        [...rep(1, 4), ...rep(0, 4)],
        bays: 1));
    expect(s.tap(0), TapResult.launched);
    expect(s.phase, StarportPhase.over);
    expect(s.overReason, StarportOver.gridlock);
    expect(s.drainEvents().last, isA<StarGridlock>());
    expect(s.tap(1), TapResult.ignored);
    expect(s.undo(), isFalse);
  });

  test('power drains only while playing; power out ends the run', () {
    final s = StarportSim(levelSource: (n, _) => lvl([ship(0, 0, 0, 0)], rep(0, 4)), seed: 1);
    s.step(5);
    expect(s.power, 1);
    expect(s.time, 5);
    s.start();
    s.step(10);
    expect(s.power, closeTo(1 - 10 * StarportTuning.drainPerSecond(1), 1e-9));
    s.drainEvents();
    s.step(1000);
    expect(s.phase, StarportPhase.over);
    expect(s.overReason, StarportOver.power);
    expect(s.power, 0);
    expect(s.drainEvents().single, isA<StarPowerOut>());
    final t = s.time;
    s.step(1);
    expect(s.time, t + 1);
    expect(s.power, 0);
  });

  test('a bump can drain the last power; departures refund, capped at 1', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 2, 0)],
        [...rep(0, 4), ...rep(1, 4)]));
    s.power = 0.03;
    expect(s.tap(0), TapResult.blocked);
    expect(s.phase, StarportPhase.over);
    expect(s.overReason, StarportOver.power);

    final r = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 0, 1)],
        [...rep(0, 4), ...rep(1, 4)]));
    r.power = 0.5;
    r.tap(0);
    expect(r.power, closeTo(0.5 + StarportTuning.departRefund, 1e-9));
    r.power = 0.99;
    r.tap(1);
    expect(r.power, 1);
  });

  test('undo restores the exact state, only once per level, refunds taken back', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 0, 0, 1), ship(2, 1, 0, 2)],
        [...rep(0, 8), ...rep(1, 4)],
        bays: 3));
    s.step(10);
    final power0 = s.power;
    s.tap(0); // boards 4, departs
    expect(s.score, 1);
    expect(s.power, closeTo(power0 + StarportTuning.departRefund, 1e-9));
    s.drainEvents();
    expect(s.undo(), isTrue);
    expect(s.parked.map((e) => e.id).toList(), [0, 1, 2]);
    expect(s.bays.every((b) => b == null), isTrue);
    expect(s.queue.length, 12);
    expect(s.score, 0);
    expect(s.power, closeTo(power0, 1e-9));
    expect(s.undosLeft, 0);
    expect(s.levelClean, isFalse);
    final ev = s.drainEvents();
    expect((ev.single as StarUndone).shipId, 0);
    expect(s.undo(), isFalse);

    // Relaunch behaves identically (dock order restored too).
    s.tap(1);
    s.tap(0);
    expect(s.bays.every((b) => b == null) || s.score >= 1, isTrue);
  });

  test('undo restores half-filled bays and dock order', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0), ship(1, 1, 0, 1), ship(2, 0, 0, 2)],
        [0, 0, ...rep(1, 4), ...rep(0, 6)],
        bays: 3));
    s.tap(0); // two board, then front is colour 1: waits
    final filled = s.bays[0]!.filled;
    expect(filled, 2);
    s.tap(1); // 4 colour-1 board and depart; ship 0 gets next 2
    expect(s.undo(), isTrue);
    expect(s.parked.map((e) => e.id).toList(), [1, 2]);
    expect(s.bays[0]!.filled, 2);
    expect(s.bays[0]!.ship.id, 0);
    expect(s.bays[1], isNull);
    expect(s.queue, [...rep(1, 4), ...rep(0, 6)]);
  });

  test('cannot undo with nothing to undo, or after a level clear', () {
    final s = simFor((n) => lvl([ship(0, 0, 0, 0)], rep(0, 4)));
    expect(s.undo(), isFalse);
    s.tap(0);
    expect(s.phase, StarportPhase.levelClear);
    expect(s.undo(), isFalse);
  });

  test('determinism: same seed -> same level seeds; reset gives a fresh run', () {
    final seen = <int>[];
    StarportLevel src(int n, int seed) {
      seen.add(seed);
      return lvl([ship(0, 0, 0, 0)], rep(0, 4), number: n);
    }

    final a = StarportSim(levelSource: src, seed: 42);
    final b = StarportSim(levelSource: src, seed: 42);
    final c = StarportSim(levelSource: src, seed: 43);
    expect(a.levelSeed(1), b.levelSeed(1));
    expect(a.levelSeed(2), b.levelSeed(2));
    expect(a.levelSeed(1), isNot(a.levelSeed(2)));
    expect(a.levelSeed(1), isNot(c.levelSeed(1)));
    expect(seen.take(2), [a.levelSeed(1), b.levelSeed(1)]);

    a.start();
    a.tap(0);
    a.nextLevel();
    expect(seen.last, a.levelSeed(2));
    a.reset();
    expect(a.phase, StarportPhase.ready);
    expect(a.score, 0);
    expect(a.levelNumber, 1);
    expect(a.levelsCleared, 0);
    expect(a.power, 1);
    expect(a.drainEvents(), isEmpty);
  });
}
