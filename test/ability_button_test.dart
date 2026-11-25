import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/data/ship_ability.dart';
import 'package:novabolt/screens/ability_button.dart';

/// A plain loadout for driving the button without a game.
class _FakeStatus extends ChangeNotifier implements AbilityStatus {
  _FakeStatus(List<ShipAbility> owned) : _owned = [...owned], _armed = owned.isEmpty ? null : owned.first;

  final List<ShipAbility> _owned;
  ShipAbility? _armed;
  final cooling = <ShipAbility, double>{};

  void add(ShipAbility a) {
    _owned.add(a);
    _armed ??= a;
    notifyListeners();
  }

  @override
  List<ShipAbility> get owned => List.unmodifiable(_owned);
  @override
  ShipAbility? get armed => _armed;
  @override
  int levelOf(ShipAbility a) => _owned.contains(a) ? 1 : 0;
  @override
  double cooldownLeft(ShipAbility a) => cooling[a] ?? 0;
  @override
  double cooldownFraction(ShipAbility a) => (cooling[a] ?? 0) / 10;
  @override
  double activeFraction(ShipAbility a) => 0;
  @override
  void arm(ShipAbility a) {
    if (_armed == a) return;
    _armed = a;
    notifyListeners();
  }

  @override
  void cycle(int step) {
    final i = _owned.indexOf(_armed!);
    arm(_owned[(i + step) % _owned.length]);
  }
}

Widget _host(AbilityStatus status, {required bool Function() onUse, ValueChanged<bool>? onSelector}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 26, bottom: 184),
          child: AbilityButton(
            status: status,
            onUse: onUse,
            onSelectorOpen: onSelector ?? (_) {},
            shipPosition: () => null,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('builds nothing until an ability is owned, then installs', (tester) async {
    final status = _FakeStatus([]);
    await tester.pumpWidget(_host(status, onUse: () => true));
    expect(find.bySemanticsLabel('Use Dash'), findsNothing);

    status.add(ShipAbility.dash);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.bySemanticsLabel('Use Dash'), findsOneWidget);
    expect(find.text('Tap to use'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Tap to use'), findsNothing);
  });

  testWidgets('one ability fires on press', (tester) async {
    var uses = 0;
    final status = _FakeStatus([ShipAbility.dash]);
    await tester.pumpWidget(_host(status, onUse: () {
      uses++;
      return true;
    }));
    final g = await tester.startGesture(tester.getCenter(find.byType(AbilityButton)) - const Offset(0, 9));
    await tester.pump();
    expect(uses, 1, reason: 'single ability uses on pointer down');
    await g.up();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('several abilities: tap uses, swipe cycles, hold opens the fan', (tester) async {
    var uses = 0;
    final selector = <bool>[];
    final status = _FakeStatus([ShipAbility.dash, ShipAbility.cloak, ShipAbility.decoy]);
    await tester.pumpWidget(_host(status, onUse: () {
      uses++;
      return true;
    }, onSelector: selector.add));
    final disc = tester.getTopLeft(find.byType(AbilityButton)) + AbilityButton.discCenter;

    // Tap: fires on release.
    final g = await tester.startGesture(disc);
    await tester.pump();
    expect(uses, 0);
    await g.up();
    await tester.pump();
    expect(uses, 1);

    // Swipe left: next ability.
    await tester.dragFrom(disc, const Offset(-40, 0));
    await tester.pump();
    expect(status.armed, ShipAbility.cloak);
    expect(uses, 1, reason: 'a swipe must not spend the ability');
    await tester.pump(const Duration(seconds: 2));

    // Hold: fan opens; slide to the third slot and release to arm it.
    final h = await tester.startGesture(disc);
    await tester.pump(const Duration(milliseconds: 300));
    expect(selector, [true]);
    // Slot 2 of 3 sits at -55 + 22.5 deg, radius 112, from the disc center.
    const a = (-55 + 22.5) * math.pi / 180;
    await h.moveTo(disc + Offset(math.cos(a), math.sin(a)) * 112);
    await tester.pump();
    await h.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(selector, [true, false]);
    expect(status.armed, ShipAbility.decoy);
    expect(uses, 1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('denied tap shows the cooldown and does not throw', (tester) async {
    final status = _FakeStatus([ShipAbility.cloak])..cooling[ShipAbility.cloak] = 9.2;
    await tester.pumpWidget(_host(status, onUse: () => false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.bySemanticsLabel('Cloak, 10 seconds'), findsOneWidget);
    await tester.tap(find.byType(AbilityButton));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('badge and pause option render for every ability', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          for (final a in ShipAbility.values) ...[
            AbilityBadge(ability: a, fromLevel: a.index % 5),
            AbilityOption(ability: a, level: 2, selected: a == ShipAbility.aegis, onTap: () {}),
          ],
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Aegis'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
