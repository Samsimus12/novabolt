// dart run test/support/starport_bench.dart [runs] [infinite]
import 'dart:io';

import 'package:novabolt/arcade/starport/starport_sim.dart';

import 'starport_bots.dart';

double median(List<num> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2].toDouble();
}

void main(List<String> args) {
  final runs = args.isNotEmpty ? int.parse(args[0]) : 60;
  final inf = args.length > 1 && args[1] == 'inf';
  final bots = <StarportBot Function()>[() => CasualBot(), () => ThoughtfulBot(), () => ExpertBot()];
  for (final make in bots) {
    final bot = make();
    final recs = <RunRecord>[];
    final sw = Stopwatch()..start();
    for (var s = 1; s <= runs; s++) {
      recs.add(playRun(bot, s * 7919 + 13, infinitePower: inf, maxLevel: inf ? 70 : 70));
    }
    stdout.writeln('=== ${bot.name} (${inf ? "infinite power" : "real power"}) ${sw.elapsed.inSeconds}s');
    final reached = [for (final r in recs) r.cleared + 1];
    reached.sort();
    stdout.writeln('median level reached ${median(reached)}  p25 ${reached[reached.length ~/ 4]} p75 ${reached[reached.length * 3 ~/ 4]}  max ${reached.last}');
    final grid = recs.where((r) => r.over == StarportOver.gridlock).length;
    final pow = recs.where((r) => r.over == StarportOver.power).length;
    stdout.writeln('run ends: gridlock $grid, power $pow, survived ${runs - grid - pow}');
    stdout.writeln('lvl  n  win%  pStart  pEnd   sec   bumps  end(g/p)');
    for (var lo = 1; lo <= 70; lo += 1) {
      final ls = [for (final r in recs) for (final l in r.levels) if (l.level == lo) l];
      if (ls.isEmpty) continue;
      final w = ls.where((l) => l.cleared).toList();
      final g = ls.where((l) => l.over == StarportOver.gridlock).length;
      final p = ls.where((l) => l.over == StarportOver.power).length;
      String f(double x) => x.toStringAsFixed(2);
      stdout.writeln('${lo.toString().padLeft(3)} ${ls.length.toString().padLeft(3)} '
          '${(100 * w.length / ls.length).toStringAsFixed(0).padLeft(4)}  '
          '${f(ls.map((l) => l.powerStart).reduce((a, b) => a + b) / ls.length)}  '
          '${w.isEmpty ? "  -  " : f(median([for (final l in w) l.powerEnd]))}  '
          '${w.isEmpty ? "  - " : median([for (final l in w) l.seconds]).toStringAsFixed(0).padLeft(4)}  '
          '${w.isEmpty ? " - " : (w.map((l) => l.bumps).reduce((a, b) => a + b) / w.length).toStringAsFixed(1)}   $g/$p');
    }
  }
}
