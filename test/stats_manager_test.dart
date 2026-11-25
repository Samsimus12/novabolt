import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await StatsManager.instance.init();
  });

  test('a finished run updates bests and totals, and survives a restart', () async {
    final s = StatsManager.instance;
    s.startRun();
    for (var i = 0; i < 40; i++) {
      s.addKill();
    }
    expect(s.submitRun(level: 5, kills: 40, combo: 7), isTrue);
    await s.flush();
    expect(s.totalKills, 40);
    await s.init(); // "restart": reload from prefs
    expect((s.bestLevel, s.bestKills, s.totalKills), (5, 40, 40));
  });

  test('leaving a run early still updates the menu numbers and keeps the new-best flag', () async {
    final s = StatsManager.instance;
    s.startRun();
    for (var i = 0; i < 12; i++) {
      s.addKill();
    }
    s.checkpointRun(level: 3, kills: 12);
    expect((s.bestLevel, s.bestKills), (3, 12));
    await s.flush();
    await s.init();
    expect((s.bestLevel, s.bestKills, s.totalKills), (3, 12, 12));
    // The run is then lost without raising anything further: still a new best.
    expect(s.submitRun(level: 3, kills: 12), isTrue);
    expect(s.submitRun(level: 3, kills: 12), isFalse);
  });

  test('flush saves kills tallied since the last event', () async {
    final s = StatsManager.instance;
    s.addKill();
    s.addKill();
    await s.flush();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('stats_total_kills'), 2);
  });
}
