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
  final double damageScaleRate;

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
    this.damageScaleRate = 0.05,
  });

  MonsterStats scaled(int playerLevel) {
    final hpMult = 1.0 + (playerLevel - 1) * hpScaleRate;
    final speedMult = (1.0 + (playerLevel - 1) * speedScaleRate).clamp(1.0, speedScaleCap);
    final damageMult = 1.0 + (playerLevel - 1) * damageScaleRate;
    return MonsterStats(
      maxHp: maxHp * hpMult,
      speed: speed * speedMult,
      contactDamagePerSecond: contactDamagePerSecond * damageMult,
      size: size,
      xpValue: xpValue,
      chargeValue: chargeValue,
      shieldDropChance: shieldDropChance,
      healthDropChance: healthDropChance,
      hpScaleRate: hpScaleRate,
      speedScaleRate: speedScaleRate,
      speedScaleCap: speedScaleCap,
      damageScaleRate: damageScaleRate,
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
  speedScaleRate: 0.07,
  speedScaleCap: 1.8,
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

// Boss 3 — Nebula Leviathan
const leviathanStats = MonsterStats(
  maxHp: 2400,
  speed: 35,
  contactDamagePerSecond: 32,
  size: 110,
  xpValue: 0,
  chargeValue: 60,
  shieldDropChance: 0.0,
  hpScaleRate: 0.45,
  speedScaleRate: 0.025,
  speedScaleCap: 1.6,
);

// Boss 4 — Blood Colossus
const colossusStats = MonsterStats(
  maxHp: 3200,
  speed: 25,
  contactDamagePerSecond: 45,
  size: 130,
  xpValue: 0,
  chargeValue: 70,
  shieldDropChance: 0.0,
  hpScaleRate: 0.45,
  speedScaleRate: 0.02,
  speedScaleCap: 1.4,
);

// Boss 5 — Storm Phantom
const phantomStats = MonsterStats(
  maxHp: 2000,
  speed: 65,
  contactDamagePerSecond: 28,
  size: 90,
  xpValue: 0,
  chargeValue: 55,
  shieldDropChance: 0.0,
  hpScaleRate: 0.4,
  speedScaleRate: 0.035,
  speedScaleCap: 2.0,
);

// Boss 6 — Cosmic Behemoth
const behemothStats = MonsterStats(
  maxHp: 4000,
  speed: 20,
  contactDamagePerSecond: 50,
  size: 140,
  xpValue: 0,
  chargeValue: 80,
  shieldDropChance: 0.0,
  hpScaleRate: 0.5,
  speedScaleRate: 0.015,
  speedScaleCap: 1.3,
);

// Boss 7 — Shadow Reaper
const reaperStats = MonsterStats(
  maxHp: 2800,
  speed: 55,
  contactDamagePerSecond: 36,
  size: 100,
  xpValue: 0,
  chargeValue: 65,
  shieldDropChance: 0.0,
  hpScaleRate: 0.45,
  speedScaleRate: 0.03,
  speedScaleCap: 1.8,
);

// Boss 8 — Solar Titan (note: titanStats name is taken by Void Tyrant)
const solarTitanStats = MonsterStats(
  maxHp: 3600,
  speed: 30,
  contactDamagePerSecond: 42,
  size: 120,
  xpValue: 0,
  chargeValue: 75,
  shieldDropChance: 0.0,
  hpScaleRate: 0.5,
  speedScaleRate: 0.02,
  speedScaleCap: 1.5,
);

// Boss 9 — Void Emperor
const emperorStats = MonsterStats(
  maxHp: 4800,
  speed: 40,
  contactDamagePerSecond: 48,
  size: 115,
  xpValue: 0,
  chargeValue: 85,
  shieldDropChance: 0.0,
  hpScaleRate: 0.5,
  speedScaleRate: 0.025,
  speedScaleCap: 1.6,
);

// Boss 10 — The Singularity
const singularityStats = MonsterStats(
  maxHp: 6000,
  speed: 15,
  contactDamagePerSecond: 60,
  size: 150,
  xpValue: 0,
  chargeValue: 100,
  shieldDropChance: 0.0,
  hpScaleRate: 0.55,
  speedScaleRate: 0.01,
  speedScaleCap: 1.2,
);
