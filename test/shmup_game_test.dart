import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/shmup/shmup_art.dart';
import 'package:novabolt/arcade/shmup/shmup_game.dart';
import 'package:novabolt/arcade/shmup/shmup_overlays.dart';
import 'package:novabolt/arcade/shmup/shmup_screen.dart';
import 'package:novabolt/arcade/shmup/shmup_sim.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:novabolt/ui/ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps real frames (looping animations make pumpAndSettle hang).
Future<void> run(WidgetTester t, double seconds) async {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

Future<ShmupGame> mount(WidgetTester t) async {
  await t.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final game = ShmupGame(seed: 1);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: GameWidget<ShmupGame>(
        game: game,
        initialActiveOverlays: const [ShmupGame.hudOverlay],
        overlayBuilderMap: {
          ShmupGame.hudOverlay: (c, g) => ShmupHud(game: g),
          ShmupGame.pauseOverlay: (c, g) => ShmupPause(game: g, onExit: () {}),
          ShmupGame.overOverlay: (c, g) => ShmupOver(game: g, onExit: () {}),
        },
      ),
    ),
  ));
  await run(t, 0.3);
  return game;
}

Finder pauseButton() => find.byWidgetPredicate((w) => w is NbIconButton && w.semanticLabel == 'Pause');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CoinManager.instance.init();
    await ArcadeManager.instance.init();
    ArcadeManager.instance.now = () => DateTime(2026, 11, 23, 12);
  });

  testWidgets('the screen pumps and shows the ready hint and the pause button', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: ShmupScreen(seed: 1)));
    await run(t, 0.5);
    expect(t.takeException(), isNull);
    expect(find.text('Drag to fly'), findsOneWidget);
    expect(pauseButton(), findsOneWidget);
  });

  testWidgets('the field matches the screen shape and the ship starts on the left', (t) async {
    final game = await mount(t);
    expect(game.sim.width, 100);
    expect(game.sim.height, closeTo(100 * 844 / 390, 0.01));
    expect(game.sim.ship.x, lessThan(30));
    expect(game.sim.phase, ShmupPhase.ready);
  });

  testWidgets('dragging starts the round and moves the ship 1:1, anywhere on screen', (t) async {
    final game = await mount(t);
    final x0 = game.sim.ship.x, y0 = game.sim.ship.y;
    final unit = 390 / 100;
    // Start the drag top-right: nowhere near the ship, which must not jump.
    await t.dragFrom(const Offset(300, 150), const Offset(-60, 80));
    await run(t, 0.1);
    expect(game.sim.phase, ShmupPhase.playing);
    final dx = game.sim.ship.x - x0, dy = game.sim.ship.y - y0;
    expect(dx, lessThan(0)); // finger went left
    expect(dx, greaterThan(-60 / unit - 0.01));
    expect(dy, greaterThan(8)); // and down (minus drag slop)
    expect(dy, lessThanOrEqualTo(80 / unit + 0.01));
    // Far drag clamps to the field.
    for (var i = 0; i < 3; i++) {
      await t.dragFrom(const Offset(380, 800), const Offset(-370, -700));
      await run(t, 0.05);
    }
    expect(game.sim.ship.x, ShmupTuning.shipR);
    // Up is stopped by the ceiling (and it hurts), not by the screen edge.
    expect(game.sim.ship.y, closeTo(game.sim.ceilingAt(game.sim.ship.x) + ShmupTuning.shipHitR, 0.01));
    expect(game.sim.ship.hull, lessThan(3));
    expect(t.takeException(), isNull);
  });

  testWidgets('the world scrolls and the ship shoots while playing', (t) async {
    final game = await mount(t);
    game.sim.start();
    await run(t, 1.0);
    expect(game.sim.scrollX, greaterThan(15));
    expect(game.sim.playerBullets, isNotEmpty);
    expect(game.sim.progress, greaterThan(0));
  });

  testWidgets('pause stops the sim and resume continues it', (t) async {
    final game = await mount(t);
    game.sim.start();
    await run(t, 0.5);
    final time = game.sim.time;
    expect(time, greaterThan(0));
    await t.tap(pauseButton());
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

  testWidgets('the last ship going down records the round and shows the results', (t) async {
    final game = await mount(t);
    final am = ArcadeManager.instance;
    final g = game.arcadeGame;
    game.sim.start();
    await run(t, 0.2);
    game.sim.score = 12;
    game.sim.shards = 1;
    game.sim.ship.lives = 1;
    game.sim.ship.hull = 1;
    game.sim.ship.invuln = 0;
    game.sim.enemyBullets.add(ShmupBullet(game.sim.ship.x, game.sim.ship.y, 0, 0, r: 1.5));
    await run(t, 0.3);
    expect(game.sim.phase, ShmupPhase.over);
    expect(game.isOver, isFalse, reason: 'the wreck gets a moment before the results');
    await run(t, 2.0);
    expect(game.isOver, isTrue);
    expect(game.result, isNotNull);
    expect(game.result!.score, 12);
    expect(game.result!.bonus, 1);
    expect(game.result!.coins, 12 * ArcadeManager.coinsPerPoint + ArcadeManager.coinsPerBonus);
    expect(am.plays(g), 1);
    expect(am.best(g), 12);
    expect(find.text('Play again'), findsOneWidget);

    await t.tap(find.text('Play again'));
    await run(t, 0.3);
    expect(game.isOver, isFalse);
    expect(game.sim.phase, ShmupPhase.ready);
    expect(game.sim.score, 0);
    expect(game.sim.ship.lives, ShmupTuning.startLives);
    expect(find.text('Drag to fly'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('Finish run in the pause menu banks the round immediately', (t) async {
    final game = await mount(t);
    game.sim.start();
    game.sim.score = 5;
    await run(t, 0.3);
    await t.tap(pauseButton());
    await run(t, 0.3);
    await t.tap(find.text('Finish run'));
    await run(t, 0.5);
    expect(game.paused, isFalse);
    expect(game.isOver, isTrue);
    expect(game.result!.score, 5);
    expect(ArcadeManager.instance.plays(game.arcadeGame), 1);
  });

  testWidgets('a boss kill raises the stage banner and the next stage starts', (t) async {
    final game = await mount(t);
    game.sim.start();
    game.sim.scrollX = game.sim.level.bossAt;
    await run(t, 4);
    expect(game.sim.boss, isNotNull);
    game.sim.boss!.parts.last.hp = 0;
    game.sim.boss!.upper.hp = 0;
    game.sim.boss!.lower.hp = 0;
    final b = game.sim.boss!;
    game.sim.playerBullets.add(ShmupBullet(b.x + b.core.dx, b.y + b.core.dy, 0, 0, dmg: 5));
    // (core hp is 0 already: kill via a fresh bullet on a live core)
    b.core.hp = 1;
    game.sim.playerBullets.add(ShmupBullet(b.x + b.core.dx, b.y + b.core.dy, 0, 0, dmg: 5));
    await run(t, 0.3);
    expect(game.sim.phase, ShmupPhase.stageClear);
    expect(find.text('STAGE CLEAR'), findsOneWidget);
    await run(t, 4);
    expect(game.sim.stage, 2);
    expect(game.sim.phase, ShmupPhase.playing);
    expect(t.takeException(), isNull);
  });

  testWidgets('the hub preview painter draws without errors', (t) async {
    await t.pumpWidget(MaterialApp(
      home: CustomPaint(painter: _PreviewPainter(), size: const Size(300, 150)),
    ));
    expect(t.takeException(), isNull);
  });
}

class _PreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (final t in [0.0, 1.3, 7.7]) {
      ShmupArt.paintPreview(canvas, size, t);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
