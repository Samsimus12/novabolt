class WeaponStats {
  final double damage;
  final double fireRate; // shots per second
  final double projectileSpeed;
  final double projectileSize;

  const WeaponStats({
    required this.damage,
    required this.fireRate,
    required this.projectileSpeed,
    required this.projectileSize,
  });

  double get fireInterval => 1.0 / fireRate;
}

const magicBoltStats = WeaponStats(
  damage: 15,
  fireRate: 2.0,
  projectileSpeed: 300,
  projectileSize: 10,
);
