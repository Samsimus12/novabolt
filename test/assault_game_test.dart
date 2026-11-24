import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/assault/assault_controls.dart';
import 'package:novabolt/arcade/assault/assault_game.dart';
import 'package:novabolt/arcade/assault/assault_levels.dart';
import 'package:novabolt/arcade/assault/assault_overlays.dart';
import 'package:novabolt/arcade/assault/assault_progress.dart';
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

Future<AssaultGame> mountGame(WidgetTester t, {int stage = 0}) async {
  final game = AssaultGame(seed: 1, stage: stage);
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

  test('AssaultProgress: bests only rise, clearing unlocks the next stage', () async {
    expect(await AssaultProgress.unlocked(stageCount: 3), 0);
    var r = await AssaultProgress.record(stage: 0, stageCount: 3, percent: 40, score: 12, cleared: false);
    expect(r.newBestPercent, isTrue);
    expect(r.newBestScore, isTrue);
    expect(r.unlockedNext, isFalse);
    r = await AssaultProgress.record(stage: 0, stageCount: 3, percent: 25, score: 30, cleared: false);
    expect(r.newBestPercent, isFalse);
    expect(r.newBestScore, isTrue);
    expect(await AssaultProgress.bestPercent(0), 40);
    expect(await AssaultProgress.bestScore(0), 30);
    r = await AssaultProgress.record(stage: 0, stageCount: 3, percent: 100, score: 20, cleared: true);
    expect(r.percent, 100);
    expect(r.unlockedNext, isTrue);
    expect(await AssaultProgress.unlocked(stageCount: 3), 1);
    expect(await AssaultProgress.bestPercent(0), 100);
    // The last stage unlocks nothing; re-clearing doesn't re-announce.
    r = await AssaultProgress.record(stage: 0, stageCount: 3, percent: 100, score: 5, cleared: true);
    expect(r.unlockedNext, isFalse);
    r = await AssaultProgress.record(stage: 2, stageCount: 3, percent: 100, score: 5, cleared: true);
    expect(r.unlockedNext, isFalse);
    expect(await AssaultProgress.unlocked(stageCount: 3), 1);
  });

  testWidgets('a game over shows how far you got and saves it', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final game = await mountGame(t);
    await run(t, 2.0);
    game.sim.pilot.x = game.sim.startX + (game.sim.exitX - game.sim.startX) * 0.5;
    game.sim.pilot.lives = 1;
    await run(t, 0.2);
    game.sim.pilot.y = AssaultTuning.levelRows + 5.0;
    await run(t, 4.0);
    expect(game.phase.value, AssaultPhase.over);
    final pct = game.sim.progressPercent;
    expect(pct, inInclusiveRange(45, 99));
    expect(find.text('Reached $pct%'), findsOneWidget);
    expect(find.text('New best'), findsOneWidget);
    expect(find.text('Next stage'), findsNothing);
    expect(await AssaultProgress.bestPercent(0), pct);
    expect(await AssaultProgress.unlocked(stageCount: 3), 0);
  });

  testWidgets('clearing a stage shows 100% and Next stage; the screen moves on', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: AssaultScreen(seed: 1, stage: 1)));
    await run(t, 2.0);
    final game = t.widget<AssaultHud>(find.byType(AssaultHud)).game;
    expect(game.stage, 1);
    // Real stages have a boss guarding the exit: count it as beaten first.
    for (final e in game.sim.enemies) {
      if (e.kind == 'boss') e.dead = true;
    }
    game.sim.pilot.x = game.sim.exitX;
    game.sim.pilot.y = game.sim.exitY;
    await run(t, 3.0);
    expect(game.phase.value, AssaultPhase.cleared);
    expect(game.sim.progressPercent, 100);
    expect(find.text('Stage 2 complete'), findsOneWidget);
    expect(find.text('New best'), findsOneWidget);
    expect(await AssaultProgress.unlocked(stageCount: assaultLevels.length), 2);
    await t.tap(find.text('Next stage'));
    await run(t, 0.6);
    expect(find.text(assaultLevels[2].name), findsOneWidget);
    expect(find.text('Stage 3'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('with stage 2 unlocked the screen opens the stage select', (t) async {
    SharedPreferences.setMockInitialValues({'assault_unlocked': 1, 'assault_best_pct_0': 100, 'assault_best_score_0': 33});
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: AssaultScreen(seed: 1)));
    await run(t, 0.5);
    expect(find.text(assaultLevels[0].name), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Best 33'), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);
    await t.tap(find.text(assaultLevels[1].name));
    await run(t, 0.6);
    expect(find.text('Stage 2'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
