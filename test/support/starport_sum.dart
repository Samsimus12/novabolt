// dart run test/support/starport_sum.dart [runs]: one-line summary per bot.
import 'dart:io';

import 'package:novabolt/arcade/starport/starport_sim.dart';

import 'starport_bots.dart';

double med(List<num> v) {
  if (v.isEmpty) return double.nan;
  final s = [...v]..sort();
  return s[s.length ~/ 2].toDouble();
}

void main(List<String> args) {
  final runs = args.isNotEmpty ? int.parse(args[0]) : 60;
  final out = StringBuffer();
  for (final bot in <StarportBot>[CasualBot(), ThoughtfulBot(), ExpertBot()]) {
    final recs = [for (var s = 1; s <= runs; s++) playRun(bot, s * 7919 + 13, maxLevel: 90)];
    final reached = [for (final r in recs) r.cleared + 1]..sort();
    final g = recs.where((r) => r.over == StarportOver.gridlock).length;
    out.write('${bot.name}: med ${med(reached).toStringAsFixed(0)} '
        '[${reached[runs ~/ 10]}-${reached[runs * 9 ~/ 10]}] grid ${(100 * g / runs).round()}%');
    if (bot is! CasualBot) {
      String s(int lvl) {
        final v = [for (final r in recs) for (final l in r.levels) if (l.level == lvl) l.powerStart];
        return v.isEmpty ? '-' : med(v).toStringAsFixed(2);
      }
      String e(int lvl) {
        final v = [for (final r in recs) for (final l in r.levels) if (l.level == lvl && l.cleared) l.powerEnd];
        return v.isEmpty ? '-' : med(v).toStringAsFixed(2);
      }
      out.write('  start@8,10,12,14,16,20,25: ${[8, 10, 12, 14, 16, 20, 25].map(s).join(",")}'
          '  end@10,14,18: ${[10, 14, 18].map(e).join(",")}');
    }
    out.writeln();
  }
  stdout.write(out);
}
