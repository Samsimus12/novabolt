import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/coins/hangar_manager.dart';
import 'package:novabolt/game/data/ship_class.dart';
import 'package:novabolt/screens/hangar_screen.dart';
import 'package:novabolt/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final hangar = HangarManager.instance;

  // The hangar has looping animations, so pumpAndSettle never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pump(WidgetTester tester, int coins) async {
    // The test font is wider/taller than the real one; card text overflow
    // here isn't what this test is about.
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    SharedPreferences.setMockInitialValues({'coins_total': coins});
    await CoinManager.instance.init();
    await hangar.init();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(builder: materialRoot, home: HangarScreen()));
    await settle(tester);
  }

  testWidgets('tapping a locked class asks first; Not now spends nothing', (tester) async {
    await pump(tester, 2000);
    await tester.tap(find.text('Interceptor'));
    await settle(tester);
    expect(find.text('Buy Interceptor?'), findsOneWidget);
    expect(hangar.ownsClass(ShipClass.interceptor), isFalse);

    await tester.tap(find.text('Not now'));
    await settle(tester);
    expect(find.text('Buy Interceptor?'), findsNothing);
    expect(hangar.ownsClass(ShipClass.interceptor), isFalse);
    expect(CoinManager.instance.totalCoins, 2000);
  });

  testWidgets('Buy in the dialog buys and selects the class', (tester) async {
    await pump(tester, 2000);
    await tester.tap(find.text('Interceptor'));
    await settle(tester);
    await tester.tap(find.text('Buy'));
    await settle(tester);
    expect(hangar.ownsClass(ShipClass.interceptor), isTrue);
    expect(hangar.selectedClass, ShipClass.interceptor);
    expect(CoinManager.instance.totalCoins, 500);
  });

  testWidgets('a class you cannot afford shows the shortfall and no Buy button', (tester) async {
    await pump(tester, 1000);
    await tester.tap(find.text('Interceptor'));
    await settle(tester);
    expect(find.text('You need 500 more NOVA.'), findsOneWidget);
    expect(find.text('Buy'), findsNothing);
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(hangar.ownsClass(ShipClass.interceptor), isFalse);
  });
}
