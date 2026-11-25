// B1/B2 verification on the real main menu: slogan text and the best-level /
// total-kills chips.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/screens/main_menu_screen.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('menu shows the new slogan, best level and TOTAL kills', (tester) async {
    SharedPreferences.setMockInitialValues({
      'stats_best_level': 7,
      'stats_best_kills': 120,
      'stats_total_kills': 4321,
      'stats_total_runs': 9,
    });
    await tester.runAsync(() async {
      await CoinManager.instance.init();
      await StatsManager.instance.init();
    });
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(MaterialApp(home: MainMenuScreen(onPlay: () {})));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Survive. Upgrade. Conquer.'), findsOneWidget);
    expect(find.text('Ten bosses. One ship.'), findsNothing);
    expect(find.text('total kills'), findsOneWidget);
    expect(find.text('best kills'), findsNothing);
    expect(find.text('best level'), findsOneWidget);
    expect(find.text('Lv 7'), findsOneWidget);
    expect(find.textContaining('4,321'), findsOneWidget);
    expect(find.text('120'), findsNothing, reason: 'best kills must not be what the chip shows');
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a fresh install (no kills) hides the stat chips; one kill shows them', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      await CoinManager.instance.init();
      await StatsManager.instance.init();
    });
    await tester.binding.setSurfaceSize(const Size(400, 860));
    await tester.pumpWidget(MaterialApp(home: MainMenuScreen(onPlay: () {})));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('total kills'), findsNothing);

    SharedPreferences.setMockInitialValues({'stats_total_kills': 1});
    await tester.runAsync(StatsManager.instance.init);
    await tester.pumpWidget(MaterialApp(key: UniqueKey(), home: MainMenuScreen(onPlay: () {})));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('total kills'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
