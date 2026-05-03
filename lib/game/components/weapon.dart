import 'package:flame/components.dart';

import '../runebolt_game.dart';
import 'monster.dart';

abstract class Weapon extends Component with HasGameReference<RuneboltGame> {
  double damage;
  double fireRate;
  int upgradeLevel = 1;
  double _timer = 0;

  Weapon({required this.damage, required this.fireRate});

  double get fireInterval => 1.0 / fireRate;

  String get displayName;
  String get nextUpgradeDescription => 'Damage +30%';

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= fireInterval) {
      _timer = 0;
      final target = _nearestMonster();
      if (target != null) fire(game.player.position, target);
    }
  }

  void fire(Vector2 playerPos, Monster target);

  void applyUpgrade() {
    upgradeLevel++;
    damage *= 1.3;
  }

  Monster? _nearestMonster() {
    Monster? nearest;
    double minDist = double.infinity;
    for (final m in game.world.children.whereType<Monster>()) {
      final d = m.position.distanceTo(game.player.position);
      if (d < minDist) {
        minDist = d;
        nearest = m;
      }
    }
    return nearest;
  }
}
