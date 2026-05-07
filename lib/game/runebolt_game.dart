import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../coins/coin_manager.dart';
import 'components/background.dart';
import 'components/hud.dart';
import 'components/monster.dart';
import 'components/monster_boss.dart';
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
  bool _hasUsedContinue = false;
  bool get hasUsedContinue => _hasUsedContinue;
  BossMonster? activeBoss;
  int picksTotal = 0;
  int _picksRemaining = 0;

  @override
  Color backgroundColor() => switch (CoinManager.instance.selectedBackground) {
        'dark_void' => const Color(0xFF020208),
        'nebula' => const Color(0xFF0A0018),
        _ => const Color(0xFF0D0D2B),
      };

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
    if (xpValue > 0 && xpSystem.addXp(xpValue)) {
      final level = xpSystem.currentLevel;
      if (level % 10 == 0) {
        _waveSystem.startBossFight(level);
        return;
      }
      _showLevelUp(level);
    }
  }

  void onBossKilled() {
    activeBoss = null;
    _waveSystem.onBossKilled();
    _showLevelUp(xpSystem.currentLevel);
  }

  void _showLevelUp(int level) {
    picksTotal = (1 + level ~/ 5).clamp(1, 5);
    _picksRemaining = picksTotal;
    currentCards = generateUpgradeCards(this);
    overlays.add('LevelUp');
    pauseEngine();
  }

  int get currentPickIndex => picksTotal - _picksRemaining + 1;

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

  void continueWithHalfHp() {
    if (!isGameOver || _hasUsedContinue) return;
    isGameOver = false;
    _hasUsedContinue = true;
    overlays.remove('GameOver');
    player.currentHp = player.maxHp * 0.5;
    resumeEngine();
  }

  void resumeFromLevelUp() {
    _picksRemaining--;
    overlays.remove('LevelUp');
    if (_picksRemaining > 0) {
      currentCards = generateUpgradeCards(this);
      overlays.add('LevelUp');
    } else {
      currentCards = [];
      picksTotal = 0;
      resumeEngine();
    }
  }

  void restart() {
    isGameOver = false;
    _hasUsedContinue = false;
    currentCards = [];
    overlays.remove('GameOver');
    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    world.children.whereType<Projectile>().toList().forEach((p) => p.removeFromParent());
    world.children.whereType<SuperchargeLaser>().toList().forEach((l) => l.removeFromParent());
    world.children.whereType<ShieldPickup>().toList().forEach((s) => s.removeFromParent());
    world.children.whereType<StarBackground>().toList().forEach((b) => b.removeFromParent());
    world.add(StarBackground());
    activeBoss = null;
    picksTotal = 0;
    _picksRemaining = 0;
    xpSystem.reset();
    superchargeSystem.reset();
    player.position = size / 2;
    player.reset();
    _waveSystem.reset();
    resumeEngine();
  }
}
