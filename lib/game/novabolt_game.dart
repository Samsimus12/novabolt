import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../stats/stats_manager.dart';
import 'components/background.dart';
import 'components/hud.dart';
import 'components/monster.dart';
import 'components/monster_boss.dart';
import 'components/player.dart';
import 'components/player_nova_burst.dart';
import 'components/projectile.dart';
import 'components/health_pickup.dart';
import 'components/shield_pickup.dart';
import 'components/supercharge_laser.dart';
import 'data/nova_mode.dart';
import 'data/upgrade_cards.dart';
import 'systems/supercharge_system.dart';
import 'systems/wave_system.dart';
import 'systems/xp_system.dart';

class NovaboltGame extends FlameGame with HasCollisionDetection {
  late Player player;
  late JoystickComponent joystick;
  late JoystickComponent aimJoystick;
  final XpSystem xpSystem = XpSystem();
  final SuperchargeSystem superchargeSystem = SuperchargeSystem();
  late WaveSystem _waveSystem;

  List<UpgradeCard> currentCards = [];
  List<StatBuffCard> bonusCards = [];
  bool isGameOver = false;
  bool _hasUsedContinue = false;
  bool get hasUsedContinue => _hasUsedContinue;
  int killCount = 0;
  bool isNewBest = false;
  int bossPhase = 0;
  BossMonster? activeBoss;
  int picksTotal = 0;
  int _picksRemaining = 0;

  NovaMode activeNovaMode = NovaMode.laser;
  Set<NovaMode> unlockedNovaModes = {NovaMode.laser};
  NovaMode? pendingInheritMode;

  @override
  Color backgroundColor() => switch (bossPhase.clamp(0, 2)) {
        1 => const Color(0xFF010C06),  // alien planet sky
        2 => const Color(0xFF0A0018),  // nebula purple
        // 3 => const Color(0xFF150000),  // blood moon red (Phase 3, future)
        _ => const Color(0xFF0D0D2B),  // deep space
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
    killCount++;
    superchargeSystem.addCharge(chargeValue.toDouble());
    if (xpValue > 0) {
      final scaledXp = (xpValue * (1 + xpSystem.currentLevel ~/ 7) * (1.0 + bossPhase * 0.25)).round();
      if (xpSystem.addXp(scaledXp)) {
        final level = xpSystem.currentLevel;
        if (level % 10 == 0) {
          _waveSystem.startBossFight(level);
          return;
        }
        _showLevelUp(level);
      }
    }
  }

  void onBossKilled() {
    activeBoss = null;
    bossPhase++;

    // Auto-inherit the boss's Nova attack and restore full HP.
    if (pendingInheritMode != null) {
      activeNovaMode = pendingInheritMode!;
      unlockedNovaModes.add(pendingInheritMode!);
      // pendingInheritMode stays set so the level-up screen can display it.
    }
    player.currentHp = player.maxHp;

    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    world.children.whereType<StarBackground>().toList().forEach((b) => b.removeFromParent());
    world.add(StarBackground());
    _waveSystem.onBossKilled();
    xpSystem.resetXp();
    _showLevelUp(xpSystem.currentLevel);
  }

  void _showLevelUp(int level) {
    picksTotal = (bossPhase + 1).clamp(1, 5);
    _picksRemaining = picksTotal;
    currentCards = generateUpgradeCards(this);
    bonusCards = rollBonusCards(this);
    for (final bonus in bonusCards) {
      bonus.apply(this);
    }
    overlays.add('LevelUp');
    pauseEngine();
  }

  int get currentPickIndex => picksTotal - _picksRemaining + 1;

  void activateSupercharge() {
    if (!superchargeSystem.activate()) return;
    switch (activeNovaMode) {
      case NovaMode.laser:
        world.add(SuperchargeLaser());
      case NovaMode.dreadnought:
        world.add(PlayerNovaBurst(
          shotCount: 12,
          color: const Color(0xFFFFDD00),
          damage: 6.0,
        ));
      case NovaMode.voidTyrant:
        world.add(PlayerNovaBurst(
          shotCount: 16,
          color: const Color(0xFFFF00CC),
          damage: 4.0,
        ));
    }
  }

  void onPlayerDeath() {
    if (isGameOver) return;
    isGameOver = true;
    isNewBest = StatsManager.instance.submitRun(
      level: xpSystem.currentLevel,
      kills: killCount,
    );
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
      bonusCards = [];
      picksTotal = 0;
      pendingInheritMode = null; // clear if boss inherit wasn't selected
      resumeEngine();
    }
  }

  void restart() {
    isGameOver = false;
    _hasUsedContinue = false;
    isNewBest = false;
    killCount = 0;
    bossPhase = 0;
    currentCards = [];
    bonusCards = [];
    activeNovaMode = NovaMode.laser;
    unlockedNovaModes = {NovaMode.laser};
    pendingInheritMode = null;
    overlays.remove('GameOver');
    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    world.children.whereType<Projectile>().toList().forEach((p) => p.removeFromParent());
    world.children.whereType<SuperchargeLaser>().toList().forEach((l) => l.removeFromParent());
    world.children.whereType<ShieldPickup>().toList().forEach((s) => s.removeFromParent());
    world.children.whereType<HealthPickup>().toList().forEach((h) => h.removeFromParent());
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
