// UI-level checks for the Nov 24 changes: Assault's move stick never jumps in
// the real widget (the Jump button does), and Rift Runner's stage/boss copy
// shows the new stage names and per-boss tips.
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/assault/assault_controls.dart';
import 'package:novabolt/arcade/assault/assault_game.dart';
import 'package:novabolt/arcade/assault/assault_overlays.dart';
import 'package:novabolt/arcade/assault/assault_screen.dart';
import 'package:novabolt/arcade/shmup/shmup_game.dart';
import 'package:novabolt/arcade/shmup/shmup_overlays.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> frames(WidgetTester t, double seconds) async {
  for (var i = 0; i < (seconds * 30).round(); i++) {
    await t.pump(const Duration(milliseconds: 33));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CoinManager.instance.init();
    await ArcadeManager.instance.init();
    ArcadeManager.instance.now = () => DateTime(2026, 11, 24, 12);
  });

  group('Assault: the move stick never jumps in the real widget', () {
    Future<AssaultGame> mount(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final game = AssaultGame(seed: 1, stage: 0);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameWidget<AssaultGame>(
            game: game,
            initialActiveOverlays: const [AssaultGame.controlsOverlay, AssaultGame.hudOverlay],
            overlayBuilderMap: {
              AssaultGame.controlsOverlay: (c, g) => AssaultControls(game: g),
              AssaultGame.hudOverlay: (c, g) => AssaultHud(game: g),
            },
          ),
        ),
      ));
      await frames(t, 3.5); // past the intro, standing on the ground
      return game;
    }

    testWidgets('dragging the stick up (straight, diagonal, flicked) leaves the pilot on the ground', (t) async {
      final game = await mount(t);
      final deck = game.deckRect;
      final y0 = game.sim.pilot.y;
      expect(game.sim.pilot.onGround, isTrue);
      final g = await t.startGesture(Offset(80, deck.center.dy));
      for (final d in const [Offset(0, -50), Offset(40, -40), Offset(0, 50), Offset(-30, -45), Offset(0, -60)]) {
        await g.moveBy(d);
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 33));
          expect(game.sim.pilot.y, greaterThanOrEqualTo(y0 - 0.001), reason: 'the pilot left the ground with the stick at ${game.sim.input.moveY}');
        }
        expect(game.sim.input.jumpHeld, isFalse);
      }
      await g.up();
      expect(game.sim.pilot.onGround, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Jump button jumps; the stick held up at the same time adds nothing', (t) async {
      final game = await mount(t);
      final y0 = game.sim.pilot.y;
      final stick = await t.startGesture(Offset(80, game.deckRect.center.dy));
      await stick.moveBy(const Offset(0, -50));
      final jump = await t.startGesture(t.getRect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Jump')).center);
      await frames(t, 0.25);
      expect(game.sim.pilot.y, lessThan(y0 - 0.5), reason: 'the Jump button did not jump');
      await jump.up();
      await stick.up();
    });
  });

  group('Assault: the intro card hints match the controls', () {
    // The pre-twin-stick hints must not come back.
    testWidgets('no stale hints on the intro card', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(const MaterialApp(home: AssaultScreen(seed: 1)));
      await frames(t, 0.5);
      expect(find.text('Crash Site'), findsOneWidget);
      for (final stale in ['Left: move, up to aim up', 'Right: jump, again in the air', 'Your gun fires straight ahead']) {
        expect(find.text(stale), findsNothing, reason: 'stale: "$stale"');
      }
      await frames(t, 3);
    });
  });

  group('Rift Runner: stage and boss copy', () {
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
      await frames(t, 0.3);
      return game;
    }

    for (final (stageNo, name, tagline) in [
      (3, 'Wreck Field', 'Dead fleets drift here, and something is stripping them.'),
      (4, 'Bone Reef', 'Inside the bones of something huge. It is not empty.'),
    ]) {
      testWidgets('stage $stageNo: ready card and stage banner show "$name"', (t) async {
        final game = await mount(t);
        game.sim.stage = stageNo;
        await frames(t, 0.3);
        expect(find.textContaining(name), findsWidgets, reason: 'ready card');
        // Start the round: the stage banner (with the tagline) shows during the intro.
        await t.dragFrom(const Offset(300, 400), const Offset(-10, 10));
        await frames(t, 0.5);
        expect(find.textContaining(name), findsWidgets, reason: 'stage banner');
        expect(find.text(tagline), findsOneWidget);
        game.sim.ship.invuln = 1e9;
        await frames(t, 4);
        expect(t.takeException(), isNull);
      });
    }

    for (final (stageNo, boss, tip) in [
      (1, 'The Breaker', 'Break both cannons to open the core'),
      (2, 'The Prism', 'Shatter the three crystals to reach the heart'),
      (3, 'The Hauler', 'Break both claws. A lit lane shows where one strikes'),
      (4, 'The Maw', 'Pop both eyes, then shoot its throat'),
    ]) {
      testWidgets('stage $stageNo boss: HUD names "$boss" and shows its tip', (t) async {
        final game = await mount(t);
        final s = game.sim;
        s.stage = stageNo;
        await t.dragFrom(const Offset(300, 400), const Offset(-10, 10));
        s.ship.invuln = 1e9;
        s.scrollX = s.level.bossAt - 1; // straight to the boss (earlier spawns fire at once; clear them)
        for (var i = 0; i < 4 && s.boss == null; i++) {
          await t.pump(const Duration(milliseconds: 33));
        }
        s.enemies.clear();
        s.enemyBullets.clear();
        for (var i = 0; i < 60 && !(s.boss?.entered ?? false); i++) {
          s.ship.invuln = 1e9;
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(s.boss?.entered, isTrue);
        await frames(t, 0.5);
        expect(find.text(boss), findsWidgets);
        expect(find.text(tip), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  });
}
