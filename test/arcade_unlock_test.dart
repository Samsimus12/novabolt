import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final am = ArcadeManager.instance;

  Future<void> boot([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    await StatsManager.instance.init();
    await CoinManager.instance.init();
    await am.init();
  }

  test('Thread the Needle is free, everything else starts locked', () async {
    await boot();
    expect(am.isUnlocked(ArcadeGame.threadTheNeedle), isTrue);
    for (final g in ArcadeManager.unlocks.keys) {
      expect(am.isUnlocked(g), isFalse, reason: g.id);
    }
    expect(am.unlockReason(ArcadeGame.groundAssault), 'Beat boss 2 in the main game');
    expect(am.unlockPrice(ArcadeGame.starport), 1500);
    expect(am.unlockReason(ArcadeGame.threadTheNeedle), '');
  });

  test('prices and bosses follow the hub order', () {
    final u = ArcadeManager.unlocks;
    expect([for (final g in ArcadeGame.values.skip(1)) u[g]!.bossNumber], [2, 3, 4, 5, 6]);
    expect([for (final g in ArcadeGame.values.skip(1)) u[g]!.price], [500, 750, 1000, 1250, 1500]);
  });

  test('beating a boss unlocks its game (and only that one), and it sticks', () async {
    await boot();
    StatsManager.instance.recordBossKill(1, flawless: false); // boss 2
    expect(am.refreshUnlocks(), [ArcadeGame.groundAssault]);
    expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
    expect(am.isUnlocked(ArcadeGame.swarmSiege), isFalse);
    // Saved: still unlocked after a restart even if boss stats were wiped.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final prefs = await SharedPreferences.getInstance();
    await boot({'arcade_unlocked': prefs.getStringList('arcade_unlocked') ?? []});
    expect(am.isUnlocked(ArcadeGame.groundAssault), isTrue);
  });

  test('buying: not enough NOVA fails, enough succeeds and is saved', () async {
    await boot({'coins_total': 400});
    const g = ArcadeGame.groundAssault;
    expect(await am.buy(g), isFalse);
    expect(am.isUnlocked(g), isFalse);
    expect(CoinManager.instance.totalCoins, 400);

    await CoinManager.instance.addCoins(300); // 700
    expect(await am.buy(g), isTrue);
    expect(am.isUnlocked(g), isTrue);
    expect(CoinManager.instance.totalCoins, 200);
    expect(await am.buy(g), isFalse, reason: 'no double charge');
    expect(CoinManager.instance.totalCoins, 200);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('arcade_unlocked'), contains(g.id));
    expect(prefs.getInt('coins_total'), 200);
    await boot({'arcade_unlocked': prefs.getStringList('arcade_unlocked')!});
    expect(am.isUnlocked(g), isTrue);
    expect(await am.buy(ArcadeGame.threadTheNeedle), isFalse);
  });

  test('players with arcade history keep those games', () async {
    await boot({
      'arcade_best_shmup': 12,
      'arcade_plays_invaders': 3,
    });
    expect(am.isUnlocked(ArcadeGame.shmup), isTrue);
    expect(am.isUnlocked(ArcadeGame.swarmSiege), isTrue);
    expect(am.isUnlocked(ArcadeGame.cockpit), isFalse);
    expect(am.isUnlocked(ArcadeGame.starport), isFalse);
  });
}
