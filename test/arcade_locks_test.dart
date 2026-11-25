// The locked-cabinet design: the unlock banner's bookkeeping (a boss unlock
// is announced once, even if the app restarted in between; a game kept from
// before unlocks is not), the hub banner and "New" chip, and the unlock
// sheet's two routes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/arcade_screen.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final am = ArcadeManager.instance;

Future<void> boot(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await StatsManager.instance.init();
  await CoinManager.instance.init();
  await am.init();
}

Future<void> mount(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    if (!d.exception.toString().contains('overflowed')) old?.call(d);
  };
  addTearDown(() => FlutterError.onError = old);
  await t.pumpWidget(const MaterialApp(home: ArcadeScreen()));
  await t.pump(const Duration(seconds: 2));
}

Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('unseen unlocks', () {
    test('a boss unlock granted at start-up is still announced, once', () async {
      await boot({'stats_bosses_defeated': ['1']}); // boss 2 -> Ground Assault
      expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
      await Future<void>.delayed(Duration.zero); // let the save land
      // The app restarts before the hub is opened.
      await am.init();
      expect(am.takeNewUnlocks(), [ArcadeGame.groundAssault]);
      expect(am.takeNewUnlocks(), isEmpty);
      await Future<void>.delayed(Duration.zero);
      await am.init();
      expect(am.takeNewUnlocks(), isEmpty, reason: 'announced once, persisted as seen');
    });

    test('a game kept from before unlocks (already played) is not news', () async {
      await boot({'arcade_plays_invaders': 3});
      expect(am.isUnlocked(ArcadeGame.swarmSiege), isTrue);
      expect(am.takeNewUnlocks(), isEmpty);
    });

    test('a bought game is not in the boss list', () async {
      await boot({'coins_total': 600});
      expect(await am.buy(ArcadeGame.groundAssault), isTrue);
      expect(am.takeNewUnlocks(), isEmpty);
    });
  });

  group('hub', () {
    testWidgets('a boss unlock shows the banner and the New chip', (t) async {
      await boot({'stats_bosses_defeated': ['0', '1', '2']});
      await mount(t);
      expect(find.text('Unlocked: Ground Assault and Swarm Siege'), findsOneWidget);
      expect(find.text('New'), findsWidgets);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('no banner without news', (t) async {
      await boot({});
      await mount(t);
      expect(find.textContaining('Unlocked:'), findsNothing);
      expect(find.text('New'), findsNothing);
      await finish(t);
    });

    testWidgets('the sheet shows both routes and the boss progress', (t) async {
      await boot({'coins_total': 900, 'stats_bosses_defeated': ['0']});
      await mount(t);
      final card = find.textContaining('Beat boss 2 in the main game');
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Ground Assault is locked'), findsOneWidget);
      expect(find.text('Beat boss 2 in the main game'), findsOneWidget);
      expect(find.text('Free, and it stays unlocked.'), findsOneWidget);
      expect(find.text('Furthest so far: boss 1.'), findsOneWidget);
      expect(find.text('Or unlock it now for '), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      await t.tap(find.text('Not now'));
      await t.pump(const Duration(milliseconds: 600));
      await finish(t);
    });

    testWidgets('buying plays the unlock moment and leaves the New chip', (t) async {
      await boot({'coins_total': 900});
      await mount(t);
      final card = find.textContaining('Beat boss 2 in the main game');
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 600));
      await t.runAsync(() async {
        await t.tap(find.text('Unlock'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Unlocked'), findsOneWidget, reason: 'the badge springs open mid-shutter');
      await t.pump(const Duration(seconds: 2));
      expect(find.text('Unlocked'), findsNothing);
      expect(find.text('New'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    });
  });
}
