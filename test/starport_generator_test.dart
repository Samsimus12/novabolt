import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/starport/starport_generator.dart';
import 'package:novabolt/arcade/starport/starport_solver.dart';
import 'package:novabolt/arcade/starport/starport_types.dart';

StarShip ship(int id, int color, Facing f, int col, int row,
        [ShipKind kind = ShipKind.shuttle]) =>
    StarShip(id: id, color: color, kind: kind, facing: f, col: col, row: row);

List<int> rep(int c, int n) => List.filled(n, c);

StarportLevel hand(List<StarShip> ships, List<int> queue, int bays,
        {int cols = 4, int rows = 1}) =>
    StarportLevel(
        number: 1,
        cols: cols,
        rows: rows,
        ships: ships,
        queue: queue,
        bays: bays,
        colorCount: 2);

void main() {
  group('solver', () {
    // A (colour 0) at cols 0-1 facing right is blocked by B (colour 1).
    final a = ship(10, 0, Facing.right, 0, 0);
    final b = ship(11, 1, Facing.right, 2, 0);

    test('solvable level returns a verified order', () {
      final lvl = hand([a, b], [...rep(1, 4), ...rep(0, 4)], 1);
      expect(lvl.countsMatch, isTrue);
      final sol = solveStarport(lvl);
      expect(sol, [11, 10]);
      expect(verifyStarportSolution(lvl, sol!), isTrue);
    });

    test('bay-limited level is unsolvable with 1 bay, solvable with 2', () {
      final q = [...rep(0, 4), ...rep(1, 4)];
      final one = hand([a, b], q, 1);
      final r = solveStarportDetailed(one);
      expect(r.solution, isNull);
      expect(r.provenUnsolvable, isTrue);
      final two = hand([a, b], q, 2);
      final sol = solveStarport(two);
      expect(sol, [11, 10]);
      expect(verifyStarportSolution(two, sol!), isTrue);
    });

    test('ships facing each other can never leave', () {
      final x = ship(1, 0, Facing.right, 0, 0);
      final y2 = ship(2, 1, Facing.left, 3, 0); // tail col 3, nose col 2
      final lvl = hand([x, y2], [...rep(0, 4), ...rep(1, 4)], 5);
      expect(lvl.layoutValid, isTrue);
      final r = solveStarportDetailed(lvl);
      expect(r.provenUnsolvable, isTrue);
    });

    test('exhausted budget is reported, not mistaken for unsolvable', () {
      final lvl = generateStarportLevel(30, seed: 3);
      final r = solveStarportDetailed(lvl, maxNodes: 1);
      expect(r.solution, isNull);
      expect(r.exhausted, isTrue);
      expect(r.provenUnsolvable, isFalse);
    });

    test('verify rejects a blocked or short order', () {
      final lvl = hand([a, b], [...rep(1, 4), ...rep(0, 4)], 1);
      expect(verifyStarportSolution(lvl, [10, 11]), isFalse); // A is blocked
      expect(verifyStarportSolution(lvl, [11]), isFalse); // queue not empty
    });

    test('stats on a hand level', () {
      final lvl = hand([a, b], [...rep(0, 4), ...rep(1, 4)], 2);
      final st = analyzeStarportLevel(lvl);
      expect(st.ships, 2);
      expect(st.launchableAtStart, 1);
      expect(st.maxBlockDepth, 1);
      expect(st.blockLinks, 1);
      expect(st.solvable, isTrue);
      expect(st.deadEndFirstMoves, 0);
    });

    test('dead-end first moves are counted', () {
      // Two free ships, one bay: launching colour 1 first strands colour 0.
      final p = ship(1, 0, Facing.up, 0, 1); // rows 1..2, nose row 1... up from tail row 2
      final q = ship(2, 1, Facing.down, 1, 0);
      final lvl = hand([p, q], [...rep(0, 4), ...rep(1, 4)], 1, cols: 2, rows: 3);
      expect(lvl.layoutValid, isTrue);
      final st = analyzeStarportLevel(lvl);
      expect(st.launchableAtStart, 2);
      expect(st.deadEndFirstMoves, 1);
      expect(st.solvable, isTrue);
    });
  });

  group('generator', () {
    test('deterministic for (number, seed), varies with them', () {
      String sig(StarportLevel l) =>
          '${l.cols}x${l.rows}|${l.bays}|${l.queue.join()}|'
          '${[for (final s in l.ships) '${s.color}${s.kind.index}${s.facing.index}@${s.col},${s.row}'].join(';')}';
      for (final n in [1, 7, 25, 60]) {
        expect(sig(generateStarportLevel(n, seed: 42)), sig(generateStarportLevel(n, seed: 42)));
      }
      expect(sig(generateStarportLevel(25, seed: 1)), isNot(sig(generateStarportLevel(25, seed: 2))));
      expect(sig(generateStarportLevel(25, seed: 1)), isNot(sig(generateStarportLevel(26, seed: 1))));
    });

    test('levels 1-60 x 20 seeds: valid, counts match, bounded, solvable', () {
      for (var n = 1; n <= 60; n++) {
        final p = starportParamsFor(n);
        for (var seed = 0; seed < 20; seed++) {
          final l = generateStarportLevel(n, seed: seed);
          final tag = 'level $n seed $seed';
          expect(l.number, n, reason: tag);
          expect(l.layoutValid, isTrue, reason: tag);
          expect(l.countsMatch, isTrue, reason: tag);
          expect(l.cols <= 6 && l.rows <= 8, isTrue, reason: tag);
          expect(l.bays >= StarportTuning.minBays && l.bays <= StarportTuning.maxBays, isTrue,
              reason: tag);
          expect(l.ships.length <= 16 && l.ships.length >= 4, isTrue, reason: tag);
          expect(l.ships.map((s) => s.id).toSet().length, l.ships.length, reason: tag);
          if (n <= 3) expect(l.ships.every((s) => s.kind == ShipKind.shuttle), isTrue, reason: tag);
          expect(l.colorCount, lessThanOrEqualTo(p.colors), reason: tag);
          final sol = solveStarport(l);
          expect(sol, isNotNull, reason: tag);
          expect(verifyStarportSolution(l, sol!), isTrue, reason: tag);
        }
      }
    });

    test('level 1 is gentle: shuttles, 2 colours, 5 bays, nothing can go wrong', () {
      for (var seed = 0; seed < 20; seed++) {
        final l = generateStarportLevel(1, seed: seed);
        expect(l.cols, 4);
        expect(l.rows, 5);
        expect(l.bays, 5);
        expect(l.colorCount, 2);
        final st = analyzeStarportLevel(l);
        expect(st.randomWinRate, 1.0);
        expect(st.deadEndFirstMoves, 0);
      }
    });

    test('difficulty trends upward with the level', () {
      double avg(int from, int to) {
        var sum = 0.0, n = 0;
        for (var lv = from; lv <= to; lv++) {
          for (var seed = 0; seed < 6; seed++) {
            sum += starportHardness(analyzeStarportLevel(generateStarportLevel(lv, seed: seed)));
            n++;
          }
        }
        return sum / n;
      }

      final b1 = avg(1, 3), b2 = avg(5, 8), b3 = avg(11, 15), b4 = avg(25, 30), b5 = avg(50, 60);
      expect(b1, lessThan(b2));
      expect(b2, lessThan(b3));
      expect(b3, lessThan(b4));
      expect(b4, lessThan(b5 + 5)); // late levels plateau near the target cap
      expect(b5, greaterThan(b2 * 2));
    });

    test('generation stays fast (levels 1-60)', () {
      final sw = Stopwatch();
      var worst = 0;
      var total = 0;
      var count = 0;
      for (var n = 1; n <= 60; n++) {
        for (var seed = 0; seed < 5; seed++) {
          sw
            ..reset()
            ..start();
          generateStarportLevel(n, seed: seed);
          final us = sw.elapsedMicroseconds;
          total += us;
          count++;
          if (us > worst) worst = us;
        }
      }
      // ignore: avoid_print
      print('generation: mean ${(total / count / 1000).toStringAsFixed(2)} ms, '
          'worst ${(worst / 1000).toStringAsFixed(2)} ms');
      expect(worst, lessThan(50000));
    });

    test('report table', () {
      for (final l in [1, 2, 3, 4, 6, 8, 10, 12, 15, 20, 30, 45, 60]) {
        var traps = 0, open = 0, depth = 0, ships = 0, liners = 0, col = 0, nodes = 0;
        var rnd = 0.0, hard = 0.0;
        const seeds = 20;
        for (var s = 0; s < seeds; s++) {
          final lvl = generateStarportLevel(l, seed: s + 1);
          final st = analyzeStarportLevel(lvl);
          traps += st.deadEndFirstMoves;
          open += st.launchableAtStart;
          depth += st.maxBlockDepth;
          nodes += st.solverNodes;
          rnd += st.randomWinRate;
          hard += starportHardness(st);
          ships += lvl.ships.length;
          liners += lvl.ships.where((x) => x.length == 3).length;
          col += lvl.colorCount;
        }
        String f(num x) => (x / seeds).toStringAsFixed(1);
        // ignore: avoid_print
        print('TABLE L$l ${starportParamsFor(l)} | ships=${f(ships)} liners=${f(liners)} '
            'col=${f(col)} open=${f(open)} depth=${f(depth)} traps=${f(traps)} '
            'randomWin=${(rnd / seeds).toStringAsFixed(2)} hardness=${f(hard)} nodes=${f(nodes)}');
      }
    });
  });
}
