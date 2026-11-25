// Debug-only entrypoint that boots straight into a specific game moment so
// visual changes can be checked (and screenshotted) without playing to it.
//
//   flutter run -t lib/dev/scene_main.dart --dart-define=SCENE=boss --dart-define=PHASE=3
//
// CLASS: vanguard | interceptor | bulwark | conduit (owns and flies it)
// SCENE: menu | shop | hangar | records | missions | waves | nova | novaswitch | flow | revive | overdrive | wingman | emp | boss | levelup | bossreward | gameover | countdown
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

import '../arcade/arcade_manager.dart';
import '../arcade/arcade_screen.dart';
import '../arcade/assault/assault_screen.dart';
import '../arcade/cockpit/cockpit_screen.dart';
import '../arcade/invaders/invaders_screen.dart';
import '../arcade/shmup/shmup_screen.dart';
import '../arcade/starport/starport_screen.dart';
import '../arcade/thread/thread_screen.dart';
import '../ads/ad_manager.dart';
import '../audio/audio_manager.dart';
import '../audio/sfx.dart';
import '../coins/coin_manager.dart';
import '../coins/hangar_manager.dart';
import '../cosmetics/catalog.dart';
import '../game/data/endgame.dart';
import '../game/data/relics.dart';
import '../game/data/curses.dart';
import '../game/components/boss_projectile.dart';
import '../game/components/joystick.dart';
import '../game/components/emp.dart';
import '../game/components/monster.dart';
import '../game/components/wingman.dart';
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
import '../game/data/daily_challenge.dart';
import '../game/data/nova_mode.dart';
import '../game/novabolt_game.dart';
import 'diagnostics.dart';
import '../main.dart';
import '../screens/countdown_overlay.dart';
import '../screens/game_controls_overlay.dart';
import '../screens/game_over_screen.dart';
import '../screens/hangar_screen.dart';
import '../screens/level_up_screen.dart';
import '../screens/records_screen.dart';
import '../screens/nova_core.dart';
import '../screens/shop_screen.dart';
import '../screens/missions_screen.dart';
import '../stats/mission_manager.dart';
import '../stats/run_log.dart';
import '../stats/stats_manager.dart';
import '../ui/theme/app_theme.dart';

// Compile-time defaults; a SharedPreferences value (dev_scene / dev_phase)
// wins so one simulator build can be relaunched into each scene, e.g.
//   xcrun simctl spawn booted defaults write com.sammorrison.novabolt flutter.dev_scene boss
var _scene = const String.fromEnvironment('SCENE', defaultValue: 'menu');
var _phase = const int.fromEnvironment('PHASE', defaultValue: 0);
// Starting boss HP fraction for SCENE=boss (dev_hp pref wins), e.g. 0.3 to
// land straight in a boss's last stage.
var _bossHp = double.tryParse(const String.fromEnvironment('HP', defaultValue: '0.7')) ?? 0.7;
String? _focus;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  startDiagnostics(autoPick: const bool.fromEnvironment('AUTOPICK'));
  final prefs = await SharedPreferences.getInstance();
  // An explicit --dart-define wins over the pref (the simulator's prefs
  // daemon can serve stale values after a plist edit).
  if (!const bool.hasEnvironment('SCENE')) _scene = prefs.getString('dev_scene') ?? _scene;
  if (!const bool.hasEnvironment('PHASE')) _phase = prefs.getInt('dev_phase') ?? _phase;
  if (!const bool.hasEnvironment('HP')) _bossHp = prefs.getDouble('dev_hp') ?? _bossHp;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // BEATEN=true: every boss counts as beaten (opens the Endgame menu card
  // and a full 10-boss rush).
  if (const bool.fromEnvironment('BEATEN')) {
    await prefs.setStringList('stats_bosses_defeated', [for (var i = 0; i < 10; i++) '$i']);
  }
  if (_scene == 'menu') {
    runApp(const NovaboltApp());
    return;
  }
  await AdManager.instance.init();
  await CoinManager.instance.init();
  await AudioManager.instance.init();
  await SfxManager.instance.init();
  // CLASS=bulwark etc.: own and fly that ship class in this test build.
  CurseRules.forceOffer = const bool.fromEnvironment('CURSE');
  const cls = String.fromEnvironment('CLASS');
  if (cls.isNotEmpty) {
    await prefs.setStringList('ship_classes', [cls]);
    await prefs.setString('ship_class', cls);
  }
  await HangarManager.instance.init();
  await StatsManager.instance.init();
  await DailyManager.instance.init();
  await EndgameManager.instance.init();
  await ArcadeManager.instance.init();
  await RunLog.instance.init();
  await MissionManager.instance.init();
  // Test scenes never move the real missions (except the missions screen).
  MissionManager.instance.enabled = _scene == 'missions';
  if (_scene == 'missions') {
    runApp(MaterialApp(builder: materialRoot, debugShowCheckedModeBanner: false, theme: buildNovaboltTheme(), home: const MissionsScreen()));
    return;
  }
  // --dart-define=STATS=true turns the combat-stats overlay on.
  if (const bool.fromEnvironment('STATS')) await RunLog.instance.setOverlayEnabled(true);
  if (_scene == 'records') {
    runApp(MaterialApp(builder: materialRoot, debugShowCheckedModeBanner: false, theme: buildNovaboltTheme(), home: const RecordsScreen()));
    return;
  }
  // SCENE=arcade (the hub) / thread (Thread the Needle) / assault (Ground
  // Assault); PHASE = seed.
  if (_scene == 'arcade' || _scene == 'thread' || _scene == 'assault' || _scene == 'invaders' || _scene == 'cockpit' || _scene == 'shmup' || _scene == 'starport') {
    runApp(MaterialApp(
      builder: materialRoot,
      debugShowCheckedModeBanner: false,
      theme: buildNovaboltTheme(),
      home: switch (_scene) {
        'arcade' => const ArcadeScreen(),
        'assault' => AssaultScreen(seed: _phase),
        'invaders' => InvadersScreen(seed: _phase),
        'cockpit' => CockpitScreen(game: ArcadeGame.cockpit, seed: _phase),
        'shmup' => ShmupScreen(seed: _phase),
        'starport' => StarportScreen(seed: _phase),
        _ => ThreadScreen(seed: _phase),
      },
    ));
    return;
  }
  if (_scene == 'hangar') {
    if (CoinManager.instance.totalCoins < 600) await CoinManager.instance.addCoins(900);
    runApp(MaterialApp(builder: materialRoot, debugShowCheckedModeBanner: false, theme: buildNovaboltTheme(), home: const HangarScreen()));
    return;
  }
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
      builder: materialRoot,
      debugShowCheckedModeBanner: false,
      theme: buildNovaboltTheme(),
      home: ShopScreen(initialTab: _phase, initialFocus: focus),
    ));
    return;
  }
  runApp(MaterialApp(
    builder: materialRoot,
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
  // ASC=3 plays Ascension 3; RUSH=true plays a boss rush.
  _DevGame()
      : super(
          mode: const RunMode(
            ascension: int.fromEnvironment('ASC'),
            bossRush: bool.fromEnvironment('RUSH'),
          ),
        );

  final _rng = math.Random(7);
  double _t = 0;
  bool _sceneApplied = false;

  @override
  Future<void> onLoad() async {
    bossPhase = _phase;
    // In an Ascension test, count the earlier bosses as beaten this run, so
    // SCENE=boss PHASE=9 ASC=1 ends in the Victory.
    if (mode.ascension > 0) bossesBeaten = _phase;
    await super.onLoad();
  }

  @override
  JoystickComponent createAimStick() => _AutoAimJoystick();

  @override
  bool get savesRuns => false;

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
    if (!isGameOver && _scene != 'gameover' && _scene != 'secondwind') player.currentHp = math.max(player.currentHp, player.maxHp * 0.62);
    if (!_sceneApplied && _t > 0.4) {
      _sceneApplied = true;
      _applyScene();
    }
    final aim = aimJoystick as _AutoAimJoystick;
    final target = activeBoss ?? world.children
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
        // PHASE picks the Nova attack (0 laser … 10 Event Horizon).
        nova.unlock(NovaMode.values[_phase.clamp(0, NovaMode.values.length - 1)]); // unlock arms it too
        activateSupercharge();
      case 'boss':
        // --dart-define=MUSIC=true: play the boss track like a real fight,
        // so the crossfade back to the game track happens on the kill.
        if (const bool.fromEnvironment('MUSIC')) AudioManager.instance.playBoss();
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
        boss.currentHp = boss.stats.maxHp * _bossHp;
        activeBoss = boss;
        tracker.bossStarted(playTimeSeconds);
        world.add(boss);
      case 'levelup':
        xpSystem.currentLevel = 4;
        player.add(WeaponSpreadShot());
        _spawnRing(5, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        onMonsterKilled(100000, 0);
      case 'bosslevel':
        // Repro: a normal level-up landing in the same frame as a boss kill.
        xpSystem.currentLevel = 10;
        pendingInheritMode = NovaMode.dreadnought;
        onBossKilled();
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
        Future.delayed(const Duration(milliseconds: 1500), continueFromAd);
        Future.delayed(const Duration(milliseconds: 5800), onPlayerDeath);
        Future.delayed(const Duration(milliseconds: 6800), restart);
      case 'overdrive':
        // One kill from Overdrive, next to a boss whose spread shots graze.
        combo = 49;
        comboTimer = 30;
        _spawnRing(10, (p) => MonsterGrunt(position: p, playerLevel: lvl)..minion = true);
        // Bullets on lanes beside the ship: 34px and 45px off pass inside
        // the graze band (22 + 7 + 18 = 47px), 70px off doesn't.
        var lane = 0;
        world.add(TimerComponent(
          period: 0.35,
          repeat: true,
          onTick: () {
            const offs = [34.0, -45.0, 70.0];
            final dy = offs[lane++ % offs.length];
            world.add(BossProjectile(
              position: Vector2(-20, player.position.y + dy),
              direction: Vector2(1, 0),
              damage: 5,
              speed: 420,
            ));
          },
        ));
        final tyrant = MonsterBossVoidTyrant(position: Vector2(size.x / 2, size.y * 0.22), playerLevel: 30);
        activeBoss = tyrant;
        world.add(tyrant);
      case 'wingman':
        // A wingman pickup on the ship (collected at once) in a mixed wave;
        // casters shoot at it, grunts/speeders peel off to chase it.
        // The pickup sits 30px off the ship so their outlines cross (the
        // harness ship never moves). dev_focus "pickup": 80px off instead, to
        // look at the pickup itself.
        xpSystem.currentLevel = 8;
        xpSystem.currentXp = -100000000;
        player.add(WeaponSpreadShot());
        _spawnRing(8, (p) => MonsterGrunt(position: p, playerLevel: lvl));
        _spawnRing(4, (p) => MonsterSpeeder(position: p, playerLevel: lvl));
        _spawnRing(2, (p) => MonsterCaster(position: p, playerLevel: lvl));
        _spawnRing(1, (p) => MonsterTank(position: p, playerLevel: lvl));
        final at = player.position + (_focus == 'pickup' ? Vector2(70, 40) : Vector2(30, 0));
        world.add(WingmanPickup(position: at));
      case 'emp':
        // An EMP pickup 30px off the ship in a mixed wave (dev_focus "pickup":
        // 80px off, to look at the pickup), and a boss to see the weaker slow.
        xpSystem.currentLevel = 8;
        xpSystem.currentXp = -100000000;
        player.add(WeaponSpreadShot());
        _spawnRing(10, (p) => MonsterGrunt(position: p, playerLevel: lvl)..minion = true);
        _spawnRing(5, (p) => MonsterSpeeder(position: p, playerLevel: lvl)..minion = true);
        _spawnRing(3, (p) => MonsterCaster(position: p, playerLevel: lvl)..minion = true);
        final at = player.position + (_focus == 'pickup' ? Vector2(70, 40) : Vector2(30, 0));
        Future.delayed(const Duration(milliseconds: 900), () => world.add(EmpPickup(position: at)));
      case 'revive':
        // Ad continue in the middle of a crowded fight: full hull + shield,
        // nearby bullets cleared, ~2s blinking invulnerability.
        // Minions give no XP, so no level-up screen gets in the way.
        _spawnRing(8, (p) => MonsterGrunt(position: p, playerLevel: lvl)..minion = true);
        final emperor = MonsterBossVoidEmperor(position: Vector2(size.x / 2, size.y * 0.25), playerLevel: 30);
        activeBoss = emperor;
        world.add(emperor);
        Future.delayed(const Duration(milliseconds: 2500), onPlayerDeath);
        Future.delayed(const Duration(milliseconds: 3500), continueFromAd);
      case 'secondwind':
        // Second wind relic: a lethal hit mid-fight brings the ship back at
        // half hull with the revive shockwave instead of ending the run.
        addRelic(Relic.secondWind);
        _spawnRing(8, (p) => MonsterGrunt(position: p, playerLevel: lvl)..minion = true);
        final emperor = MonsterBossVoidEmperor(position: Vector2(size.x / 2, size.y * 0.25), playerLevel: 30);
        activeBoss = emperor;
        world.add(emperor);
        Future.delayed(const Duration(milliseconds: 2500), () {
          player.invulnerable = 0;
          player.takeDamage(99999);
        });
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
