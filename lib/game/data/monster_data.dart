class MonsterStats {
  final double maxHp;
  final double speed;
  final double contactDamagePerSecond;
  final double size;
  final int xpValue;
  final int chargeValue;
  final double shieldDropChance;
  final double healthDropChance;
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
    this.healthDropChance = 0.10,
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
      healthDropChance: healthDropChance,
      hpScaleRate: hpScaleRate,
      speedScaleRate: speedScaleRate,
      speedScaleCap: speedScaleCap,
    );
  }
}

const gruntStats = MonsterStats(
  maxHp: 30,
  speed: 80,
  contactDamagePerSecond: 10,
  size: 36,
  xpValue: 10,
  chargeValue: 5,
  shieldDropChance: 0.053,
  healthDropChance: 0.049,
);

const tankStats = MonsterStats(
  maxHp: 160,
  speed: 45,
  contactDamagePerSecond: 18,
  size: 60,
  xpValue: 30,
  chargeValue: 15,
  shieldDropChance: 0.14,
  healthDropChance: 0.1225,
  hpScaleRate: 0.4,
  speedScaleRate: 0.05,
  speedScaleCap: 2.0,
);

const speederStats = MonsterStats(
  maxHp: 18,
  speed: 210,
  contactDamagePerSecond: 7,
  size: 22,
  xpValue: 5,
  chargeValue: 3,
  shieldDropChance: 0.035,
  healthDropChance: 0.037,
  hpScaleRate: 0.15,
  speedScaleRate: 0.12,
  speedScaleCap: 2.5,
);

const casterStats = MonsterStats(
  maxHp: 40,
  speed: 55,
  contactDamagePerSecond: 6,
  size: 32,
  xpValue: 20,
  chargeValue: 7,
  shieldDropChance: 0.06,
  healthDropChance: 0.056,
  hpScaleRate: 0.2,
  speedScaleRate: 0.08,
  speedScaleCap: 2.0,
);

const bossStats = MonsterStats(
  maxHp: 800,
  speed: 30,
  contactDamagePerSecond: 28,
  size: 100,
  xpValue: 0,
  chargeValue: 30,
  shieldDropChance: 0.0,
  hpScaleRate: 0.5,
  speedScaleRate: 0.03,
  speedScaleCap: 1.5,
);

const tyrantStats = MonsterStats(
  maxHp: 1600,
  speed: 45,
  contactDamagePerSecond: 40,
  size: 120,
  xpValue: 0,
  chargeValue: 50,
  shieldDropChance: 0.0,
  hpScaleRate: 0.5,
  speedScaleRate: 0.03,
  speedScaleCap: 1.8,
);
