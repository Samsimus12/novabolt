import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/monster_boss_dreadnought.dart';
import '../components/monster_grunt.dart';
import '../components/monster_speeder.dart';
import '../components/monster_tank.dart';
import '../runebolt_game.dart';

class WaveSystem extends Component with HasGameReference<RuneboltGame> {
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
          playerLevel: game.xpSystem.currentLevel,
        ));
      }
    }
  }

  void _spawnRegular() {
    final lvl = game.xpSystem.currentLevel;
    final pos = _randomEdgePosition();
    if (lvl >= 3 && _rng.nextDouble() < 0.35) {
      _spawnAt(MonsterSpeeder(position: pos, playerLevel: lvl));
    } else {
      _spawnAt(MonsterGrunt(position: pos, playerLevel: lvl));
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
    final boss = MonsterBossDreadnought(
      position: Vector2(game.size.x / 2, -80),
      playerLevel: playerLevel,
    );
    game.activeBoss = boss;
    game.world.add(boss);
  }

  void onBossKilled() {
    _isBossFight = false;
  }

  void reset() {
    _timer = 0;
    _tankTimer = 0;
    _isBossFight = false;
  }
}
