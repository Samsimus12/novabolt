import 'package:flutter_test/flutter_test.dart';

import 'support/balance_model.dart';

/// Analytic boss time-to-kill model (see support/balance_model.dart for the
/// assumptions). Prints the before/after table; the asserts pin the target
/// feel so a later tuning change that trivialises the late bosses fails.
void main() {
  final after = Rules.current();

  test('print boss time-to-kill table (before vs after)', () {
    final buf = StringBuffer();
    for (final p in [Profile.typical, Profile.strong]) {
      buf.writeln('${p.name}: boss  hp(before->after)  dps(b->a)  ttk seconds (before -> after)');
      for (var n = 1; n <= 10; n++) {
        final b = buildAt(p, Rules.legacy, n), a = buildAt(p, after, n);
        buf.writeln('  boss ${n.toString().padLeft(2)}  '
            '${Rules.legacy.bossHp(n).round()} -> ${after.bossHp(n).round()}  '
            '${b.dps.round()} -> ${a.dps.round()}  '
            '${ttk(p, Rules.legacy, n).toStringAsFixed(1)} -> ${ttk(p, after, n).toStringAsFixed(1)}');
      }
    }
    // ignore: avoid_print
    print(buf);
  });

  test('bosses 1-4 are not harder than before', () {
    for (var n = 1; n <= 4; n++) {
      expect(after.bossHp(n), Rules.legacy.bossHp(n), reason: 'boss $n HP unchanged');
      for (final p in [Profile.typical, Profile.strong]) {
        // The diminishing late upgrade steps only touch levels 6+, so early
        // damage stays within a whisker of before (a strong build that has
        // already levelled weapons past 5 and evolved loses more: that is the point).
        final floor = p == Profile.typical ? 0.85 : 0.40;
        expect(buildAt(p, after, n).dps, greaterThan(buildAt(p, Rules.legacy, n).dps * floor), reason: '${p.name} boss $n');
      }
    }
    expect(buildAt(Profile.typical, after, 1).dps, buildAt(Profile.typical, Rules.legacy, 1).dps);
  });

  test('typical build: first boss 25-45s, late bosses 45-80s', () {
    expect(ttk(Profile.typical, after, 1), inInclusiveRange(25, 45));
    for (var n = 5; n <= 10; n++) {
      expect(ttk(Profile.typical, after, n), inInclusiveRange(45, 80), reason: 'boss $n');
    }
  });

  test('strong build: faster, but never a few seconds', () {
    for (var n = 1; n <= 10; n++) {
      final t = ttk(Profile.strong, after, n);
      expect(t, greaterThan(n >= 7 ? 20 : 8), reason: 'boss $n took ${t.toStringAsFixed(1)}s');
      expect(t, lessThan(ttk(Profile.typical, after, n)), reason: 'boss $n');
    }
  });

  test('late bosses are no longer shorter than before for the strong build', () {
    for (var n = 7; n <= 10; n++) {
      expect(ttk(Profile.strong, after, n), greaterThan(ttk(Profile.strong, Rules.legacy, n) * 1.5), reason: 'boss $n');
    }
  });
}
