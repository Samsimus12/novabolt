import 'dart:math' as math;

import 'package:flame/components.dart';

import '../components/monster_grunt.dart';
import '../runebolt_game.dart';

class WaveSystem extends Component with HasGameReference<RuneboltGame> {
  double _timer = 0;
  final _rng = math.Random();

  double get _spawnInterval {
    final lvl = game.xpSystem.currentLevel;
    if (lvl < 3) return 3.0;
    if (lvl < 5) return 2.0;
    if (lvl < 8) return 1.5;
    if (lvl < 12) return 1.0;
    return 0.7;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= _spawnInterval) {
      _timer = 0;
      _spawnGrunt();
    }
  }

  void _spawnGrunt() {
    final sz = game.size;
    double x, y;
    switch (_rng.nextInt(4)) {
      case 0:
        x = _rng.nextDouble() * sz.x;
        y = -50;
        break;
      case 1:
        x = sz.x + 50;
        y = _rng.nextDouble() * sz.y;
        break;
      case 2:
        x = _rng.nextDouble() * sz.x;
        y = sz.y + 50;
        break;
      default:
        x = -50;
        y = _rng.nextDouble() * sz.y;
    }
    game.world.add(MonsterGrunt(
      position: Vector2(x, y),
      playerLevel: game.xpSystem.currentLevel,
    ));
  }

  void reset() {
    _timer = 0;
  }
}
