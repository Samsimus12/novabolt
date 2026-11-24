import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/ui/ui.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/invaders/invaders_game.dart';
import 'package:novabolt/arcade/invaders/invaders_overlays.dart';
import 'package:novabolt/arcade/invaders/invaders_screen.dart';
import 'package:novabolt/arcade/invaders/invaders_sim.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps real frames (looping animations make pumpAndSettle hang).
Future<void> run(WidgetTester t, double seconds) async {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

Future<InvadersGame> mount(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final game = InvadersGame(seed: 1);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameWidget<InvadersGame>(
        game: game,
        initialActiveOverlays: const [InvadersGame.hudOverlay],
        overlayBuilderMap: {
          InvadersGame.hudOverlay: (c, g) => InvadersHud(game: g),
          InvadersGame.pauseOverlay: (c, g) => InvadersPause(game: g, onExit: () {}),
          InvadersGame.overOverlay: (c, g) => InvadersOver(game: g, onExit: () {}),
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

  testWidgets('the screen pumps and shows the ready hint', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: InvadersScreen(seed: 1)));
    await run(t, 0.5);
    expect(t.takeException(), isNull);
    expect(find.text('Drag to move'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is NbIconButton && w.semanticLabel == 'Pause'), findsOneWidget);
  });

  testWidgets('the field matches the screen shape', (t) async {
    final game = await mount(t);
    expect(game.sim.width, 100);
    expect(game.sim.height, closeTo(100 * 844 / 390, 0.01));
  });

  testWidgets('dragging in the lower area starts the round and slides the ship 1:1', (t) async {
    final game = await mount(t);
    expect(game.sim.phase, InvadersPhase.ready);
    final x0 = game.sim.shipX;
    final unit = 390 / 100;
    await t.dragFrom(const Offset(200, 700), const Offset(60, 0));
    await run(t, 0.1);
    expect(game.sim.phase, InvadersPhase.playing);
    // 60 px of finger = 60/3.9 units (minus the drag slop Flutter eats).
    expect(game.sim.shipX - x0, greaterThan(8));
    expect(game.sim.shipX - x0, lessThanOrEqualTo(60 / unit + 0.01));
    await t.dragFrom(const Offset(300, 700), const Offset(-500, 0));
    await run(t, 0.1);
    expect(game.sim.shipX, InvadersSim.shipHw, reason: 'clamped to the screen edge');
    expect(t.takeException(), isNull);
  });

  testWidgets('a touch in the top part of the screen does not steer or start', (t) async {
    final game = await mount(t);
    await t.dragFrom(const Offset(200, 120), const Offset(60, 0));
    await run(t, 0.1);
    expect(game.sim.phase, InvadersPhase.ready);
  });

  testWidgets('pause stops the sim and resume continues it', (t) async {
    final game = await mount(t);
    game.sim.start();
    await run(t, 0.5);
    final time = game.sim.time;
    expect(time, greaterThan(0));
    await t.tap(find.byWidgetPredicate((w) => w is NbIconButton && w.semanticLabel == 'Pause'));
    await run(t, 0.3);
    expect(game.paused, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    final frozen = game.sim.time;
    await run(t, 0.5);
    expect(game.sim.time, frozen);
    await t.tap(find.text('Resume'));
    await run(t, 0.5);
    expect(game.paused, isFalse);
    expect(game.sim.time, greaterThan(frozen));
  });

  testWidgets('a finished round records via ArcadeManager and shows results', (t) async {
    final game = await mount(t);
    final am = ArcadeManager.instance;
    final g = game.arcadeGame;
    game.sim.start();
    await run(t, 0.2);
    game.sim.score = 12;
    game.sim.bonus = 1;
    game.sim.lives = 1;
    game.sim.invulnerable = 0;
    game.sim.alienShots.add(Shot(game.sim.shipX, game.sim.shipY - 3, fromShip: false));
    await run(t, 0.3);
    expect(game.sim.phase, InvadersPhase.over);
    await run(t, 2.0);
    expect(game.isOver, isTrue);
    expect(game.result, isNotNull);
    expect(game.result!.score, 12);
    expect(game.result!.coins, 12 * ArcadeManager.coinsPerPoint + ArcadeManager.coinsPerBonus);
    expect(am.plays(g), 1);
    expect(am.best(g), 12);
    expect(find.text('Play again'), findsOneWidget);

    await t.tap(find.text('Play again'));
    await run(t, 0.3);
    expect(game.isOver, isFalse);
    expect(game.sim.phase, InvadersPhase.ready);
    expect(game.sim.score, 0);
    expect(game.sim.lives, 3);
    expect(t.takeException(), isNull);
  });
}
