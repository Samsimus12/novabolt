// Debug-only entrypoint that boots straight into a specific game moment so
// visual changes can be checked (and screenshotted) without playing to it.
//
//   flutter run -t lib/dev/scene_main.dart --dart-define=SCENE=boss --dart-define=PHASE=3
//
// SCENE: menu | shop | waves | nova | novaswitch | flow | boss | levelup | bossreward | gameover | countdown
// PHASE: 0-9, the visual/boss phase to start in (default 0); for shop, the tab
// Prefs dev_loadout (comma-separated ids to own + equip) and dev_focus (shop
// item to focus) are optional.
//
// Uses only the game's public API; the player regenerates hull every frame
// and the aim stick auto-tracks the nearest enemy so weapons keep firing.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ads/ad_manager.dart';
import '../audio/audio_manager.dart';
import '../coins/coin_manager.dart';
import '../cosmetics/catalog.dart';
import '../game/components/joystick.dart';
import '../game/components/monster.dart';
import '../game/components/monster_boss.dart';
import '../game/components/monster_boss_blood_colossus.dart';
import '../game/components/monster_boss_cosmic_behemoth.dart';
import '../game/components/monster_boss_dreadnought.dart';
import '../game/components/monster_boss_leviathan.dart';
import '../game/components/monster_boss_shadow_reaper.dart';
import '../game/components/monster_boss_singularity.dart';
import '../game/components/monster_boss_solar_titan.dart';
import '../game/components/monster_boss_storm_phantom.dart';
import '../game/components/monster_boss_void_emperor.dart';
import '../game/components/monster_boss_void_tyrant.dart';
import '../game/components/monster_caster.dart';
import '../game/components/monster_grunt.dart';
import '../game/components/monster_speeder.dart';
import '../game/components/monster_tank.dart';
import '../game/components/weapon_spread_shot.dart';
import '../game/components/weapon_sword_aura.dart';
import '../game/data/nova_mode.dart';
import '../game/novabolt_game.dart';
import '../main.dart';
import '../screens/countdown_overlay.dart';
import '../screens/game_controls_overlay.dart';
import '../screens/game_over_screen.dart';
import '../screens/level_up_screen.dart';
import '../screens/nova_core.dart';
import '../screens/shop_screen.dart';
import '../stats/stats_manager.dart';
import '../ui/theme/app_theme.dart';

// Compile-time defaults; a SharedPreferences value (dev_scene / dev_phase)
// wins so one simulator build can be relaunched into each scene, e.g.
//   xcrun simctl spawn booted defaults write com.sammorrison.novabolt flutter.dev_scene boss
var _scene = const String.fromEnvironment('SCENE', defaultValue: 'menu');
var _phase = const int.fromEnvironment('PHASE', defaultValue: 0);
String? _focus;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  _scene = prefs.getString('dev_scene') ?? _scene;
  _phase = prefs.getInt('dev_phase') ?? _phase;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  if (_scene == 'menu') {
    runApp(const NovaboltApp());
    return;
  }
  await AdManager.instance.init();
  await CoinManager.instance.init();
  await AudioManager.instance.init();
  await StatsManager.instance.init();
  // Optional loadout: comma-separated item ids to buy (dev coins) and equip,
  // e.g. 'nebula,shield_corona,nova_helix,thruster_prism,boom_supernova'.
  _focus = prefs.getString('dev_focus');
  final loadout = prefs.getString('dev_loadout') ?? const String.fromEnvironment('LOADOUT');
  if (loadout.isNotEmpty) {
    final mgr = CoinManager.instance;
    for (final id in loadout.split(',')) {
      for (final kind in CosmeticKind.values) {
        for (final item in catalogFor(kind)) {
          if (item.id != id.trim()) continue;
          if (!mgr.owns(item.ownId)) {
            await mgr.addCoins(item.price);
            await mgr.purchase(item.ownId, item.price);
          }
          await mgr.select(item);
        }
      }
    }
  }
  if (_scene == 'shop') {
    if (CoinManager.instance.totalCoins < 600) await CoinManager.instance.addCoins(640);
    final focus = prefs.getString('dev_focus');
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildNovaboltTheme(),
      home: ShopScreen(initialTab: _phase, initialFocus: focus),
    ));
    return;
  }
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildNovaboltTheme(),
    home: GameWidget<NovaboltGame>.controlled(
      gameFactory: _DevGame.new,
      initialActiveOverlays: const ['GameControls'],
      overlayBuilderMap: {
        'GameControls': (context, game) =>
            GameControlsOverlay(game: game, onMenu: () {}),
        'GameOver': (context, game) => GameOverScreen(game: game),
        'LevelUp': (context, game) => LevelUpScreen(game: game),
        'Countdown': (context, game) => CountdownOverlay(game: game),
      },
    ),
  ));
}

class _DevGame extends NovaboltGame {
  final _rng = math.Random(7);
  double _t = 0;
  bool _sceneApplied = false;

  @override
  Future<void> onLoad() async {
    bossPhase = _phase;
    await super.onLoad();
  }

  @override
  JoystickComponent createAimStick() => _AutoAimJoystick();

  @override
  void onMount() {
    super.onMount();
    if (const bool.fromEnvironment('FPS', defaultValue: true)) {
      camera.viewport.add(FpsTextComponent(position: Vector2(12, size.y - 28), priority: 100));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (!isGameOver && _scene != 'gameover') player.currentHp = math.max(player.currentHp, player.maxHp * 0.62);
    if (!_sceneApplied && _t > 0.4) {
      _sceneApplied = true;
      _applyScene();
    }
    final aim = aimJoystick as _AutoAimJoystick;
    final target = world.children
        .whereType<Monster>()
        .where((m) => m.position.x > 0 && m.position.x < size.x && m.position.y > 0 && m.position.y < size.y)
        .fold<Monster?>(null, (best, m) =>
            best == null || m.position.distanceTo(player.position) < best.position.distanceTo(player.position) ? m : best);
    if (target != null) {
      aim.forced = (target.position - player.position).normalized();
    } else {
      aim.forced = Vector2(math.cos(_t), math.sin(_t));
    }
  }

  void _spawnRing(int count, Monster Function(Vector2) make) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final r = 140 + _rng.nextDouble() * 160;
      world.add(make(Vector2(size.x / 2 + math.cos(a) * r, size.y / 2 + math.sin(a) * r)));
    }
  }

  void _applyScene() {
    const lvl = 8;
    switch (_scene) {
      case 'waves':
        xpSystem.currentLevel = 8;
        xpSystem.currentXp = -100000000;
        player.add(WeaponSpreadShot());
        player.add(WeaponSwordAura());
        player.shieldHp = 30;
        superchargeSystem.addCharge(70);
        _spawnRing(7, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        _spawnRing(3, (p) => MonsterSpeeder(position: p, playerLevel: lvl));
        _spawnRing(2, (p) => MonsterTank(position: p, playerLevel: lvl));
        _spawnRing(2, (p) => MonsterCaster(position: p, playerLevel: lvl));
      case 'nova':
        xpSystem.currentLevel = 8;
        xpSystem.currentXp = -100000000;
        _spawnRing(8, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        _spawnRing(3, (p) => MonsterTank(position: p, playerLevel: lvl));
        superchargeSystem.addCharge(100);
        activateSupercharge();
      case 'boss':
        xpSystem.currentLevel = 10;
        xpSystem.currentXp = -100000000;
        player.add(WeaponSpreadShot());
        superchargeSystem.addCharge(100);
        final pos = Vector2(size.x / 2, size.y * 0.28);
        final BossMonster boss = switch (bossPhase % 10) {
          0 => MonsterBossDreadnought(position: pos, playerLevel: 10),
          1 => MonsterBossVoidTyrant(position: pos, playerLevel: 10),
          2 => MonsterBossLeviathan(position: pos, playerLevel: 10),
          3 => MonsterBossBloodColossus(position: pos, playerLevel: 10),
          4 => MonsterBossStormPhantom(position: pos, playerLevel: 10),
          5 => MonsterBossCosmicBehemoth(position: pos, playerLevel: 10),
          6 => MonsterBossShadowReaper(position: pos, playerLevel: 10),
          7 => MonsterBossSolarTitan(position: pos, playerLevel: 10),
          8 => MonsterBossVoidEmperor(position: pos, playerLevel: 10),
          _ => MonsterBossSingularity(position: pos, playerLevel: 10),
        };
        boss.currentHp = boss.stats.maxHp * 0.7;
        activeBoss = boss;
        world.add(boss);
      case 'levelup':
        xpSystem.currentLevel = 4;
        player.add(WeaponSpreadShot());
        _spawnRing(5, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        onMonsterKilled(100000, 0);
      case 'novaswitch':
        // dev_focus: "" (just the core), "wheel:<hover>" or "all" / "all:wheel:<hover>"
        // for every mode unlocked (full ring).
        final f = _focus ?? '';
        final extra = f.startsWith('all')
            ? NovaMode.values.skip(1).toList()
            : [NovaMode.dreadnought, NovaMode.leviathan, NovaMode.solarTitan, NovaMode.singularity];
        for (final m in extra) {
          nova.unlock(m);
        }
        nova.active = NovaMode.leviathan;
        xpSystem.currentLevel = 24;
        xpSystem.currentXp = -100000000;
        _spawnRing(6, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        superchargeSystem.addCharge(100);
        final w = RegExp(r'wheel:(-?\d+)').firstMatch(f);
        if (w != null) NovaCore.debugWheel.value = int.parse(w.group(1)!);
      case 'bossreward':
        xpSystem.currentLevel = 10;
        pendingInheritMode = NovaMode.dreadnought;
        onBossKilled();
      case 'gameover':
        xpSystem.currentLevel = 14;
        killCount = 212;
        _spawnRing(6, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        Future.delayed(const Duration(milliseconds: 600), onPlayerDeath);
      case 'flow':
        // Smoke test: die, continue, countdown, die again, restart.
        _spawnRing(6, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        Future.delayed(const Duration(milliseconds: 500), onPlayerDeath);
        Future.delayed(const Duration(milliseconds: 1500), continueWithHalfHp);
        Future.delayed(const Duration(milliseconds: 5800), onPlayerDeath);
        Future.delayed(const Duration(milliseconds: 6800), restart);
      case 'countdown':
        _spawnRing(6, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        Future.delayed(const Duration(milliseconds: 300), () {
          pauseEngine();
          overlays.add('Countdown');
        });
    }
  }
}

class _AutoAimJoystick extends NovaJoystick {
  Vector2? forced;
  _AutoAimJoystick()
      : super(color: const Color(0xFF4DE8FF), aim: true, margin: const EdgeInsets.only(right: 56, bottom: 80));

  @override
  Vector2 get relativeDelta => forced ?? super.relativeDelta;
}
