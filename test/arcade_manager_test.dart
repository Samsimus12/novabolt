import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final am = ArcadeManager.instance;
  const g = ArcadeGame.threadTheNeedle;

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({});
    await CoinManager.instance.init();
    await am.init();
    am.now = () => DateTime(2026, 11, 22, 12);
  }

  test('a round pays NOVA and records the best score', () async {
    await boot();
    final r = await am.finishRound(g, score: 12, bonus: 2);
    expect(r.coins, 12 * ArcadeManager.coinsPerPoint + 2 * ArcadeManager.coinsPerBonus);
    expect(CoinManager.instance.totalCoins, r.coins);
    expect(am.best(g), 12);
    expect(r.newBest, isFalse, reason: 'the first round sets a best but is not "new best"');

    final r2 = await am.finishRound(g, score: 20);
    expect(r2.newBest, isTrue);
    final r3 = await am.finishRound(g, score: 5);
    expect(r3.newBest, isFalse);
    expect(am.best(g), 20);
    expect(am.plays(g), 3);
  });

  test('the daily cap limits NOVA, and resets the next day', () async {
    await boot();
    final big = await am.finishRound(g, score: 1000);
    expect(big.coins, ArcadeManager.dailyCap);
    expect(big.capped, isTrue);
    final more = await am.finishRound(g, score: 50);
    expect(more.coins, 0);
    expect(am.leftToday, 0);

    am.now = () => DateTime(2026, 11, 23, 9);
    expect(am.earnedToday, 0);
    final next = await am.finishRound(g, score: 10);
    expect(next.coins, 10 * ArcadeManager.coinsPerPoint);
  });
}
