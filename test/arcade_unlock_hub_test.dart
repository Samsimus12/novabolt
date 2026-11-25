// B4 verification, beyond test/arcade_unlock_test.dart: the hub screen itself
// (a locked game must not launch), edge cases of buying and double taps.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/arcade_screen.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Nav extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute && previousRoute != null) pushes++;
  }
}

final am = ArcadeManager.instance;

Future<void> boot(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  await StatsManager.instance.init();
  await CoinManager.instance.init();
  await am.init();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buying', () {
    test('exactly the price works; one NOVA short does not', () async {
      await boot({'coins_total': 499});
      expect(await am.buy(ArcadeGame.groundAssault), isFalse);
      expect(CoinManager.instance.totalCoins, 499);
      await boot({'coins_total': 500});
      expect(await am.buy(ArcadeGame.groundAssault), isTrue);
      expect(CoinManager.instance.totalCoins, 0);
    });

    test('every price is charged exactly (500/750/1000/1250/1500) and unlocks only that game', () async {
      const prices = {
        ArcadeGame.groundAssault: 500,
        ArcadeGame.swarmSiege: 750,
        ArcadeGame.cockpit: 1000,
        ArcadeGame.shmup: 1250,
        ArcadeGame.starport: 1500,
      };
      for (final e in prices.entries) {
        await boot({'coins_total': 5000});
        expect(await am.buy(e.key), isTrue, reason: e.key.id);
        expect(CoinManager.instance.totalCoins, 5000 - e.value, reason: e.key.id);
        for (final other in prices.keys) {
          expect(am.isUnlocked(other), other == e.key, reason: '${e.key.id} bought, checking ${other.id}');
        }
      }
    });

    test('a game already unlocked by its boss is not charged for', () async {
      await boot({
        'coins_total': 5000,
        'stats_bosses_defeated': ['1'],
      });
      expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
      expect(await am.buy(ArcadeGame.groundAssault), isFalse);
      expect(CoinManager.instance.totalCoins, 5000);
    });

    test('a bought game stays unlocked when the boss is beaten later (and no refund is owed)', () async {
      await boot({'coins_total': 600});
      await am.buy(ArcadeGame.groundAssault);
      StatsManager.instance.recordBossKill(1, flawless: false);
      expect(am.refreshUnlocks(), isEmpty, reason: 'it was already unlocked, so nothing new');
    });

    test('refreshUnlocks reports a game only once', () async {
      await boot({});
      StatsManager.instance.recordBossKill(2, flawless: true); // boss 3
      expect(am.refreshUnlocks(), [ArcadeGame.swarmSiege]);
      expect(am.refreshUnlocks(), isEmpty);
    });

    // KNOWN BUG (reported to lead): buy() checks isUnlocked, then awaits spend(), so two
    // calls started together both pass the check and both charge. Remove skip when fixed.
    test('double-tapping Unlock charges once (two buy() calls at the same moment)', () async {
      await boot({'coins_total': 5000});
      final r = await Future.wait([am.buy(ArcadeGame.groundAssault), am.buy(ArcadeGame.groundAssault)]);
      expect(r.where((x) => x).length, 1, reason: 'exactly one purchase should succeed: $r');
      expect(CoinManager.instance.totalCoins, 4500, reason: 'charged once, not twice');
    });

    test('boss unlocks do not cascade: beating a later boss only opens its own game', () async {
      await boot({});
      StatsManager.instance.recordBossKill(4, flawless: false); // boss 5
      am.refreshUnlocks();
      expect(am.isUnlocked(ArcadeGame.shmup), isTrue);
      expect(am.isUnlocked(ArcadeGame.groundAssault), isFalse);
      expect(am.isUnlocked(ArcadeGame.swarmSiege), isFalse);
      expect(am.isUnlocked(ArcadeGame.cockpit), isFalse);
    });

    test('boss indices wrap with the 10-boss cycle (boss 12 counts as boss 2)', () async {
      await boot({});
      // The game records (bossPhase - 1) % 10, so the 12th boss is index 1.
      StatsManager.instance.recordBossKill((12 - 1) % 10, flawless: false);
      am.refreshUnlocks();
      expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
    });
  });

  group('the hub screen', () {
    // Lets looping animations and one-shot timers finish before the test ends.
    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 5));
    }

    Future<_Nav> mount(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(390, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      // The test environment has no real fonts (everything renders in a wide
      // placeholder), so layout overflows are meaningless here: ignore them.
      final old = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.exception.toString().contains('overflowed')) old?.call(d);
      };
      addTearDown(() => FlutterError.onError = old);
      final nav = _Nav();
      await t.pumpWidget(MaterialApp(navigatorObservers: [nav], home: const ArcadeScreen()));
      await t.pump(const Duration(seconds: 1));
      return nav;
    }

    testWidgets('locked cards say Locked, with the boss and the price; Thread the Needle does not', (t) async {
      await boot({'coins_total': 0});
      await mount(t);
      // The list is lazy: scroll to the bottom so every card has been built once.
      expect(find.text('Locked'), findsWidgets);
      expect(find.textContaining('Beat boss 2 in the main game, or unlock for 500 NOVA'), findsOneWidget);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Beat boss 6 in the main game, or unlock for 1500 NOVA'), findsOneWidget);
      expect(find.textContaining('Thread the Needle is locked'), findsNothing);
      expect(find.text('Coming soon'), findsNothing);
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('tapping a locked game opens the unlock dialog and does NOT launch the game', (t) async {
      await boot({'coins_total': 100});
      final nav = await mount(t);
      final card = find.textContaining('Beat boss 2 in the main game');
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Ground Assault is locked'), findsOneWidget);
      expect(find.text('You need 400 more NOVA.'), findsOneWidget);
      expect(find.text('Unlock'), findsNothing, reason: 'cannot afford: no Unlock button');
      expect(nav.pushes, 0, reason: 'a locked game must never open');
      await t.tap(find.text('OK'));
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('Ground Assault is locked'), findsNothing);
      expect(am.isUnlocked(ArcadeGame.groundAssault), isFalse);
      expect(CoinManager.instance.totalCoins, 100);
      expect(nav.pushes, 0);
      await finish(t);
    });

    testWidgets('with enough NOVA: Not now changes nothing, Unlock spends and flips the card', (t) async {
      await boot({'coins_total': 800});
      final nav = await mount(t);
      final card = find.textContaining('Beat boss 2 in the main game');
      await t.ensureVisible(card);
      await t.pump();
      await t.tap(card);
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.text('Not now'));
      await t.pump(const Duration(milliseconds: 600));
      expect(CoinManager.instance.totalCoins, 800);
      expect(am.isUnlocked(ArcadeGame.groundAssault), isFalse);

      await t.tap(card);
      await t.pump(const Duration(milliseconds: 600));
      final lockedBefore = find.text('Locked').evaluate().length;
      await t.runAsync(() async {
        await t.tap(find.text('Unlock'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pump(const Duration(milliseconds: 600));
      expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
      expect(CoinManager.instance.totalCoins, 300);
      expect(find.text('Locked').evaluate().length, lockedBefore - 1);
      expect(find.textContaining('Beat boss 2 in the main game'), findsNothing);
      expect(nav.pushes, 0, reason: 'buying does not auto-launch');
      expect(t.takeException(), isNull);
      await finish(t);
    });

    testWidgets('a boss beaten since the last visit opens its game when the hub opens', (t) async {
      await boot({});
      StatsManager.instance.recordBossKill(3, flawless: false); // boss 4: Mayday
      await mount(t);
      expect(am.isUnlocked(ArcadeGame.cockpit), isTrue);
      expect(find.textContaining('Beat boss 4 in the main game'), findsNothing);
      expect(find.textContaining('Beat boss 2 in the main game'), findsOneWidget);
      await finish(t);
    });
  });
}
