import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import 'components/background.dart';
import 'components/hud.dart';
import 'components/monster.dart';
import 'components/player.dart';
import 'components/projectile.dart';
import 'systems/wave_system.dart';
import 'systems/xp_system.dart';

class RuneboltGame extends FlameGame with HasCollisionDetection {
  late Player player;
  final XpSystem xpSystem = XpSystem();
  late WaveSystem _waveSystem;

  bool isGameOver = false;

  @override
  Color backgroundColor() => const Color(0xFF0D0D2B);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.topLeft;

    player = Player(position: size / 2);
    _waveSystem = WaveSystem();

    world.add(StarBackground());
    world.add(player);
    world.add(_waveSystem);
    camera.viewport.add(Hud());
  }

  void onMonsterKilled(int xpValue) {
    if (xpSystem.addXp(xpValue)) {
      overlays.add('LevelUp');
      pauseEngine();
    }
  }

  void onPlayerDeath() {
    if (isGameOver) return;
    isGameOver = true;
    overlays.add('GameOver');
    pauseEngine();
  }

  void resumeFromLevelUp() {
    overlays.remove('LevelUp');
    resumeEngine();
  }

  void restart() {
    isGameOver = false;
    overlays.remove('GameOver');
    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    world.children.whereType<Projectile>().toList().forEach((p) => p.removeFromParent());
    xpSystem.reset();
    player.reset();
    _waveSystem.reset();
    resumeEngine();
  }
}
