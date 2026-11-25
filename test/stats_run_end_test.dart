// B1 verification: menu bests/totals must be right after every way a run can
// end, survive a restart, and the autosave timer must not lose kills.
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<int?> _stored(String k) async => (await SharedPreferences.getInstance()).getInt(k);

void main() {
  final s = StatsManager.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await s.flush(); // cancel any pending autosave from the last test
    SharedPreferences.setMockInitialValues({});
    await s.init();
  });

  void kills(int n) {
    for (var i = 0; i < n; i++) {
      s.addKill();
    }
  }

  test('fresh install: level 1, no kills', () {
    expect((s.bestLevel, s.bestKills, s.totalKills, s.totalRuns), (1, 0, 0, 0));
  });

  test('death: submitRun raises bests, adds totals and persists immediately', () async {
    s.startRun();
    kills(25);
    expect(s.submitRun(level: 4, kills: 25, combo: 9), isTrue);
    // No explicit flush: the run end itself must have saved (let the async write finish).
    await Future<void>.delayed(Duration.zero);
    expect(await _stored('stats_total_kills'), 25);
    expect(await _stored('stats_best_level'), 4);
    expect(await _stored('stats_best_kills'), 25);
    expect(await _stored('stats_best_combo'), 9);
  });

  test('a worse run never lowers bests but still adds to the total', () async {
    s.startRun();
    kills(30);
    s.submitRun(level: 6, kills: 30);
    s.startRun();
    kills(5);
    expect(s.submitRun(level: 2, kills: 5), isFalse);
    expect((s.bestLevel, s.bestKills, s.totalKills, s.totalRuns), (6, 30, 35, 2));
  });

  test('quit/abandon (checkpoint, run never submitted) shows on the menu and survives a restart', () async {
    s.startRun();
    kills(18);
    s.checkpointRun(level: 5, kills: 18, combo: 4);
    expect((s.bestLevel, s.bestKills, s.bestCombo, s.totalKills), (5, 18, 4, 18));
    await s.flush();
    await s.init();
    expect((s.bestLevel, s.bestKills, s.totalKills), (5, 18, 18));
  });

  test('checkpoint twice (background, then Save and exit) is idempotent', () async {
    s.startRun();
    kills(10);
    s.checkpointRun(level: 3, kills: 10);
    s.checkpointRun(level: 3, kills: 10);
    s.checkpointRun(level: 4, kills: 14);
    expect((s.bestLevel, s.bestKills, s.totalKills), (4, 14, 10));
    expect(s.submitRun(level: 4, kills: 14), isTrue, reason: 'the run did beat the old best');
    expect(s.submitRun(level: 4, kills: 14), isFalse);
  });

  test('a checkpoint that beats nothing does not claim a new best later', () {
    s.startRun();
    kills(50);
    s.submitRun(level: 8, kills: 50);
    s.startRun();
    s.checkpointRun(level: 2, kills: 3);
    expect(s.submitRun(level: 2, kills: 3), isFalse);
  });

  test('new-best flag from an abandoned run does not leak into the next run', () {
    s.startRun();
    s.checkpointRun(level: 9, kills: 90); // best, then abandoned (never submitted)
    s.startRun();
    expect(s.submitRun(level: 1, kills: 1), isFalse);
  });

  test('revive: the same run submitted twice (death, revive, death) keeps totals right', () async {
    s.startRun(); // revive does NOT call startRun again
    kills(20);
    expect(s.submitRun(level: 3, kills: 20), isTrue);
    kills(15); // after the revive
    expect(s.submitRun(level: 5, kills: 35), isTrue);
    expect((s.bestLevel, s.bestKills, s.totalKills, s.totalRuns), (5, 35, 35, 1));
    await s.flush();
    await s.init();
    expect((s.bestLevel, s.bestKills, s.totalKills), (5, 35, 35));
  });

  test('revive then quit: checkpoint after a submitted death still persists the extra kills', () async {
    s.startRun();
    kills(20);
    s.submitRun(level: 3, kills: 20);
    kills(7);
    s.checkpointRun(level: 4, kills: 27);
    await s.flush();
    await s.init();
    expect((s.bestLevel, s.bestKills, s.totalKills), (4, 27, 27));
  });

  testWidgets('autosave: kills are written ~3s after the first unsaved kill with no other event', (tester) async {
    s.addKill();
    s.addKill();
    await tester.pump(const Duration(seconds: 2));
    s.addKill();
    await tester.pump(const Duration(milliseconds: 1500)); // 3.5s after the first kill
    final saved = await tester.runAsync(() => _stored('stats_total_kills'));
    expect(saved, 3);
    expect(s.totalKills, 3);
  });

  testWidgets('flush cancels the pending timer (nothing left pending)', (tester) async {
    s.addKill();
    await tester.runAsync(s.flush);
    // testWidgets fails the test at the end if a Timer is still pending.
    expect(s.totalKills, 1);
  });

  test('boss kills and flawless counts persist with bests', () async {
    s.startRun();
    s.recordBossKill(2, flawless: true);
    s.recordBossKill(3, flawless: false);
    await s.flush();
    await s.init();
    expect((s.totalBossKills, s.flawlessBossKills, s.bossesDiscovered), (2, 1, 2));
    expect(s.hasDefeatedBoss(2) && s.hasDefeatedBoss(3) && !s.hasDefeatedBoss(0), isTrue);
  });
}
