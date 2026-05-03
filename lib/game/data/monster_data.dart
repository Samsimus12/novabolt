class MonsterStats {
  final double maxHp;
  final double speed;
  final double contactDamagePerSecond;
  final double size;
  final int xpValue;

  const MonsterStats({
    required this.maxHp,
    required this.speed,
    required this.contactDamagePerSecond,
    required this.size,
    required this.xpValue,
  });

  MonsterStats scaled(int playerLevel) {
    final s = 1.0 + (playerLevel - 1) * 0.3;
    return MonsterStats(
      maxHp: maxHp * s,
      speed: (speed * (1.0 + (playerLevel - 1) * 0.1)).clamp(speed, speed * 3),
      contactDamagePerSecond: contactDamagePerSecond,
      size: size,
      xpValue: xpValue,
    );
  }
}

const gruntStats = MonsterStats(
  maxHp: 30,
  speed: 80,
  contactDamagePerSecond: 15,
  size: 36,
  xpValue: 10,
);
