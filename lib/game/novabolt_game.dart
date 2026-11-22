import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../audio/audio_manager.dart';
import '../stats/stats_manager.dart';
import 'components/background.dart';
import 'components/health_pickup.dart';
import 'components/hud.dart';
import 'components/joystick.dart';
import 'components/monster.dart';
import 'components/monster_boss.dart';
import 'components/player.dart';
import 'components/player_nova_burst.dart';
import 'components/projectile.dart';
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
  bool isBossReward = false;
  bool _levelUpPendingAfterContinue = false;

  double _playTimeSeconds = 0;
  double get playTimeSeconds => _playTimeSeconds;

  /// Armed Nova attack and the ones earned this run. Listen to it to react
  /// to switches and unlocks.
  final nova = NovaLoadout();
  NovaMode get activeNovaMode => nova.active;
  set activeNovaMode(NovaMode m) => nova.active = m;
  List<NovaMode> get unlockedNovaModes => nova.unlocked;

  /// True while the Nova selector wheel is open; the game runs in slow motion.
  bool novaSelectorOpen = false;
  NovaMode? pendingInheritMode;

  // Visual phase cycles through 10 distinct backgrounds.
  int get _visualPhase => bossPhase % 10;

  @override
  Color backgroundColor() => switch (_visualPhase) {
        0 => const Color(0xFF0D0D2B),  // deep space
        1 => const Color(0xFF06031C),  // alien planet sky
        2 => const Color(0xFF0A0018),  // nebula purple
        3 => const Color(0xFF150000),  // blood moon red
        4 => const Color(0xFF08000F),  // void storm
        5 => const Color(0xFF001520),  // crystal cavern
        6 => const Color(0xFF1A0800),  // solar flare
        7 => const Color(0xFF000505),  // galactic core
        8 => const Color(0xFF020006),  // shadow realm
        _ => const Color(0xFF000000),  // singularity
      };

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    camera.viewfinder.anchor = Anchor.topLeft;

    joystick = createMoveStick();
    aimJoystick = createAimStick();

    player = Player(position: size / 2);
    _waveSystem = WaveSystem();

    world.add(StarBackground());
    world.add(player);
    world.add(_waveSystem);
    camera.viewport.add(joystick);
    camera.viewport.add(aimJoystick);
    camera.viewport.add(Hud());
  }

  /// Left stick. Overridable so debug harnesses can inject input.
  JoystickComponent createMoveStick() => NovaJoystick(
        color: const Color(0xFFD8DEFF),
        aim: false,
        margin: const EdgeInsets.only(left: 56, bottom: 80),
      );

  /// Right stick (aim + fire).
  JoystickComponent createAimStick() => NovaJoystick(
        color: const Color(0xFF4DE8FF),
        aim: true,
        margin: const EdgeInsets.only(right: 56, bottom: 80),
      );

  // ── Game feel: screen shake + hit-stop ────────────────────────────────────
  // Purely presentational. Shake offsets the camera by a few pixels (the
  // viewfinder anchor stays top-left); hit-stop slows simulated time for a
  // few frames on heavy impacts.
  double _trauma = 0;
  double _hitStop = 0;
  double _slowMo = 0;
  final _shakeRng = math.Random();

  /// Add screen shake. [amount] 0–1; trauma is squared so small hits stay
  /// subtle and big ones read as big.
  void shake(double amount) => _trauma = math.min(1, _trauma + amount);

  /// Hold shake at least at [level] (continuous effects like the Nova beam).
  void rumble(double level) => _trauma = math.max(_trauma, level);

  /// Freeze the simulation for [seconds] (capped) — sells a heavy hit.
  void hitStop(double seconds) => _hitStop = math.max(_hitStop, math.min(seconds, 0.12));

  /// Run at quarter speed for [seconds] (boss kills).
  void slowMo(double seconds) => _slowMo = math.max(_slowMo, seconds);

  @override
  void update(double dt) {
    var scaled = dt;
    if (_hitStop > 0) {
      _hitStop -= dt;
      scaled = dt * 0.04;
    } else if (_slowMo > 0) {
      _slowMo -= dt;
      scaled = dt * 0.3;
    } else if (novaSelectorOpen) {
      scaled = dt * 0.25;
    }
    super.update(scaled);
    if (!isGameOver) _playTimeSeconds += dt;

    if (_trauma > 0) {
      _trauma = math.max(0, _trauma - dt * 1.8);
      final t2 = _trauma * _trauma;
      camera.viewfinder.position = Vector2(
        (_shakeRng.nextDouble() * 2 - 1) * 9 * t2,
        (_shakeRng.nextDouble() * 2 - 1) * 9 * t2,
      );
    } else if (!camera.viewfinder.position.isZero()) {
      camera.viewfinder.position = Vector2.zero();
    }
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
          AudioManager.instance.playBoss();
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
      nova.unlock(pendingInheritMode!);
      // pendingInheritMode stays set so the level-up screen can display it.
    }
    player.currentHp = player.maxHp;
    AudioManager.instance.playGame();
    shake(0.9);

    world.children.whereType<Monster>().toList().forEach((m) => m.removeFromParent());
    world.children.whereType<StarBackground>().toList().forEach((b) => b.removeFromParent());
    world.add(StarBackground());
    _waveSystem.onBossKilled();
    xpSystem.resetXp();
    _showLevelUp(xpSystem.currentLevel, isBossKill: true);
  }

  void _showLevelUp(int level, {bool isBossKill = false}) {
    if (isGameOver) return;
    isBossReward = isBossKill;
    if (isBossKill) {
      picksTotal = 3;
    } else {
      final luckyChance = bossPhase == 0 ? 0.10 : 0.20 + (bossPhase - 1) * 0.025;
      picksTotal = math.Random().nextDouble() < luckyChance ? 2 : 1;
    }
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
    final mode = activeNovaMode;
    if (mode == NovaMode.laser) {
      world.add(SuperchargeLaser());
    } else {
      world.add(PlayerNovaBurst(shotCount: mode.burstCount, color: mode.color, damage: mode.burstDamage));
    }
  }

  void onPlayerDeath() {
    if (isGameOver) return;
    isGameOver = true;
    // Level-up can fire in the same collision frame as death — game over wins.
    if (overlays.isActive('LevelUp')) {
      overlays.remove('LevelUp');
      _levelUpPendingAfterContinue = true;
    }
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
    if (_levelUpPendingAfterContinue) {
      _levelUpPendingAfterContinue = false;
      // Show the level-up that was interrupted by death; engine stays paused.
      overlays.add('LevelUp');
    } else {
      // Engine stays paused; CountdownOverlay calls resumeEngine() when done.
      overlays.add('Countdown');
    }
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
      isBossReward = false;
      pendingInheritMode = null; // clear if boss inherit wasn't selected
      resumeEngine();
    }
  }

  void restart() {
    isGameOver = false;
    _hasUsedContinue = false;
    isNewBest = false;
    _trauma = 0;
    _hitStop = 0;
    _slowMo = 0;
    novaSelectorOpen = false;
    killCount = 0;
    bossPhase = 0;
    _playTimeSeconds = 0;
    currentCards = [];
    bonusCards = [];
    nova.reset();
    pendingInheritMode = null;
    overlays.remove('GameOver');
    overlays.remove('Countdown');
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
    _levelUpPendingAfterContinue = false;
    xpSystem.reset();
    superchargeSystem.reset();
    player.position = size / 2;
    player.reset();
    _waveSystem.reset();
    resumeEngine();
  }
}
