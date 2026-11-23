import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/monster.dart';
import '../components/monster_boss.dart';
import '../components/monster_boss_blood_colossus.dart';
import '../components/monster_boss_cosmic_behemoth.dart';
import '../components/monster_boss_dreadnought.dart';
import '../components/monster_boss_leviathan.dart';
import '../components/monster_boss_shadow_reaper.dart';
import '../components/monster_boss_singularity.dart';
import '../components/monster_boss_solar_titan.dart';
import '../components/monster_boss_storm_phantom.dart';
import '../components/monster_boss_void_emperor.dart';
import '../components/monster_boss_void_tyrant.dart';
import '../components/monster_caster.dart';
import '../components/monster_grunt.dart';
import '../components/monster_speeder.dart';
import '../components/monster_tank.dart';
import '../data/elite_balance.dart';
import '../novabolt_game.dart';
import 'wave_events.dart';

class WaveSystem extends Component with HasGameReference<NovaboltGame> {
  double _timer = 0;
  double _tankTimer = 0;
  bool _isBossFight = false;
  /// Level at the last boss kill (wave difficulty restarts from it). Saved
  /// and restored with a run.
  int bossKillLevel = 0;
  final _rng = math.Random();

  /// Wave events (meteor storm, gold rush, swarm, blackout) and this run's
  /// elite / gold-rush tallies. Added to the world next to this system.
  final WaveEvents events = WaveEvents();

  /// Last level seen, to notice level-ups (-1 = not yet read).
  int _lastLevel = -1;

  // Test builds only: --dart-define=ELITES=true makes half of all spawns elite.
  static const _forceElites = bool.fromEnvironment('ELITES');

  @override
  void onMount() {
    super.onMount();
    if (events.parent == null) parent?.add(events);
  }

  // Levels elapsed since the last boss kill (or game start).
  int get _waveLevel => game.xpSystem.currentLevel - bossKillLevel;

  double get _spawnInterval {
    final wl = _waveLevel;
    if (wl < 3) return 3.0;
    if (wl < 5) return 2.0;
    if (wl < 8) return 1.5;
    if (wl < 12) return 1.0;
    return 0.7;
  }

  double get _tankSpawnInterval {
    final wl = _waveLevel;
    if (wl < 5) return double.infinity;
    if (wl < 8) return 15.0;
    if (wl < 12) return 10.0;
    return 7.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _trackLevel();
    // Boss rush: no waves, the game brings in the bosses itself.
    if (_isBossFight || game.mode.bossRush) return;

    _timer += dt;
    final swarm = events.isSwarm ? WaveEventBalance.swarmIntervalScale : 1.0;
    if (_timer >= _spawnInterval * game.spawnIntervalMultiplier * swarm) {
      _timer = 0;
      _spawnRegular();
    }

    final tankInterval = _tankSpawnInterval;
    if (tankInterval != double.infinity) {
      _tankTimer += dt;
      if (_tankTimer >= tankInterval) {
        _tankTimer = 0;
        _spawnAt(_maybeElite(MonsterTank(
          position: _randomEdgePosition(),
          playerLevel: _effectiveLevel,
        )));
      }
    }
  }

  int get _effectiveLevel => game.xpSystem.currentLevel + game.bossPhase * 8;

  /// Notices level-ups (they happen inside game.onMonsterKilled) and hands
  /// them to [events]. Several levels at once are each checked.
  void _trackLevel() {
    final lvl = game.xpSystem.currentLevel;
    // First frame, restart, or a saved run being restored (a jump of many
    // levels at once): just sync, it isn't a level-up.
    if (_lastLevel < 0 || lvl < _lastLevel || lvl - _lastLevel > 3 || game.mode.bossRush) {
      _lastLevel = lvl;
      return;
    }
    if (lvl == _lastLevel) return;
    for (var l = _lastLevel + 1; l <= lvl; l++) {
      if (_isBossFight) break;
      events.onLevelUp(l - bossKillLevel, isBossLevel: l % 10 == 0);
    }
    _lastLevel = lvl;
  }

  void _spawnRegular() {
    final wl = _waveLevel;
    final eff = _effectiveLevel;
    final pos = _randomEdgePosition();
    final roll = _rng.nextDouble();
    if (events.isSwarm) {
      // Swarm: fast spawns, light enemies only, no elites.
      _spawnAt(roll < WaveEventBalance.swarmSpeederShare
          ? MonsterSpeeder(position: pos, playerLevel: eff)
          : MonsterGrunt(position: pos, playerLevel: eff));
      return;
    }
    if (wl >= 7 && roll < 0.15) {
      _spawnAt(_maybeElite(MonsterCaster(position: pos, playerLevel: eff)));
    } else if (wl >= 3 && roll < (wl >= 7 ? 0.50 : 0.35)) {
      _spawnAt(_maybeElite(MonsterSpeeder(position: pos, playerLevel: eff)));
    } else {
      _spawnAt(_maybeElite(MonsterGrunt(position: pos, playerLevel: eff)));
    }
  }

  /// Rolls the elite chance for a fresh wave spawn (never bosses/minions).
  Monster _maybeElite(Monster m) {
    if (_isBossFight || _waveLevel < EliteBalance.minWaveLevel) return m;
    final chance = _forceElites
        ? 0.5
        : math.min(EliteBalance.maxChance * game.eliteChanceMultiplier,
                (EliteBalance.baseChance + EliteBalance.chancePerLevel * _effectiveLevel) * game.eliteChanceMultiplier)
            .clamp(0.0, 0.9);
    if (_rng.nextDouble() < chance) {
      m.makeElite(EliteMod.values[_rng.nextInt(EliteMod.values.length)]);
    }
    return m;
  }

  void _spawnAt(Component monster) {
    game.world.add(monster);
  }

  Vector2 _randomEdgePosition() {
    final sz = game.size;
    switch (_rng.nextInt(4)) {
      case 0:
        return Vector2(_rng.nextDouble() * sz.x, -50);
      case 1:
        return Vector2(sz.x + 50, _rng.nextDouble() * sz.y);
      case 2:
        return Vector2(_rng.nextDouble() * sz.x, sz.y + 50);
      default:
        return Vector2(-50, _rng.nextDouble() * sz.y);
    }
  }

  void startBossFight(int playerLevel) {
    _isBossFight = true;
    _timer = 0;
    _tankTimer = 0;
    events.clear();
    final spawnPos = Vector2(game.size.x / 2, -80);
    // Cycle through 10 unique bosses; bossPhase is the count already defeated.
    final BossMonster boss = switch (game.bossPhase % 10) {
      0 => MonsterBossDreadnought(position: spawnPos, playerLevel: playerLevel),
      1 => MonsterBossVoidTyrant(position: spawnPos, playerLevel: playerLevel),
      2 => MonsterBossLeviathan(position: spawnPos, playerLevel: playerLevel),
      3 => MonsterBossBloodColossus(position: spawnPos, playerLevel: playerLevel),
      4 => MonsterBossStormPhantom(position: spawnPos, playerLevel: playerLevel),
      5 => MonsterBossCosmicBehemoth(position: spawnPos, playerLevel: playerLevel),
      6 => MonsterBossShadowReaper(position: spawnPos, playerLevel: playerLevel),
      7 => MonsterBossSolarTitan(position: spawnPos, playerLevel: playerLevel),
      8 => MonsterBossVoidEmperor(position: spawnPos, playerLevel: playerLevel),
      _ => MonsterBossSingularity(position: spawnPos, playerLevel: playerLevel),
    };
    game.activeBoss = boss;
    game.world.add(boss);
  }

  void onBossKilled() {
    _isBossFight = false;
    _timer = 0;
    _tankTimer = 0;
    bossKillLevel = game.xpSystem.currentLevel;
    _lastLevel = game.xpSystem.currentLevel;
    events.clear();
  }

  void reset() {
    _timer = 0;
    _tankTimer = 0;
    _isBossFight = false;
    bossKillLevel = 0;
    _lastLevel = -1;
    events.resetRun();
  }
}
