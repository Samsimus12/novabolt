import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/starport/starport_sim.dart';
import 'package:novabolt/arcade/starport/starport_types.dart';

import 'support/starport_bots.dart';

/// Loose pins on Starport's difficulty and clock, using simulated players
/// (test/support/starport_bots.dart). Few seeds, so the bounds are wide;
/// `dart run test/support/starport_sum.dart 60` gives the precise numbers.
void main() {
  final seeds = [for (var i = 1; i <= 8; i++) i * 7919 + 13];

  double median(List<num> v) {
    final s = [...v]..sort();
    return s[s.length ~/ 2].toDouble();
  }

  test('levels 1-3 are always cleared, even by a casual player', () {
    final bot = CasualBot();
    for (final s in seeds) {
      final r = playRun(bot, s, maxLevel: 3, infinitePower: true);
      expect(r.cleared, 3, reason: 'seed $s');
    }
  });

  test('the expert (solver) clears every level it is given, power aside', () {
    final bot = ExpertBot();
    for (final s in seeds.take(4)) {
      final r = playRun(bot, s, maxLevel: 50, infinitePower: true);
      expect(r.over, isNull, reason: 'seed $s ended ${r.over}');
      expect(r.cleared, 50);
    }
  });

  test('casual players reach roughly level 7-13 and are stopped by gridlock', () {
    final bot = CasualBot();
    final runs = [for (final s in seeds) playRun(bot, s)];
    final reached = [for (final r in runs) r.cleared + 1];
    expect(median(reached), inInclusiveRange(7, 13));
    expect(runs.where((r) => r.over == StarportOver.gridlock).length, greaterThanOrEqualTo(6));
  });

  test('thoughtful players reach roughly level 12-20, mostly out of power', () {
    final bot = ThoughtfulBot();
    final runs = [for (final s in seeds) playRun(bot, s)];
    final reached = [for (final r in runs) r.cleared + 1];
    expect(median(reached), inInclusiveRange(12, 20));
    expect(runs.where((r) => r.over == StarportOver.power).length, greaterThanOrEqualTo(6));
    // Power is a pressure, not a wall, in the early/middle game.
    for (final r in runs) {
      for (final l in r.levels.where((l) => l.level >= 4 && l.level <= 10 && l.cleared)) {
        expect(l.powerEnd, greaterThan(0.3), reason: 'level ${l.level}');
      }
    }
  });

  test('experts last 25+ levels and are ended by the clock', () {
    final bot = ExpertBot();
    final runs = [for (final s in seeds) playRun(bot, s)];
    final reached = [for (final r in runs) r.cleared + 1];
    expect(median(reached), greaterThanOrEqualTo(25));
    expect(runs.where((r) => r.over == StarportOver.power).length, greaterThanOrEqualTo(7));
    expect(runs.where((r) => r.over == StarportOver.gridlock), isEmpty);
  });

  test('bumps hurt but do not end a run alone', () {
    // Ten bumps at level 10 cost 0.5 of a full meter: survivable, and costly.
    expect(StarportTuning.bumpCost * 10, lessThan(0.6));
    expect(StarportTuning.bumpCost, greaterThanOrEqualTo(0.04));
    // A bump costs roughly 2-4 seconds of drain at mid levels.
    final secs = StarportTuning.bumpCost / StarportTuning.drainPerSecond(10);
    expect(secs, inInclusiveRange(2, 4));
  });
}
