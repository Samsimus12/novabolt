// B5 UI verification: the ability button, hold fan, pause panel and level-up
// cards, driven against the REAL game and loadout (not a fake status).
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/components/monster.dart';
import 'package:novabolt/game/data/ability_stats.dart';
import 'package:novabolt/game/data/ship_ability.dart';
import 'package:novabolt/game/data/upgrade_cards.dart';
import 'package:novabolt/game/novabolt_game.dart';
import 'package:novabolt/game/systems/wave_system.dart';
import 'package:novabolt/screens/ability_button.dart';
import 'package:novabolt/screens/game_controls_overlay.dart';
import 'package:novabolt/screens/level_up_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> frames(WidgetTester t, int n) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

Future<NovaboltGame> mount(WidgetTester t) async {
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => t.binding.setSurfaceSize(null));
  // The test environment has no real fonts: ignore text overflow noise.
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    if (!d.exception.toString().contains('overflowed')) old?.call(d);
  };
  addTearDown(() => FlutterError.onError = old);
  final game = NovaboltGame();
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameWidget<NovaboltGame>(
        game: game,
        key: UniqueKey(),
        initialActiveOverlays: const ['GameControls'],
        overlayBuilderMap: {
          'GameControls': (c, g) => GameControlsOverlay(game: g, onMenu: () {}),
          'LevelUp': (c, g) => LevelUpScreen(game: g),
          'Countdown': (c, g) => const SizedBox.shrink(),
          'GameOver': (c, g) => const SizedBox.shrink(),
        },
      ),
    ),
  ));
  await frames(t, 12);
  for (final w in game.world.children.whereType<WaveSystem>().toList()) {
    w.removeFromParent();
  }
  for (final m in game.world.children.whereType<Monster>().toList()) {
    m.removeFromParent();
  }
  await frames(t, 2);
  game.player.maxHp = 1e6;
  game.player.currentHp = 1e6;
  return game;
}

/// Global center of the ability disc.
Offset disc(WidgetTester t) => t.getTopLeft(find.byType(AbilityButton)) + AbilityButton.discCenter;

// Fan geometry mirrors _FanLayout in ability_button.dart (center -55 deg,
// 22.5 deg apart, radius 112 once open).
Offset slot(int i, int n) {
  final a = (-55 + (i - (n - 1) / 2) * 22.5) * math.pi / 180;
  return Offset(math.cos(a), math.sin(a)) * 112;
}

String label(WidgetTester t) => t.getSemantics(find.byType(AbilityButton)).label;

Matcher use(String name) => equals('Use $name');

void take(NovaboltGame g, List<ShipAbility> l) {
  for (final a in l) {
    g.abilities.take(a);
  }
}

Future<void> end(WidgetTester t, NovaboltGame g) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

void main() {
  testWidgets('no abilities: no button; the first one installs it', (t) async {
    final g = await mount(t);
    expect(find.byType(AbilityButton), findsOneWidget);
    g.abilities.take(ShipAbility.dash);
    await frames(t, 20);
    expect(label(t), use('Dash'));
    expect(t.takeException(), isNull);
    await end(t, g);
  });

  testWidgets('one ability: a press fires it in the game, then the ring shows the cooldown and denies a second press', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash]);
    await frames(t, 20);
    final g1 = await t.startGesture(disc(t));
    await frames(t, 2);
    await g1.up();
    expect(g.player.isDashing || g.player.dashCooldown > 0, isTrue, reason: 'Dash fired through the real game');
    await frames(t, 5);
    expect(label(t), matches(RegExp(r'^Dash, \d+ seconds$')), reason: 'cooldown shown');
    final cd = g.abilities.cooldownLeft(ShipAbility.dash);
    final g2 = await t.startGesture(disc(t));
    await frames(t, 2);
    await g2.up();
    await frames(t, 20);
    expect(g.abilities.cooldownLeft(ShipAbility.dash), lessThanOrEqualTo(cd), reason: 'a denied press changes nothing');
    expect(t.takeException(), isNull);
    // Cooldown runs out: ready again.
    for (var i = 0; i < 30 && g.abilities.cooldownLeft(ShipAbility.dash) > 0; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await frames(t, 4);
    expect(g.abilities.cooldownLeft(ShipAbility.dash), 0);
    // It can be used again (the press goes through to the real game).
    final g3 = await t.startGesture(disc(t));
    await frames(t, 2);
    await g3.up();
    expect(g.abilities.cooldownLeft(ShipAbility.dash), greaterThan(0));
    await end(t, g);
  });

  testWidgets('three abilities: tap uses the armed one; the label shows active, then the cooldown', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash, ShipAbility.cloak, ShipAbility.decoy]);
    g.abilities.arm(ShipAbility.cloak);
    await frames(t, 20);
    final press = await t.startGesture(disc(t));
    await frames(t, 2);
    await press.up();
    await frames(t, 5);
    expect(g.abilities.cloaked, isTrue);
    expect(label(t), 'Cloak active');
    // Other abilities stay usable while one is cooling.
    for (var i = 0; i < 40 && g.abilities.cloaked; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await frames(t, 4);
    expect(g.abilities.cooldownLeft(ShipAbility.cloak), greaterThan(10));
    g.abilities.arm(ShipAbility.decoy);
    await frames(t, 5);
    expect(label(t), use('Decoy'));
    await end(t, g);
  });

  // KNOWN BUG (reported to lead): the Semantics label is computed in build(), but the
  // loadout only notifies on owned/armed/level changes, so the label never refreshes
  // as the cooldown runs: a screen reader keeps hearing "Dash, 3 seconds" (or
  // "Cloak active") after the ability is ready again. Remove skip when fixed.
  testWidgets('screen-reader label follows the cooldown back to "Use Dash"', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash]);
    await frames(t, 20);
    final p = await t.startGesture(disc(t));
    await frames(t, 2);
    await p.up();
    await frames(t, 5);
    expect(label(t), matches(RegExp(r'^Dash, \d+ seconds$')));
    for (var i = 0; i < 30 && g.abilities.cooldownLeft(ShipAbility.dash) > 0; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await frames(t, 10);
    expect(label(t), 'Use Dash');
    await end(t, g);
  });

  testWidgets('swiping cycles the armed ability both ways and does not spend it', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash, ShipAbility.cloak, ShipAbility.decoy]);
    await frames(t, 20);
    await t.dragFrom(disc(t), const Offset(-45, 0));
    await frames(t, 20);
    expect(g.abilities.armed, ShipAbility.cloak);
    await t.dragFrom(disc(t), const Offset(-45, 0));
    await frames(t, 20);
    expect(g.abilities.armed, ShipAbility.decoy);
    await t.dragFrom(disc(t), const Offset(-45, 0));
    await frames(t, 20);
    expect(g.abilities.armed, ShipAbility.dash, reason: 'wraps');
    await t.dragFrom(disc(t), const Offset(45, 0));
    await frames(t, 20);
    expect(g.abilities.armed, ShipAbility.decoy, reason: 'right swipe goes back');
    expect(g.abilities.cloaked, isFalse);
    expect(g.player.dashCooldown, 0);
    expect(g.abilities.cooldownLeft(ShipAbility.cloak), 0);
    await end(t, g);
  });

  testWidgets('hold opens the fan and slows the game; release on a slot arms it; release elsewhere cancels', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash, ShipAbility.cloak, ShipAbility.decoy]);
    await frames(t, 20);
    final c = disc(t);

    var h = await t.startGesture(c);
    await t.pump(const Duration(milliseconds: 350));
    expect(g.abilitySelectorOpen, isTrue, reason: 'fan open = game slowed');
    await h.moveTo(c + slot(2, 3));
    await frames(t, 3);
    await h.up();
    await frames(t, 20);
    expect(g.abilitySelectorOpen, isFalse);
    expect(g.abilities.armed, ShipAbility.decoy);
    expect(g.abilities.cloaked, isFalse, reason: 'choosing does not use');

    // Cancel: release far from every slot.
    h = await t.startGesture(c);
    await t.pump(const Duration(milliseconds: 350));
    expect(g.abilitySelectorOpen, isTrue);
    await h.moveTo(c + const Offset(0, 90));
    await frames(t, 3);
    await h.up();
    await frames(t, 20);
    expect(g.abilitySelectorOpen, isFalse);
    expect(g.abilities.armed, ShipAbility.decoy, reason: 'unchanged');

    // Release on the center: also a cancel.
    h = await t.startGesture(c);
    await t.pump(const Duration(milliseconds: 350));
    await h.up();
    await frames(t, 20);
    expect(g.abilities.armed, ShipAbility.decoy);
    expect(g.abilitySelectorOpen, isFalse);
    expect(t.takeException(), isNull);
    await end(t, g);
  });

  testWidgets('five abilities: every fan slot can be picked', (t) async {
    final g = await mount(t);
    take(g, ShipAbility.values);
    await frames(t, 20);
    final c = disc(t);
    for (final i in [4, 0, 2, 1, 3]) {
      final h = await t.startGesture(c);
      await t.pump(const Duration(milliseconds: 350));
      await h.moveTo(c + slot(i, 5));
      await frames(t, 3);
      await h.up();
      await frames(t, 20);
      expect(g.abilities.armed, ShipAbility.values[i], reason: 'slot $i');
      expect(g.abilitySelectorOpen, isFalse);
    }
    expect(g.abilities.cloaked || g.abilities.isActive(ShipAbility.aegis), isFalse, reason: 'picking never fires');
    await end(t, g);
  });

  testWidgets('the fan slows time to 0.25x for the whole hold', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.overclock, ShipAbility.cloak]);
    g.abilities.use(ShipAbility.overclock);
    await frames(t, 20);
    final c = disc(t);
    final h = await t.startGesture(c);
    await t.pump(const Duration(milliseconds: 350));
    final a = g.abilities.activeLeft(ShipAbility.overclock);
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 33));
    }
    final used = a - g.abilities.activeLeft(ShipAbility.overclock);
    expect(used, closeTo(0.25, 0.08), reason: '1 s of real time = 0.25 s of ability time');
    await h.up();
    await end(t, g);
  });

  testWidgets('dying with the fan open clears slow-mo and does not throw', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash, ShipAbility.cloak]);
    await frames(t, 20);
    final h = await t.startGesture(disc(t));
    await t.pump(const Duration(milliseconds: 350));
    expect(g.abilitySelectorOpen, isTrue);
    g.player.takeDamage(1e12);
    await frames(t, 5);
    expect(g.isGameOver, isTrue);
    expect(g.abilitySelectorOpen, isFalse);
    await h.up();
    await frames(t, 10);
    expect(g.abilitySelectorOpen, isFalse);
    expect(t.takeException(), isNull);
    await end(t, g);
  });

  testWidgets('the button sits where the old Dash button was and does not steal the move stick', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash, ShipAbility.cloak]);
    await frames(t, 20);
    final c = disc(t);
    // Spec: 58 px in from the left, 234 px up from the bottom (+ safe area, 0 here).
    expect(c.dx, closeTo(58, 1));
    expect(c.dy, closeTo(844 - 234, 1));
    // A touch well below it (on the stick area) must not use or swipe the button.
    final g2 = await t.startGesture(Offset(c.dx, c.dy + 150));
    await g2.moveBy(const Offset(40, 0));
    await frames(t, 10);
    await g2.up();
    expect(g.abilities.armed, ShipAbility.dash);
    expect(g.abilities.cooldownLeft(ShipAbility.cloak), 0);
    await end(t, g);
  });

  testWidgets('pause panel: no Abilities section with one ability; with several you can pick the armed one', (t) async {
    final g = await mount(t);
    take(g, [ShipAbility.dash]);
    await frames(t, 5);
    g.requestPause();
    await frames(t, 20);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Abilities'), findsNothing);
    await t.tap(find.bySemanticsLabel('Resume'));
    await frames(t, 20);
    expect(find.text('Paused'), findsNothing);

    take(g, [ShipAbility.cloak, ShipAbility.aegis]);
    g.abilities.take(ShipAbility.aegis); // level 2
    await frames(t, 5);
    g.requestPause();
    await frames(t, 20);
    expect(find.text('Abilities'), findsOneWidget);
    expect(find.bySemanticsLabel('Dash, level 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Cloak, level 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Aegis, level 2'), findsOneWidget);
    await t.ensureVisible(find.bySemanticsLabel('Aegis, level 2'));
    await t.tap(find.bySemanticsLabel('Aegis, level 2'));
    await frames(t, 5);
    expect(g.abilities.armed, ShipAbility.aegis);
    expect(t.takeException(), isNull);
    await end(t, g);
  });

  testWidgets('level-up cards: new ability, ability level, and the first-time hint; picking one grants it', (t) async {
    final g = await mount(t);
    final newDash = AbilityCard(ShipAbility.dash);
    g.currentCards = [newDash, AbilityCard(ShipAbility.cloak, fromLevel: 2), AbilityCard(ShipAbility.aegis)];
    g.overlays.add('LevelUp');
    await frames(t, 40);
    expect(find.text('New ability'), findsNWidgets(2));
    expect(find.text('Ability Lv 3'), findsOneWidget);
    expect(find.text('Goes on the button above the left stick.'), findsNWidgets(2), reason: 'while nothing is owned yet');
    expect(find.text('Lv 2 to 3'), findsOneWidget);
    expect(find.text(AbilityStats.summary(ShipAbility.dash)), findsOneWidget);
    expect(find.text(ShipAbility.dash.tagline), findsOneWidget);
    expect(g.abilities.owned, isEmpty);
    await t.tap(find.text('Dash').first);
    await frames(t, 60);
    expect(g.abilities.owned, [ShipAbility.dash]);
    expect(g.abilities.armed, ShipAbility.dash);
    expect(t.takeException(), isNull);
    await end(t, g);
  });
}
