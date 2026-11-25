// B6 verification: abilities are no longer announced on use, and the
// reduced-motion ("calm") flag really calms the ability UI.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/data/ship_ability.dart';
import 'package:novabolt/screens/ability_button.dart';

import 'ability_game_test.dart' show boot, frame;

class _Status extends ChangeNotifier implements AbilityStatus {
  final List<ShipAbility> _o = [ShipAbility.dash, ShipAbility.cloak, ShipAbility.decoy];
  ShipAbility _a = ShipAbility.dash;
  @override
  List<ShipAbility> get owned => _o;
  @override
  ShipAbility? get armed => _a;
  @override
  int levelOf(ShipAbility a) => 1;
  @override
  double cooldownLeft(ShipAbility a) => 0;
  @override
  double cooldownFraction(ShipAbility a) => 0;
  @override
  double activeFraction(ShipAbility a) => 0;
  @override
  void arm(ShipAbility a) {
    _a = a;
    notifyListeners();
  }

  @override
  void cycle(int step) => arm(_o[(_o.indexOf(_a) + step) % _o.length]);
}

Widget host(AbilityStatus s, {required bool calm}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: calm),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 184),
              child: AbilityButton(status: s, onUse: () => true, onSelectorOpen: (_) {}, shipPosition: () => null),
            ),
          ),
        ),
      ),
    );

void main() {
  group('no announcement on use', () {
    testWidgets('using every ability in the real game never posts a banner', (t) async {
      final g = await boot(t);
      for (final a in ShipAbility.values) {
        g.abilities.take(a);
      }
      g.announcement = '';
      for (final a in ShipAbility.values) {
        expect(g.abilities.use(a), isTrue, reason: a.name);
        await frame(t, 3);
        expect(g.announcement, anyOf(isNull, isEmpty), reason: '${a.name} must not announce itself');
      }
      await frame(t, 10);
      expect(g.announcement, anyOf(isNull, isEmpty));
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('taking an ability card still tells the player (that is not "use")', (t) async {
      final g = await boot(t);
      g.announcement = '';
      g.abilities.take(ShipAbility.cloak);
      expect(g.announcement, anyOf(isNull, isEmpty), reason: 'the loadout itself is quiet; the card announces');
      await t.pumpWidget(const SizedBox());
    });
  });

  group('calm (reduced motion)', () {
    testWidgets('the card badge stops pulsing when animations are off, and pulses otherwise', (t) async {
      for (final calm in [true, false]) {
        await t.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: calm),
            child: Scaffold(body: Center(child: AbilityBadge(ability: ShipAbility.aegis, fromLevel: 0))),
          ),
        ));
        await t.pump(const Duration(milliseconds: 100));
        if (calm) {
          await t.pumpAndSettle(const Duration(milliseconds: 50), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
          expect(t.hasRunningAnimations, isFalse, reason: 'calm: nothing keeps animating');
        } else {
          await t.pump(const Duration(milliseconds: 500));
          expect(t.hasRunningAnimations, isTrue, reason: 'normal: the badge pulses');
        }
        await t.pumpWidget(const SizedBox());
      }
    });

    testWidgets('switching ability: the name flash does not slide in calm mode, and does in normal mode', (t) async {
      Future<double> travel(bool calm) async {
        final s = _Status();
        await t.pumpWidget(host(s, calm: calm));
        await t.pump(const Duration(seconds: 1));
        s.cycle(1); // arm Cloak: the name flashes above the button
        await t.pump();
        await t.pump(const Duration(milliseconds: 20));
        final y0 = t.getTopLeft(find.text('Cloak')).dy;
        await t.pump(const Duration(milliseconds: 60));
        final y1 = t.getTopLeft(find.text('Cloak')).dy;
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 3));
        return (y1 - y0).abs();
      }

      expect(await travel(true), 0, reason: 'calm: no slide');
      expect(await travel(false), greaterThan(0.5), reason: 'normal: it rises into place');
    });

    testWidgets('the button works in calm mode (tap uses, hold fan opens) without throwing', (t) async {
      final s = _Status();
      var uses = 0;
      var opened = false;
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 26, bottom: 184),
                child: AbilityButton(
                  status: s,
                  onUse: () {
                    uses++;
                    return true;
                  },
                  onSelectorOpen: (o) => opened = opened || o,
                  shipPosition: () => null,
                ),
              ),
            ),
          ),
        ),
      ));
      await t.pump(const Duration(seconds: 1));
      final c = t.getTopLeft(find.byType(AbilityButton)) + AbilityButton.discCenter;
      await t.tapAt(c);
      await t.pump(const Duration(milliseconds: 50));
      expect(uses, 1);
      final h = await t.startGesture(c);
      await t.pump(const Duration(milliseconds: 350));
      expect(opened, isTrue);
      await h.up();
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    });
  });
}
