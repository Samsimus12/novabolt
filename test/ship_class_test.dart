import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/coins/hangar_manager.dart';
import 'package:novabolt/game/data/ship_class.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final hangar = HangarManager.instance;

  Future<void> boot(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await CoinManager.instance.init();
    await hangar.init();
  }

  test('Vanguard is free and selected by default', () async {
    await boot({});
    expect(hangar.selectedClass, ShipClass.vanguard);
    expect(hangar.ownsClass(ShipClass.vanguard), isTrue);
    expect(hangar.ownsClass(ShipClass.bulwark), isFalse);
  });

  test('buying needs coins, then selects and persists', () async {
    await boot({'coins_total': 2000});
    expect(await hangar.buyClass(ShipClass.bulwark), isFalse, reason: 'costs 2500');
    expect(CoinManager.instance.totalCoins, 2000);

    expect(await hangar.buyClass(ShipClass.interceptor), isTrue);
    expect(CoinManager.instance.totalCoins, 500);
    expect(hangar.selectedClass, ShipClass.interceptor);
    expect(await hangar.buyClass(ShipClass.interceptor), isFalse, reason: 'already owned');

    await hangar.selectClass(ShipClass.vanguard);
    await hangar.init(); // reload from prefs
    expect(hangar.ownsClass(ShipClass.interceptor), isTrue);
    expect(hangar.selectedClass, ShipClass.vanguard);
  });

  test('a saved selection of an unowned class falls back to Vanguard', () async {
    await boot({'ship_class': 'conduit'});
    expect(hangar.selectedClass, ShipClass.vanguard);
  });

  test('every class trades a strength for a weakness', () {
    for (final c in ShipClass.values.where((c) => c != ShipClass.vanguard)) {
      expect(c.perks, isNotEmpty, reason: c.title);
      expect(c.drawbacks, isNotEmpty, reason: c.title);
      expect(c.cost, greaterThan(0), reason: c.title);
    }
  });
}
