import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/assault/assault_controls.dart';
import 'package:novabolt/arcade/assault/assault_game.dart';
import 'package:novabolt/arcade/assault/assault_overlays.dart';
import 'package:novabolt/arcade/assault/assault_screen.dart';
import 'package:novabolt/arcade/assault/assault_types.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps real frames (looping animations make pumpAndSettle hang).
Future<void> run(WidgetTester t, double seconds) async {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

Future<AssaultGame> mountGame(WidgetTester t) async {
  final game = AssaultGame(seed: 1);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameWidget<AssaultGame>(
        game: game,
        initialActiveOverlays: const [AssaultGame.controlsOverlay, AssaultGame.hudOverlay],
        overlayBuilderMap: {
          AssaultGame.controlsOverlay: (c, g) => AssaultControls(game: g),
          AssaultGame.hudOverlay: (c, g) => AssaultHud(game: g),
          AssaultGame.pauseOverlay: (c, g) => AssaultPause(game: g, onExit: () {}),
          AssaultGame.resultsOverlay: (c, g) => AssaultResults(game: g, onExit: () {}),
        },
      ),
    ),
  ));
  await run(t, 0.3);
  return game;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CoinManager.instance.init();
    await ArcadeManager.instance.init();
    ArcadeManager.instance.now = () => DateTime(2026, 11, 22, 12);
  });

  testWidgets('the screen pumps and the stage starts after the intro', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: AssaultScreen(seed: 1)));
    await run(t, 0.5);
    expect(t.takeException(), isNull);
    expect(find.text('Crash Site'), findsOneWidget);
    await run(t, 1.5);
    expect(find.text('Crash Site'), findsNothing);
    expect(find.text('Jump'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('layout: ten tiles across, 13 tall, deck below', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final game = await mountGame(t);
    expect(game.tilePx, closeTo(39, 0.01));
    expect(game.viewRect.height, closeTo(13 * 39, 0.01));
    expect(game.deckRect.top, game.viewRect.bottom);
    expect(game.deckRect.bottom, closeTo(844, 0.01));
  });

  testWidgets('pausing freezes the sim, resuming continues it', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final game = await mountGame(t);
    await run(t, 2.0); // past the intro
    expect(game.phase.value, AssaultPhase.playing);

    game.pauseRound();
    await run(t, 0.1);
    expect(game.paused, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    final frozen = game.sim.time;
    await run(t, 0.5);
    expect(game.sim.time, frozen);

    game.resumeRound();
    await run(t, 0.5);
    expect(game.paused, isFalse);
    expect(find.text('Paused'), findsNothing);
    expect(game.sim.time, greaterThan(frozen));
    expect(t.takeException(), isNull);
  });

  testWidgets('the stick and Jump work at the same time', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final game = await mountGame(t);
    final deck = game.deckRect;
    final stick = await t.startGesture(Offset(80, deck.center.dy));
    await stick.moveBy(const Offset(60, 0));
    final jump = await t.startGesture(Offset(deck.width * 0.75, deck.center.dy));
    final i = game.sim.input;
    expect(i.moveX, closeTo(1, 0.01));
    expect(i.jumpHeld, isTrue);
    await jump.up();
    expect(i.jumpHeld, isFalse);
    expect(i.moveX, closeTo(1, 0.01), reason: 'releasing Jump must not drop the stick');
    await stick.up();
    expect(i.moveX, 0);
  });

  testWidgets('a finished round is recorded by the arcade manager', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final game = await mountGame(t);
    await run(t, 2.0);
    final am = ArcadeManager.instance;
    expect(am.plays(ArcadeGame.groundAssault), 0);

    // Fall out of the level on the last life.
    game.sim.pilot.lives = 1;
    game.sim.pilot.y = AssaultTuning.levelRows + 5.0;
    await run(t, 4.0);
    expect(game.phase.value, AssaultPhase.over);
    expect(game.isOver, isTrue);
    expect(am.plays(ArcadeGame.groundAssault), 1);
    expect(game.result, isNotNull);
    expect(find.text('Play again'), findsOneWidget);

    await t.tap(find.text('Play again'));
    await run(t, 0.3);
    expect(game.isOver, isFalse);
    expect(game.phase.value, AssaultPhase.intro);
    expect(find.text('Play again'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
