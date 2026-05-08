import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/monster_boss_dreadnought.dart';
import '../components/monster_boss_void_tyrant.dart';
import '../components/monster_caster.dart';
import '../components/monster_grunt.dart';
import '../components/monster_speeder.dart';
import '../components/monster_tank.dart';
import '../novabolt_game.dart';

class WaveSystem extends Component with HasGameReference<NovaboltGame> {
  double _timer = 0;
  double _tankTimer = 0;
  bool _isBossFight = false;
  final _rng = math.Random();

  double get _spawnInterval {
    final lvl = game.xpSystem.currentLevel;
    if (lvl < 3) return 3.0;
    if (lvl < 5) return 2.0;
    if (lvl < 8) return 1.5;
    if (lvl < 12) return 1.0;
    return 0.7;
  }

  double get _tankSpawnInterval {
    final lvl = game.xpSystem.currentLevel;
    if (lvl < 5) return double.infinity;
    if (lvl < 8) return 15.0;
    if (lvl < 12) return 10.0;
    return 7.0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_isBossFight) return;

    _timer += dt;
    if (_timer >= _spawnInterval) {
      _timer = 0;
      _spawnRegular();
    }

    final tankInterval = _tankSpawnInterval;
    if (tankInterval != double.infinity) {
      _tankTimer += dt;
      if (_tankTimer >= tankInterval) {
        _tankTimer = 0;
        _spawnAt(MonsterTank(
          position: _randomEdgePosition(),
          playerLevel: _effectiveLevel,
        ));
      }
    }
  }

  int get _effectiveLevel => game.xpSystem.currentLevel + game.bossPhase * 5;

  void _spawnRegular() {
    final lvl = game.xpSystem.currentLevel;
    final eff = _effectiveLevel;
    final pos = _randomEdgePosition();
    final roll = _rng.nextDouble();
    if (lvl >= 7 && roll < 0.15) {
      _spawnAt(MonsterCaster(position: pos, playerLevel: eff));
    } else if (lvl >= 3 && roll < (lvl >= 7 ? 0.50 : 0.35)) {
      _spawnAt(MonsterSpeeder(position: pos, playerLevel: eff));
    } else {
      _spawnAt(MonsterGrunt(position: pos, playerLevel: eff));
    }
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
    final spawnPos = Vector2(game.size.x / 2, -80);
    final boss = (playerLevel >= 20 && playerLevel % 20 == 0)
        ? MonsterBossVoidTyrant(position: spawnPos, playerLevel: playerLevel)
        : MonsterBossDreadnought(position: spawnPos, playerLevel: playerLevel);
    game.activeBoss = boss;
    game.world.add(boss);
  }

  void onBossKilled() {
    _isBossFight = false;
    _timer = 0;
    _tankTimer = 0;
  }

  void reset() {
    _timer = 0;
    _tankTimer = 0;
    _isBossFight = false;
  }
}
