// Render smoke test for the Rift Runner art: every stage and every boss kind,
// through all three boss phases, with the real Flame game and HUD. Fails on
// any exception thrown while drawing.
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/arcade/arcade_manager.dart';
import 'package:novabolt/arcade/shmup/shmup_game.dart';
import 'package:novabolt/arcade/shmup/shmup_overlays.dart';
import 'package:novabolt/arcade/shmup/shmup_sim.dart';
import 'package:novabolt/coins/coin_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> frames(WidgetTester t, double s, [void Function()? each]) async {
  for (var i = 0; i < (s * 30).round(); i++) {
    each?.call();
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

  for (var stage = 1; stage <= 5; stage++) {
    testWidgets('stage $stage: level, mid-boss, boss phases 1-3, clear all render', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final game = ShmupGame(seed: stage);
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
      final s = game.sim;
      s.stage = stage;
      await frames(t, 0.5); // ready card
      await t.dragFrom(const Offset(300, 400), const Offset(-10, 10));
      void keep() => s.ship.invuln = 1e9;
      // Level: jump to the middle (terrain, enemies, pick-ups, the mid-boss).
      for (final at in [300.0, 1050.0, 1120.0]) {
        s.scrollX = at;
        await frames(t, 2.5, keep);
      }
      // Boss.
      s.scrollX = s.level.bossAt - 1;
      await frames(t, 5, keep);
      final b = s.boss;
      expect(b, isNotNull, reason: 'boss never appeared');
      expect(b!.kind, ShmupBossKind.values[s.level.bossStyle % 4]);
      await frames(t, 4, keep); // phase 1
      for (final g in b.guards) {
        g.hp = 0;
      }
      await frames(t, 7, keep); // phase 2 (Maw jaw cycles, Hauler pulls, Prism arms)
      expect(b.phase, 2);
      b.core.hp = b.core.maxHp * 0.3;
      await frames(t, 8, keep); // phase 3
      expect(b.phase, 3);
      // Kill it: dying + clear card.
      b.core.hp = 0.5;
      s.playerBullets.add(ShmupBullet(b.x + b.core.dx - 2, b.y + b.core.dy, 1, 0, dmg: 5, life: 1));
      for (var i = 0; i < 40 && s.phase == ShmupPhase.playing; i++) {
        keep();
        // keep the throat open for the Maw
        s.playerBullets.add(ShmupBullet(b.x + b.core.dx - 2, b.y + b.core.dy, 1, 0, dmg: 5, life: 1));
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(s.phase, ShmupPhase.stageClear);
      await frames(t, 2, keep);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('game over screen draws on a late stage', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final game = ShmupGame(seed: 9);
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
    game.sim.stage = 4;
    await t.dragFrom(const Offset(300, 400), const Offset(-10, 10));
    game.sim.retire();
    await frames(t, 2);
    expect(t.takeException(), isNull);
  });
}
