import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/data/daily_challenge.dart';
import 'package:novabolt/screens/daily_briefing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('briefing lists today\'s rules and rewards, Start returns true', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DailyManager.instance.init();
    final today = DailyManager.instance.today;
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDailyBriefing(context),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final m in today.modifiers) {
      expect(find.text(m.title), findsOneWidget);
      expect(find.text(m.description), findsOneWidget);
    }
    expect(find.text('Double NOVA coins on every daily run'), findsOneWidget);
    expect(find.textContaining('Streak bonus +50'), findsOneWidget, reason: 'first day of a streak pays 50');

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('Not now returns false', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await DailyManager.instance.init();
    bool? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDailyBriefing(context),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
