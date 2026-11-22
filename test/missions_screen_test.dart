import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/screens/missions_screen.dart';
import 'package:novabolt/stats/mission_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder _label(String l) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == l);

void main() {
  testWidgets('claiming a finished mission pays out and brings a new one', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await CoinManager.instance.init();
    final mgr = MissionManager.instance;
    mgr.debugReset();
    mgr.random = math.Random(3);
    await tester.runAsync(mgr.init);
    final done = Mission(type: MissionType.pickups, tier: 0, target: 1, reward: 100, id: 900, progress: 1, completed: true);
    mgr.debugSetMissions([done, ...mgr.missions.skip(1)]);
    final coinsBefore = CoinManager.instance.totalCoins;

    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(const MaterialApp(home: MissionsScreen()));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Scavenger'), findsOneWidget);
    expect(_label('Claim 100 NOVA'), findsOneWidget);
    expect(_label('Swap this mission'), findsNWidgets(2));

    await tester.runAsync(() async {
      await tester.tap(_label('Claim 100 NOVA'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(seconds: 1));
    expect(CoinManager.instance.totalCoins, coinsBefore + 100);
    expect(mgr.missions.any((m) => m.id == 900), isFalse);
    expect(mgr.claimableCount, 0);
    expect(find.text('New'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    mgr.debugReset();
  });
}
