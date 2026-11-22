import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/stats/mission_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Mission _m(MissionType type, int target, {String? arg, int id = 1, int reward = 100}) =>
    Mission(type: type, tier: 0, target: target, reward: reward, arg: arg, id: id, seen: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mgr = MissionManager.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mgr.debugReset();
    mgr.random = math.Random(7);
    await mgr.init();
  });

  test('init fills three slots with distinct types and saves them', () async {
    expect(mgr.missions, hasLength(3));
    expect(mgr.missions.map((m) => m.type).toSet(), hasLength(3));
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('missions')!) as Map<String, dynamic>;
    expect(saved['v'], MissionManager.version);
    expect(saved['m'], hasLength(3));
  });

  test('a fresh fill never repeats a type (many seeds)', () async {
    for (var seed = 0; seed < 200; seed++) {
      SharedPreferences.setMockInitialValues({});
      mgr.debugReset();
      mgr.random = math.Random(seed);
      await mgr.init();
      expect(mgr.missions.map((m) => m.type).toSet(), hasLength(3), reason: 'seed $seed');
    }
  });

  test('kills count across runs, complete once, then claim pays and replaces', () async {
    mgr.debugSetMissions([
      _m(MissionType.kills, 5, id: 1, reward: 150),
      _m(MissionType.killType, 2, arg: 'Tank', id: 2),
      _m(MissionType.pickups, 3, id: 3),
    ]);
    final completed = <Mission>[];
    mgr.onCompleted = completed.add;

    mgr.startRun();
    for (var i = 0; i < 3; i++) {
      mgr.onKill('Grunt');
    }
    mgr.endRun(level: 4, daily: false);
    mgr.startRun();
    mgr.onKill('Tank');
    mgr.onKill('Speeder');
    mgr.onKill('Tank'); // 5th kill + 2nd tank
    mgr.onKill('Tank'); // ignored, both already done

    expect(completed.map((m) => m.id), [1, 2]);
    expect(mgr.missions[0].progress, 5);
    expect(mgr.claimableCount, 2);

    var paid = 0;
    final got = await mgr.claim(mgr.missions[0], addCoins: (n) async => paid += n);
    expect(got, 150);
    expect(paid, 150);
    expect(mgr.claimableCount, 1);
    expect(mgr.missions, hasLength(3));
    expect(mgr.missions[0].id, isNot(1));
    expect(mgr.missions[0].type, isNot(MissionType.kills));
    expect(mgr.missions.map((m) => m.type).toSet(), hasLength(3));
    // Claiming again does nothing.
    expect(await mgr.claim(completed.first, addCoins: (n) async => paid += n), 0);
    expect(paid, 150);
  });

  test('per-run missions keep the best value and need it in one run', () {
    mgr.debugSetMissions([
      _m(MissionType.reachLevel, 12, id: 1),
      _m(MissionType.dailyLevel, 6, id: 2),
      _m(MissionType.survive, 180, id: 3),
    ]);
    mgr.startRun();
    mgr.onLevel(9);
    mgr.onSurvived(100.7);
    mgr.endRun(level: 9, daily: false);
    expect(mgr.missions[0].progress, 9);
    expect(mgr.missions[1].progress, 0, reason: 'not a daily run');
    expect(mgr.missions[2].progress, 100);

    mgr.startRun();
    mgr.onLevel(3);
    mgr.onSurvived(50);
    expect(mgr.missions[0].progress, 9, reason: 'lower values never reduce progress');
    expect(mgr.missions[2].progress, 100);

    mgr.startRun(daily: true);
    mgr.onLevel(6);
    expect(mgr.missions[1].completed, isTrue);
    mgr.onLevel(12);
    mgr.onSurvived(180.2);
    expect(mgr.missions[0].completed, isTrue);
    expect(mgr.missions[2].completed, isTrue);
    expect(mgr.missions[2].progressLabel, '3:00 / 3:00');
  });

  test('boss missions: any, specific, flawless', () {
    mgr.debugSetMissions([
      _m(MissionType.bossKills, 2, id: 1),
      _m(MissionType.specificBoss, 1, arg: '1', id: 2),
      _m(MissionType.flawlessBoss, 1, id: 3),
    ]);
    mgr.onBossKill(0, flawless: false);
    expect(mgr.missions.map((m) => m.progress), [1, 0, 0]);
    mgr.onBossKill(1, flawless: true);
    expect(mgr.missions.every((m) => m.completed), isTrue);
    expect(mgr.missions[1].title, 'Target: Void Tyrant');
  });

  test('combo, elite, dash and pickup events', () {
    mgr.debugSetMissions([
      _m(MissionType.combo, 15, id: 1),
      _m(MissionType.eliteKills, 2, id: 2),
      _m(MissionType.dashKills, 2, id: 3),
    ]);
    for (var c = 1; c <= 14; c++) {
      mgr.onCombo(c);
    }
    mgr.onCombo(0); // combo broken
    expect(mgr.missions[0].progress, 14);
    mgr.onCombo(15);
    mgr.onEliteKill();
    mgr.onEliteKill();
    mgr.onDashKill();
    mgr.onPickup();
    expect(mgr.missions.map((m) => m.completed), [true, true, false]);
    expect(mgr.missions[2].progress, 1);
  });

  test('one free swap per day, not on completed missions', () async {
    var now = DateTime(2026, 11, 22, 20, 30);
    mgr.clock = () => now;
    final done = _m(MissionType.pickups, 1, id: 10)..completed = true..progress = 1;
    mgr.debugSetMissions([_m(MissionType.kills, 100, id: 11), done, _m(MissionType.combo, 15, id: 12)]);

    expect(mgr.canSwap, isTrue);
    expect(await mgr.swap(done), isNull);
    final fresh = await mgr.swap(mgr.missions[0]);
    expect(fresh, isNotNull);
    expect(mgr.missions[0].id, fresh!.id);
    expect(mgr.missions.map((m) => m.type).toSet(), hasLength(3));
    expect(mgr.canSwap, isFalse);
    expect(mgr.swapResetIn, const Duration(hours: 3, minutes: 30));
    expect(await mgr.swap(mgr.missions[2]), isNull);

    now = DateTime(2026, 11, 23, 0, 1);
    expect(mgr.canSwap, isTrue);
  });

  test('progress survives a restart after flush', () async {
    mgr.debugSetMissions([
      _m(MissionType.kills, 100, id: 1),
      _m(MissionType.pickups, 10, id: 2),
      _m(MissionType.combo, 15, id: 3),
    ]);
    for (var i = 0; i < 42; i++) {
      mgr.onKill('Grunt');
    }
    mgr.onPickup();
    await mgr.flush();

    mgr.debugReset();
    await mgr.init();
    expect(mgr.missions.map((m) => m.id), [1, 2, 3]);
    expect(mgr.missions[0].progress, 42);
    expect(mgr.missions[1].progress, 1);
  });

  test('a stored mission list from another version is replaced', () async {
    SharedPreferences.setMockInitialValues({
      'missions': jsonEncode({'v': 999, 'm': []}),
    });
    mgr.debugReset();
    await mgr.init();
    expect(mgr.missions, hasLength(3));
  });

  test('unavailable features are never rolled', () async {
    mgr.debugReset();
    mgr.elitesAvailable = false;
    mgr.dashAvailable = false;
    for (var seed = 0; seed < 40; seed++) {
      SharedPreferences.setMockInitialValues({});
      mgr.debugSetMissions([]);
      mgr.random = math.Random(seed);
      await mgr.init();
      for (final m in mgr.missions) {
        expect(m.type, isNot(MissionType.eliteKills));
        expect(m.type, isNot(MissionType.dashKills));
        expect(m.reward, inInclusiveRange(100, 400));
      }
    }
  });

  test('disabled manager ignores events', () {
    mgr.debugSetMissions([
      _m(MissionType.kills, 5, id: 1),
      _m(MissionType.reachLevel, 5, id: 2),
      _m(MissionType.pickups, 5, id: 3),
    ]);
    mgr.enabled = false;
    mgr.onKill('Grunt');
    mgr.onLevel(4);
    mgr.onPickup();
    expect(mgr.missions.map((m) => m.progress), [0, 0, 0]);
  });
}
