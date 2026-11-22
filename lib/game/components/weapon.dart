import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../data/balance.dart';
import '../novabolt_game.dart';

abstract class Weapon extends Component with HasGameReference<NovaboltGame> {
  double damage;
  double fireRate;
  int upgradeLevel = 1;

  /// Set by an evolution card; each weapon changes how it fires when true.
  bool evolved = false;
  String? evolvedName;

  /// Name shown to the player (the evolved name once evolved).
  String get label => evolved ? (evolvedName ?? displayName) : displayName;
  double _timer = 0;

  Weapon({required this.damage, required this.fireRate});

  /// Shots per second including the run-wide Overcharge bonus.
  double get effectiveFireRate =>
      fireRate *
      (1 + game.fireRateBonus) *
      game.shipClass.fireRate *
      (game.overdriveActive ? 1 + Balance.overdriveFireRate : 1);
  double get fireInterval => 1.0 / effectiveFireRate;

  /// Damage per shot including the run-wide Targeting Array bonus. Weapons
  /// pass this (not [damage]) to what they fire.
  double get shotDamage => damage * (1 + game.weaponDamageBonus) * game.shipClass.gunDamage;

  String get displayName;
  bool get isUpgradeable => true;
  String get nextUpgradeDescription => 'Damage +30%';

  @override
  void update(double dt) {
    super.update(dt);
    _timer += dt;
    if (_timer >= fireInterval) {
      final delta = game.aimJoystick.relativeDelta;
      if (!delta.isZero()) {
        _timer = 0;
        fire(game.player.position, delta.normalized());
        SfxManager.instance.play(Sfx.shoot);
      }
    }
  }

  void fire(Vector2 playerPos, Vector2 direction);

  void applyUpgrade() {
    upgradeLevel++;
    damage *= 1.3;
  }
}
