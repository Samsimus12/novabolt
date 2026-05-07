import '../data/monster_data.dart';
import 'boss_projectile.dart';
import 'monster.dart';

abstract class BossMonster extends Monster {
  double _fireTimer = 0;

  double get fireInterval;
  double get projectileDamage;
  String get displayName;

  BossMonster({required super.position, required MonsterStats stats})
      : super(stats: stats);

  @override
  void update(double dt) {
    super.update(dt);
    if (isDead) return;
    _fireTimer += dt;
    if (_fireTimer >= fireInterval) {
      _fireTimer = 0;
      _fireAtPlayer();
    }
  }

  void _fireAtPlayer() {
    final dir = game.player.position - position;
    if (dir.length < 1) return;
    game.world.add(BossProjectile(
      position: position.clone(),
      direction: dir.normalized(),
      damage: projectileDamage,
    ));
  }

  @override
  void onDie() {
    game.onBossKilled();
  }
}
