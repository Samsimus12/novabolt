import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import 'components/background.dart';
import 'components/hud.dart';
import 'components/monster.dart';
import 'components/player.dart';
import 'components/projectile.dart';
import 'components/shield_pickup.dart';
import 'components/supercharge_laser.dart';
import 'data/upgrade_cards.dart';
import 'systems/supercharge_system.dart';
import 'systems/wave_system.dart';
import 'systems/xp_system.dart';

class RuneboltGame extends FlameGame with HasCollisionDetection {
  late Player player;
  late JoystickComponent joystick;
  late JoystickComponent aimJoystick;
  final XpSystem xpSystem = XpSystem();
  final SuperchargeSystem superchargeSystem = SuperchargeSystem();
  late WaveSystem _waveSystem;

  List<UpgradeCard> currentCards = [];
  bool isGameOver = false;

  @override
  Color backgroundColor() => const Color(0xFF0D0D2B);

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.topLeft;

    joystick = JoystickComponent(
      knob: CircleComponent(
        radius: 24,
        paint: Paint()..color = const Color(0x99FFD700),
      ),
      background: CircleComponent(
        radius: 56,
        paint: Paint()..color = const Color(0x33FFD700),
      ),
      margin: const EdgeInsets.only(left: 56, bottom: 80),
    );

    aimJoystick = JoystickComponent(
      knob: CircleComponent(
        radius: 24,
        paint: Paint()..color = const Color(0x9900E5FF),
      ),
      background: CircleComponent(
        radius: 56,
        paint: Paint()..color = const Color(0x3300E5FF),
      ),
      margin: const EdgeInsets.only(right: 56, bottom: 80),
    );

    player = Player(position: size / 2);
    _waveSystem = WaveSystem();

    world.add(StarBackground());
    world.add(player);
    world.add(_waveSystem);
    camera.viewport.add(joystick);
    camera.viewport.add(aimJoystick);
    camera.viewport.add(Hud());
  }

  void onMonsterKilled(int xpValue, int chargeValue) {
    superchargeSystem.addCharge(chargeValue.toDouble());
    if (xpSystem.addXp(xpValue)) {
      currentCards = generateUpgradeCards(this);
      overlays.add('LevelUp');
      pauseEngine();
    }
  }

  void activateSupercharge() {
    if (superchargeSystem.activate()) {
      world.add(SuperchargeLaser());
    }
  }

  void onPlayerDeath() {
    if (isGameOver) return;
    isGameOver = true;
    overlays.add('GameOver');
    pauseEngine();
  }

  void resumeFromLevelUp() {
    currentCards = [];
    overlays.remove('LevelUp');
    resumeEngine();
  }

  void restart() {
    isGameOver = false;
    currentCards = [];
    overlays.remove('GameOver');
    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    world.children.whereType<Projectile>().toList().forEach((p) => p.removeFromParent());
    world.children.whereType<SuperchargeLaser>().toList().forEach((l) => l.removeFromParent());
    world.children.whereType<ShieldPickup>().toList().forEach((s) => s.removeFromParent());
    xpSystem.reset();
    superchargeSystem.reset();
    player.position = size / 2;
    player.reset();
    _waveSystem.reset();
    resumeEngine();
  }
}
