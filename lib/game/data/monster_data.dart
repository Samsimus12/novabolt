class MonsterStats {
  final double maxHp;
  final double speed;
  final double contactDamagePerSecond;
  final double size;
  final int xpValue;
  final int chargeValue;
  final double shieldDropChance;
  final double hpScaleRate;
  final double speedScaleRate;
  final double speedScaleCap;

  const MonsterStats({
    required this.maxHp,
    required this.speed,
    required this.contactDamagePerSecond,
    required this.size,
    required this.xpValue,
    this.chargeValue = 8,
    this.shieldDropChance = 0.15,
    this.hpScaleRate = 0.3,
    this.speedScaleRate = 0.1,
    this.speedScaleCap = 3.0,
  });

  MonsterStats scaled(int playerLevel) {
    final hpMult = 1.0 + (playerLevel - 1) * hpScaleRate;
    final speedMult = (1.0 + (playerLevel - 1) * speedScaleRate).clamp(1.0, speedScaleCap);
    return MonsterStats(
      maxHp: maxHp * hpMult,
      speed: speed * speedMult,
      contactDamagePerSecond: contactDamagePerSecond,
      size: size,
      xpValue: xpValue,
      chargeValue: chargeValue,
      shieldDropChance: shieldDropChance,
      hpScaleRate: hpScaleRate,
      speedScaleRate: speedScaleRate,
      speedScaleCap: speedScaleCap,
    );
  }
}

const gruntStats = MonsterStats(
  maxHp: 30,
  speed: 80,
  contactDamagePerSecond: 15,
  size: 36,
  xpValue: 10,
  chargeValue: 8,
  shieldDropChance: 0.075,
);

const tankStats = MonsterStats(
  maxHp: 160,
  speed: 45,
  contactDamagePerSecond: 25,
  size: 60,
  xpValue: 30,
  chargeValue: 25,
  shieldDropChance: 0.20,
  hpScaleRate: 0.4,
  speedScaleRate: 0.05,
  speedScaleCap: 2.0,
);

const speederStats = MonsterStats(
  maxHp: 18,
  speed: 210,
  contactDamagePerSecond: 10,
  size: 22,
  xpValue: 5,
  chargeValue: 5,
  shieldDropChance: 0.05,
  hpScaleRate: 0.15,
  speedScaleRate: 0.12,
  speedScaleCap: 2.5,
);
