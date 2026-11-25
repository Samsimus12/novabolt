// B4 verification, part 2: "announced exactly once" bookkeeping, restarts,
// legacy players, the hub banner, and the shortfall line.
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

/// A "restart": settle writes, then reload everything from what was saved.
Future<void> restart() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await StatsManager.instance.flush();
  await StatsManager.instance.init();
  await CoinManager.instance.init();
  await am.init();
}

Future<void> mount(WidgetTester t, {int pumps = 2}) async {
  await t.binding.setSurfaceSize(const Size(390, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    if (!d.exception.toString().contains('overflowed')) old?.call(d);
  };
  addTearDown(() => FlutterError.onError = old);
  await t.pumpWidget(MaterialApp(key: UniqueKey(), home: const ArcadeScreen()));
  await t.pump(Duration(seconds: pumps));
}

Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('announced exactly once', () {
    test('beating a boss while the app runs: refresh grants it, one take announces it, then never again', () async {
      await boot({});
      expect(am.takeNewUnlocks(), isEmpty);
      StatsManager.instance.recordBossKill(2, flawless: false); // boss 3 -> Swarm Siege
      expect(am.refreshUnlocks(), [ArcadeGame.swarmSiege]);
      expect(am.refreshUnlocks(), isEmpty, reason: 'granting twice is not news twice');
      expect(am.takeNewUnlocks(), [ArcadeGame.swarmSiege]);
      expect(am.takeNewUnlocks(), isEmpty);
      await restart();
      expect(am.takeNewUnlocks(), isEmpty);
      expect(am.isUnlocked(ArcadeGame.swarmSiege), isTrue);
    });

    test('several restarts before the hub is opened keep the news; opening it clears it for good', () async {
      await boot({});
      StatsManager.instance.recordBossKill(1, flawless: false);
      StatsManager.instance.recordBossKill(3, flawless: false);
      am.refreshUnlocks();
      await restart();
      await restart();
      await restart();
      expect(am.takeNewUnlocks(), [ArcadeGame.groundAssault, ArcadeGame.cockpit], reason: 'table order, nothing lost');
      await restart();
      expect(am.takeNewUnlocks(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('arcade_unseen'), isEmpty);
      expect(prefs.getStringList('arcade_unlocked'), containsAll([ArcadeGame.groundAssault.id, ArcadeGame.cockpit.id]));
    });

    test('a later boss announces only itself', () async {
      await boot({});
      StatsManager.instance.recordBossKill(1, flawless: false);
      am.refreshUnlocks();
      expect(am.takeNewUnlocks(), [ArcadeGame.groundAssault]);
      StatsManager.instance.recordBossKill(2, flawless: false);
      am.refreshUnlocks();
      expect(am.takeNewUnlocks(), [ArcadeGame.swarmSiege]);
    });

    test('a game with a record is never news, whichever way it got unlocked', () async {
      // Played before unlocks existed, and the boss is beaten too.
      await boot({'arcade_best_invaders': 40, 'stats_bosses_defeated': ['2']});
      expect(am.isUnlocked(ArcadeGame.swarmSiege), isTrue);
      expect(am.takeNewUnlocks(), isEmpty);
      // Plays alone (no best) also counts as a record.
      await boot({'arcade_plays_shmup': 1});
      expect(am.isUnlocked(ArcadeGame.shmup), isTrue);
      expect(am.takeNewUnlocks(), isEmpty);
      // Played earlier, boss beaten later: still not news.
      await boot({'arcade_plays_cockpit': 2});
      StatsManager.instance.recordBossKill(3, flawless: false);
      am.refreshUnlocks();
      expect(am.takeNewUnlocks(), isEmpty);
    });

    test('a bought game is never announced, even if its boss is beaten afterwards', () async {
      await boot({'coins_total': 2000});
      expect(await am.buy(ArcadeGame.shmup), isTrue);
      expect(am.takeNewUnlocks(), isEmpty);
      StatsManager.instance.recordBossKill(4, flawless: false);
      expect(am.refreshUnlocks(), isEmpty);
      expect(am.takeNewUnlocks(), isEmpty);
      await restart();
      expect(am.takeNewUnlocks(), isEmpty);
      expect(am.isUnlocked(ArcadeGame.shmup), isTrue);
    });

    test('a player from before the unseen list existed (no key) loads fine', () async {
      await boot({'arcade_unlocked': ['assault']});
      expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
      expect(am.takeNewUnlocks(), isEmpty);
    });

    test('Thread the Needle is never news', () async {
      await boot({'stats_bosses_defeated': ['0', '1', '2', '3', '4', '5']});
      final news = am.takeNewUnlocks();
      expect(news, isNot(contains(ArcadeGame.threadTheNeedle)));
      expect(news.length, 5);
    });
  });

  group('hub', () {
    testWidgets('banner once: leaving and reopening the hub shows no banner and no New chip', (t) async {
      await boot({'stats_bosses_defeated': ['0', '1']});
      await mount(t);
      expect(find.text('Unlocked: Ground Assault'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
      await finish(t);
      await mount(t);
      expect(find.textContaining('Unlocked:'), findsNothing);
      expect(find.text('New'), findsNothing);
      await finish(t);
    });

    testWidgets('news earned before a restart is still on the banner after it', (t) async {
      await boot({});
      StatsManager.instance.recordBossKill(1, flawless: false);
      am.refreshUnlocks();
      await t.runAsync(restart);
      await mount(t);
      expect(find.text('Unlocked: Ground Assault'), findsOneWidget);
      await finish(t);
    });

    testWidgets('three games at once read as "A, B and C"', (t) async {
      await boot({'stats_bosses_defeated': ['1', '2', '3']});
      await mount(t);
      expect(find.text('Unlocked: Ground Assault, Swarm Siege and Mayday'), findsOneWidget);
      await finish(t);
    });

    testWidgets('a played game stays unlocked and shows no banner or New chip', (t) async {
      await boot({'arcade_best_invaders': 10});
      await mount(t);
      expect(find.textContaining('Unlocked:'), findsNothing);
      expect(find.text('New'), findsNothing);
      await finish(t);
    });

    Future<void> openSheet(WidgetTester t, String boss) async {
      final card = find.textContaining('Beat boss $boss in the main game');
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('shortfall is shown, to the NOVA, with no Unlock button; at the exact price it flips', (t) async {
      await boot({'coins_total': 499});
      await mount(t);
      await openSheet(t, '2');
      expect(find.text('You need 1 more NOVA.'), findsOneWidget);
      expect(find.text('Unlock'), findsNothing);
      await t.tap(find.text('OK'));
      await t.pump(const Duration(milliseconds: 600));
      await finish(t);

      await boot({'coins_total': 500});
      await mount(t);
      await openSheet(t, '2');
      expect(find.textContaining('You need'), findsNothing);
      expect(find.text('Unlock'), findsOneWidget);
      await t.tap(find.text('Not now'));
      await t.pump(const Duration(milliseconds: 600));
      await finish(t);
    });

    testWidgets('broke player: the sheet shows the full price as the shortfall', (t) async {
      await boot({'coins_total': 0});
      await mount(t);
      await openSheet(t, '2');
      expect(find.text('You need 500 more NOVA.'), findsOneWidget);
      await t.tap(find.text('OK'));
      await t.pump(const Duration(milliseconds: 600));
      expect(am.isUnlocked(ArcadeGame.groundAssault), isFalse);
      await finish(t);
    });

    testWidgets('the sheet reports boss progress and never opens the game; a bought game gets no banner next visit', (t) async {
      await boot({'coins_total': 800, 'stats_bosses_defeated': ['0']});
      await mount(t);
      await openSheet(t, '2');
      expect(find.text('Furthest so far: boss 1.'), findsOneWidget);
      await t.runAsync(() async {
        await t.tap(find.text('Unlock'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump(const Duration(seconds: 3));
      expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
      expect(CoinManager.instance.totalCoins, 300);
      await finish(t);
      await mount(t);
      expect(find.textContaining('Unlocked:'), findsNothing, reason: 'bought, not earned: no banner on the next visit');
      expect(find.text('New'), findsNothing);
      await finish(t);
    });
  });
}
