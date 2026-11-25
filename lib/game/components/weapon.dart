import 'package:flame/components.dart';

import '../../audio/sfx.dart';
import '../data/balance.dart';
import '../novabolt_game.dart';

abstract class Weapon extends Component with HasGameReference<NovaboltGame> {
  double damage;
  double fireRate;

  /// The weapon as first acquired; an evolution restarts from these.
  final double baseDamage, baseFireRate;
  int upgradeLevel = 1;

  /// Set by an evolution card; each weapon changes how it fires when true.
  bool evolved = false;
  String? evolvedName;

  /// Name shown to the player (the evolved name once evolved).
  String get label => evolved ? (evolvedName ?? displayName) : displayName;
  double _timer = 0;

  Weapon({required this.damage, required this.fireRate})
      : baseDamage = damage,
        baseFireRate = fireRate;

  /// Shots per second including the run-wide Overcharge bonus.
  double get effectiveFireRate =>
      fireRate *
      (1 + game.fireRateBonus) *
      game.shipClass.fireRate *
      (game.overdriveActive ? 1 + Balance.overdriveFireRate : 1) *
      game.abilities.fireRateMultiplier;
  double get fireInterval => 1.0 / effectiveFireRate;

  /// Damage per shot including the run-wide Targeting Array bonus. Weapons
  /// pass this (not [damage]) to what they fire.
  double get shotDamage => damage * (1 + game.weaponDamageBonus) * game.shipClass.gunDamage;

  String get displayName;
  bool get isUpgradeable => true;
  String get nextUpgradeDescription => 'Damage +${upgradePercent()}%';

  /// Highest upgrade level on the current track (evolving starts a new one).
  int get maxUpgradeLevel => evolved ? Balance.evolvedMaxLevel : Balance.maxWeaponLevel;

  /// Whether another upgrade card can be offered for this weapon.
  bool get canUpgrade => isUpgradeable && upgradeLevel < maxUpgradeLevel;

  /// The percentage the next upgrade adds (for card text).
  int upgradePercent() =>
      ((Balance.upgradeDamageStep(upgradeLevel + 1, evolved: evolved) - 1) * 100).round();

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
    damage *= Balance.upgradeDamageStep(upgradeLevel, evolved: evolved);
  }

  /// Fuse into the enhanced form: a fresh upgrade track. Level back to 1,
  /// damage and fire rate back to the base weapon's (the old levels and card
  /// rarity bonuses are traded in) times [Balance.evolvedDamageMult].
  void evolve(String name) {
    evolved = true;
    evolvedName = name;
    upgradeLevel = 1;
    damage = baseDamage * Balance.evolvedDamageMult;
    fireRate = baseFireRate;
  }
}
