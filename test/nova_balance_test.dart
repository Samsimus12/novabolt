// ignore_for_file: avoid_print
// Nova balance: fires a full Nova of every mode at the same fixed field (see
// support/nova_bench.dart) and checks that, per mode,
//   damage per Nova x chargeScale
// sits near a target curve: the laser's damage +4% per boss tier (so later
// beams are a small reward). chargeScale is in the product because a strong
// beam that charges slower is the same trade as one that hits for less.
// Event Horizon (erases shots) is credited 80%; Shadow Veil (no damage of its
// own: slows everything to 30%, hits +35%) is measured on the player's guns
// instead: extra damage from +35% hits, plus the hull an approaching wave
// would have cost (enemy-seconds on top of the ship avoided x a mid-game
// grunt's contact damage per second).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/data/monster_data.dart';
import 'package:novabolt/game/data/nova_mode.dart';

import 'support/nova_bench.dart';

void main() {
  testWidgets('every Nova beam is worth about the same, rising ~4% per boss', (t) async {
    const seeds = [1, 2, 3, 4, 5, 6, 7, 8];
    const band = 15; // percent
    double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    var bw = 0.0, bb = 0.0;
    for (final s in seeds) {
      final b = await benchNova(t, null, hull: 10, seed: s);
      bw += b.waveDamage / seeds.length;
      bb += b.bossDamage / seeds.length;
    }
    print('baseline (guns only, 5 s): wave ${bw.toStringAsFixed(0)} boss ${bb.toStringAsFixed(0)}');
    double? laser;
    for (final m in NovaMode.values) {
      if (m == NovaMode.shadowReaper) {
        final secs = 5 * m.durationScale;
        var extra = 0.0, saved = 0.0;
        for (final s in seeds) {
          final n0 = await benchVeil(t, veil: false, seed: s, near: true, seconds: secs);
          final n1 = await benchVeil(t, veil: true, seed: s, near: true, seconds: secs);
          extra += (n1.damage - n0.damage) / seeds.length;
          final f0 = await benchVeil(t, veil: false, seed: s, seconds: secs);
          final f1 = await benchVeil(t, veil: true, seed: s, seconds: secs);
          saved += (f0.exposure - f1.exposure) * gruntStats.scaled(10).contactDamagePerSecond / seeds.length;
        }
        final eff = (extra + saved) * m.chargeScale;
        final target = laser! * (1 + 0.04 * m.index);
        final err = (eff / target - 1) * 100;
        print('${m.name.padRight(15)} dur x${m.durationScale} charge x${m.chargeScale} secs ${secs.toStringAsFixed(1)} extra gun damage ${extra.toStringAsFixed(0)} + hull saved ${saved.toStringAsFixed(0)} x charge = ${eff.toStringAsFixed(0)} target ${target.toStringAsFixed(0)} off ${err.toStringAsFixed(0)}%');
        expect(err.abs(), lessThan(band), reason: '${m.name} is ${err.toStringAsFixed(0)}% off its target');
        continue;
      }
      final tot = <double>[], boss = <double>[], secs = <double>[];
      var kills = 0;
      for (final s in seeds) {
        final big = await benchNova(t, m, hull: 10, seed: s);
        final gun = (bw + bb) / 5 * big.seconds; // what the guns alone do meanwhile
        tot.add(big.total - gun);
        boss.add(big.bossDamage - bb / 5 * big.seconds);
        secs.add(big.seconds);
        kills += (await benchNova(t, m, seed: s)).kills;
      }
      final raw = avg(tot), eff = raw * m.chargeScale;
      laser ??= eff;
      final credit = m == NovaMode.singularity ? 0.8 : 1.0;
      final target = laser * (1 + 0.04 * m.index) * credit;
      final err = (eff / target - 1) * 100;
      print('${m.name.padRight(15)} dur x${m.durationScale} charge x${m.chargeScale} secs ${avg(secs).toStringAsFixed(1)} '
          'dmg/Nova ${raw.toStringAsFixed(0).padLeft(5)} (boss ${avg(boss).toStringAsFixed(0).padLeft(4)}) '
          'x charge = ${eff.toStringAsFixed(0).padLeft(5)} target ${target.toStringAsFixed(0).padLeft(5)} off ${err.toStringAsFixed(0)}% '
          'kills ${(kills / seeds.length).toStringAsFixed(1)}/15');
      expect(err.abs(), lessThan(band), reason: '${m.name} is ${err.toStringAsFixed(0)}% off its target');
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });
}
