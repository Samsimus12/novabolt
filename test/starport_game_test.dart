import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/starport/starport_game.dart';
import 'package:novabolt/arcade/starport/starport_generator.dart';
import 'package:novabolt/arcade/starport/starport_overlays.dart';
import 'package:novabolt/arcade/starport/starport_screen.dart';
import 'package:novabolt/arcade/starport/starport_sim.dart';
import 'package:novabolt/arcade/starport/starport_types.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3x3 hangar, two shuttles of colour 0:
///   A (id 0) at (0,0)-(1,0) facing right: clear.
///   B (id 1) at (1,2)-(1,1) facing up: its nose (1,1) looks at (1,0), so A
///   blocks it until A has gone.
/// Eight colour-0 passengers fill both ships.
StarportLevel handLevel(int number, int seed) => StarportLevel(
      number: number,
      cols: 3,
      rows: 3,
      ships: const [
        StarShip(id: 0, color: 0, kind: ShipKind.shuttle, facing: Facing.right, col: 0, row: 0),
        StarShip(id: 1, color: 0, kind: ShipKind.shuttle, facing: Facing.up, col: 1, row: 2),
      ],
      queue: List.filled(8, 0),
      bays: 4,
      colorCount: 1,
    );

/// Pumps real frames (looping animations make pumpAndSettle hang).
Future<void> run(WidgetTester t, double seconds) async {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

Future<StarportGame> mount(WidgetTester t, {bool begin = true}) async {
  await t.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final game = StarportGame(seed: 1, levelSource: handLevel);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameWidget<StarportGame>(
        game: game,
        initialActiveOverlays: const [StarportGame.hudOverlay, StarportGame.readyOverlay],
        overlayBuilderMap: {
          StarportGame.hudOverlay: (c, g) => StarportHud(game: g),
          StarportGame.readyOverlay: (c, g) => StarportReady(game: g),
          StarportGame.clearOverlay: (c, g) => StarportClear(game: g),
          StarportGame.pauseOverlay: (c, g) => StarportPause(game: g, onExit: () {}),
          StarportGame.overOverlay: (c, g) => StarportResults(game: g, onExit: () {}),
        },
      ),
    ),
  ));
  await run(t, 0.3);
  if (begin) {
    game.begin();
    await run(t, 0.1);
  }
  return game;
}

Future<void> tapCell(WidgetTester t, StarportGame g, int c, int r) async {
  await t.tapAt(g.cellCenter(c, r));
  await run(t, 0.05);
}

Finder iconButton(String label) =>
    find.byWidgetPredicate((w) => w is NbIconButton && w.semanticLabel == label);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CoinManager.instance.init();
    await ArcadeManager.instance.init();
    ArcadeManager.instance.now = () => DateTime(2026, 11, 22, 12);
  });

  testWidgets('the screen pumps and shows the ready card and the HUD', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: StarportScreen(seed: 1, levelSource: handLevel)));
    await run(t, 0.5);
    expect(t.takeException(), isNull);
    expect(find.text('Launch'), findsOneWidget);
    expect(iconButton('Pause'), findsOneWidget);
    expect(iconButton('Undo'), findsOneWidget);
    await t.tap(find.text('Launch'));
    await run(t, 0.3);
    expect(find.text('Launch'), findsNothing);
    expect(find.text('Level 1'), findsOneWidget);
  });

  testWidgets('the layout fits the screen with square cells', (t) async {
    final g = await mount(t);
    final screen = Rect.fromLTWH(0, 0, 390, 844);
    expect(screen.contains(g.hangarRect.topLeft), isTrue);
    expect(screen.contains(g.hangarRect.bottomRight), isTrue);
    expect(g.cellSize * 3, closeTo(g.hangarRect.width, 0.01));
    expect(g.cellSize * 3, closeTo(g.hangarRect.height, 0.01));
    expect(g.bayRects.length, 4);
    expect(g.stationRect.bottom, lessThan(g.gateRect.top));
    expect(g.gateRect.bottom, lessThan(g.hangarRect.top));
    for (final b in g.bayRects) {
      expect(g.stationRect.contains(b.center), isTrue);
    }
  });

  testWidgets('tapping a clear ship launches it, boards and departs', (t) async {
    final g = await mount(t);
    await tapCell(t, g, 1, 0);
    expect(g.sim.parked.map((s) => s.id), [1]);
    expect(g.flights, isNotEmpty, reason: 'the ship flies out');
    // Sim is already final; the picture catches up.
    expect(g.sim.score, 1);
    expect(g.sim.queue.length, 4);
    await run(t, 1.5);
    expect(g.busy, isFalse);
    expect(g.visParked.map((s) => s.id), [1]);
    expect(g.visQueue.length, 4);
    expect(g.visBays.every((b) => b == null), isTrue, reason: 'it filled and left');
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a blocked ship bumps and highlights the blocker', (t) async {
    final g = await mount(t);
    final before = g.sim.power;
    await tapCell(t, g, 1, 1); // B, blocked by A
    expect(g.sim.parked.length, 2);
    expect(g.sim.levelClean, isFalse);
    expect(g.sim.power, lessThan(before));
    expect(g.blockerGlow(0), greaterThan(0));
    expect(g.bumpOffset(g.sim.parked.firstWhere((s) => s.id == 1)), isNot(Offset.zero));
    await run(t, 0.7);
    expect(g.blockerGlow(0), 0);
    expect(g.bumpOffset(g.sim.parked.firstWhere((s) => s.id == 1)), Offset.zero);
    expect(g.sim.parked.length, 2);
  });

  testWidgets('tapping empty floor does nothing', (t) async {
    final g = await mount(t);
    await tapCell(t, g, 2, 1); // empty cell
    expect(g.sim.parked.length, 2);
    expect(g.sim.levelClean, isTrue);
    expect(g.flights, isEmpty);
  });

  testWidgets('undo puts the ship back and the button then disables', (t) async {
    final g = await mount(t);
    await tapCell(t, g, 1, 0);
    expect(g.sim.parked.length, 1);
    await t.tap(iconButton('Undo'));
    await run(t, 0.1);
    expect(g.sim.parked.length, 2);
    expect(g.sim.queue.length, 8);
    expect(g.sim.undosLeft, 0);
    expect(g.visParked.length, 2);
    expect(g.visQueue.length, 8);
    expect(g.flights, isEmpty);
    expect(g.undosLeft.value, 0);
    final undo = t.widget<NbIconButton>(iconButton('Undo'));
    expect(undo.onPressed, isNull);
  });

  testWidgets('rapid taps are never blocked by animations', (t) async {
    final g = await mount(t);
    // A and (once A is gone) B in consecutive frames.
    await t.tapAt(g.cellCenter(1, 0));
    await t.pump(const Duration(milliseconds: 16));
    await t.tapAt(g.cellCenter(1, 1));
    await t.pump(const Duration(milliseconds: 16));
    expect(g.sim.parked, isEmpty, reason: 'both launched while the first was still flying');
    expect(g.sim.phase, StarportPhase.levelClear);
    await run(t, 0.7);
    expect(g.sim.score, 2 + 5);
    expect(t.takeException(), isNull);
  });

  testWidgets('a cleared level shows the card and then starts the next', (t) async {
    final g = await mount(t);
    await tapCell(t, g, 1, 0);
    await tapCell(t, g, 1, 1);
    expect(g.sim.phase, StarportPhase.levelClear);
    expect(g.sim.levelClean, isTrue);
    await run(t, 1.6);
    expect(find.text('Level 1 cleared'), findsOneWidget);
    expect(find.text('Clean level'), findsOneWidget);
    await run(t, StarportGame.clearHold + 0.4);
    expect(find.text('Level 1 cleared'), findsNothing);
    expect(g.sim.levelNumber, 2);
    expect(g.sim.phase, StarportPhase.playing);
    expect(g.visParked.length, 2);
    expect(g.levelNumber.value, 2);
    expect(g.sim.levelsCleared, 1);
  });

  testWidgets('tapping the clear card skips the wait', (t) async {
    final g = await mount(t);
    await tapCell(t, g, 1, 0);
    await tapCell(t, g, 1, 1);
    await run(t, 1.6);
    expect(find.text('Level 1 cleared'), findsOneWidget);
    await t.tap(find.text('Level 1 cleared'));
    await run(t, 0.1);
    expect(g.sim.levelNumber, 2);
  });

  testWidgets('the power meter drains and a flat meter ends the run with a result', (t) async {
    final g = await mount(t);
    final am = ArcadeManager.instance;
    final p0 = g.power.value;
    await run(t, 1.0);
    expect(g.power.value, lessThan(p0));

    g.sim.score = 12;
    g.sim.bonus = 1;
    g.sim.levelsCleared = 3;
    g.sim.power = 0.0005;
    await run(t, 0.3);
    expect(g.sim.phase, StarportPhase.over);
    expect(g.sim.overReason, StarportOver.power);
    expect(g.result, isNull, reason: 'results wait a moment');
    await run(t, StarportGame.overDelay + 0.5);
    final r = g.result!;
    expect(r.score, 12);
    expect(r.bonus, 1);
    expect(r.coins, 12 * ArcadeManager.coinsPerPoint + ArcadeManager.coinsPerBonus);
    expect(am.best(g.arcadeGame), 12);
    expect(am.plays(g.arcadeGame), 1);
    expect(CoinManager.instance.totalCoins, r.coins);
    expect(find.text('Power out'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
    expect(g.isOver, isTrue);

    // Taps are dead on the results screen; Play again starts level 1.
    await t.tap(find.text('Play again'));
    await run(t, 0.3);
    expect(g.isOver, isFalse);
    expect(g.sim.phase, StarportPhase.playing);
    expect(g.sim.score, 0);
    expect(g.sim.levelNumber, 1);
    expect(find.text('Play again'), findsNothing);
  });

  testWidgets('gridlock ends the run after the animations', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    // One bay, A is colour 0 but the queue starts with colour 1: docking
    // A fills the only bay and nobody can board.
    StarportLevel tight(int n, int s) => StarportLevel(
          number: n,
          cols: 3,
          rows: 2,
          ships: const [
            StarShip(id: 0, color: 0, kind: ShipKind.shuttle, facing: Facing.right, col: 0, row: 0),
            StarShip(id: 1, color: 1, kind: ShipKind.shuttle, facing: Facing.right, col: 0, row: 1),
          ],
          queue: [1, 1, 1, 1, 0, 0, 0, 0],
          bays: 1,
          colorCount: 2,
        );
    final g = StarportGame(seed: 1, levelSource: tight);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GameWidget<StarportGame>(
          game: g,
          overlayBuilderMap: {
            StarportGame.overOverlay: (c, g) => StarportResults(game: g, onExit: () {}),
          },
        ),
      ),
    ));
    await run(t, 0.3);
    g.begin();
    await t.tapAt(g.cellCenter(1, 0));
    await run(t, 0.2);
    expect(g.sim.overReason, StarportOver.gridlock);
    expect(g.result, isNull);
    await run(t, 1.8);
    expect(g.result, isNotNull);
    expect(find.text('Gridlock'), findsOneWidget);
  });

  testWidgets('pause stops the sim and resume continues it', (t) async {
    final g = await mount(t);
    await run(t, 0.5);
    final time = g.sim.time;
    expect(time, greaterThan(0));
    await t.tap(iconButton('Pause'));
    await run(t, 0.3);
    expect(g.paused, isTrue);
    expect(find.text('Paused'), findsOneWidget);
    final frozen = g.sim.time;
    await run(t, 0.5);
    expect(g.sim.time, frozen);
    await t.tap(find.text('Resume'));
    await run(t, 0.5);
    expect(g.paused, isFalse);
    expect(g.sim.time, greaterThan(frozen));
  });

  testWidgets('the ready card starts the run and the clock does not run before', (t) async {
    final g = await mount(t, begin: false);
    await run(t, 0.5);
    expect(g.sim.phase, StarportPhase.ready);
    expect(g.sim.power, 1);
    await tapCell(t, g, 1, 0);
    expect(g.sim.parked.length, 2, reason: 'taps before the start do nothing');
    await t.tap(find.text('Launch'));
    await run(t, 0.2);
    expect(g.sim.phase, StarportPhase.playing);
    expect(find.text('Launch'), findsNothing);
  });

  testWidgets("the real generator's levels fit the screen", (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    for (final n in [1, 4, 8, 12, 20, 30]) {
      final g = StarportGame(seed: 7, levelSource: (_, s) => generateStarportLevel(n, seed: s));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: GameWidget<StarportGame>(game: g))));
      await run(t, 0.1);
      expect(g.cellSize, greaterThanOrEqualTo(24), reason: 'level $n');
      expect(Rect.fromLTWH(0, 0, 390, 844).contains(g.hangarRect.bottomRight), isTrue, reason: 'level $n');
      expect(g.hangarRect.top, greaterThan(g.gateRect.bottom), reason: 'level $n');
      expect(g.bayRects.length, g.sim.level.bays);
    }
  });
}
