/// Every tuning number for the run-level systems, in one place.
///
/// Enemy and boss base stats stay in `monster_data.dart` (one row per
/// enemy); the global multipliers below scale all of them at once, so a
/// quick "everything is 10% too tanky" fix is one edit here.
///
/// Targets these numbers were set against (see CLAUDE.md "Balance"):
///   • a new player usually dies around boss 1–2; a practised one reaches 4–5
///   • a boss fight lasts ~45–90s
///   • a player with no Hangar upgrades can still win boss 1
///   • no single card, relic or Nova should feel mandatory
abstract final class Balance {
  // ── Global enemy knobs ────────────────────────────────────────────────────
  static const double enemyHpMultiplier = 1.0;
  static const double enemyDamageMultiplier = 1.0;
  static const double bossHpMultiplier = 1.0;

  // ── Dash ──────────────────────────────────────────────────────────────────
  /// A dash covers dashSpeed × dashDuration ≈ 115 px.
  static const double dashDuration = 0.16;
  static const double dashSpeed = 720;
  static const double dashCooldown = 2.2;
  /// Invulnerability lasts the dash plus this much after it.
  static const double dashGrace = 0.12;

  // ── Revive ────────────────────────────────────────────────────────────────
  /// After any revive (ad or Hangar): seconds of invulnerability. A
  /// shockwave (ReviveBlast) also clears every enemy bullet and hazard.
  static const double reviveGrace = 2.0;

  // ── Player damage ─────────────────────────────────────────────────────────
  static const double baseCritChance = 0.05;
  static const double baseCritMultiplier = 2.0;

  /// Cap on all *stacking* damage bonuses combined (Hangar firepower, Glass
  /// cannon, Bloodlust, Shadow Veil, Cryo shatter). Crits and per-weapon
  /// upgrade levels are separate and not capped.
  static const double maxDamageBonus = 2.0;

  // ── Combo ─────────────────────────────────────────────────────────────────
  static const double comboWindow = 2.0;
  static const int comboCap = 50;
  static const double comboXpPerKill = 0.02; // up to 2x XP at the cap
  static const double comboChargePerKill = 0.01; // up to 1.5x Nova charge

  // ── Overdrive (reach a [overdriveCombo] combo) ───────────────────────────
  // Fires once per chain: the combo has to break before it can trigger again.
  static const int overdriveCombo = 50;
  static const double overdriveDuration = 8;
  static const double overdriveXp = 2.0; // on top of the combo bonus
  static const double overdriveFireRate = 0.25; // +25% fire rate, every weapon
  static const double overdriveCharge = 1.5; // Nova charge from kills

  // ── Grazing (an enemy bullet passes close without hitting) ───────────────
  /// Extra px beyond the hit distance that still counts as a graze.
  static const double grazeMargin = 18;
  static const double grazeCharge = 1.5; // Nova charge per graze (of 100)
  static const double grazeComboTime = 0.4; // tops up the combo timer
  static const int grazesPerSecond = 4; // reward cap (max ~6% Nova/s), so bullet walls aren't farmed

  // ── Nova ──────────────────────────────────────────────────────────────────
  // Base Nova lasts 100 / 20 = 5 s. Nova card bonuses and caps: see "Stat cards" below.

  // Per-attack damage (before Nova Overload and the damage bonus). The
  // reference is the Laser: 120 dps along a line. Area attacks deal less per
  // target; single-target ones about the Laser's dps against a boss.
  static const double laserDps = 120;
  static const double orbitalStrikeDamage = 40, orbitalStrikeInterval = 0.3;
  static const double voidWellDps = 60;
  static const double blackHoleDps = 65;
  static const double shockwaveDamage = 35, shockwaveInterval = 0.6;
  static const double bloodBarrageBoltDamage = 9;
  static const double chainDamage = 20, chainInterval = 0.3, chainFirstHopBonus = 1.5;
  static const int chainHops = 5;
  static const double shadowVeilDamageBonus = 1.35, shadowVeilSlow = 0.3;
  static const double sunBeamDps = 55;
  static const double missileDamage = 16, missileInterval = 0.15;
  static const double eventHorizonDamage = 32, eventHorizonInterval = 0.8;

  // ── Stat cards (Common, Rare, Epic, Legendary), additive, capped ──────────
  // Every card adds a flat percentage to a run-wide bonus; bonuses add (two
  // +15% cards = +30%), apply to every weapon including later ones, and stop
  // being offered once the cap is reached.
  static const fireRateTiers = [10, 15, 20, 30];
  static const maxFireRateBonus = 100;
  static const weaponDamageTiers = [10, 15, 20, 30]; // Targeting Array: never Common
  static const maxWeaponDamageBonus = 100;
  static const novaChargeTiers = [15, 20, 30, 40];
  static const maxNovaChargeBonus = 150;
  static const novaDurationTiers = [15, 20, 30, 40];
  static const maxNovaDurationBonus = 120;
  static const novaDamageTiers = [15, 25, 35, 50];
  static const maxNovaDamageBonus = 200;

  // ── Upgrade cards ─────────────────────────────────────────────────────────
  /// Rarity multiplier for weapon-upgrade cards' bonus damage only; stat
  /// cards use the per-rarity tables above.
  static const double rareMultiplier = 1.4;
  static const double epicMultiplier = 1.8;
  static const double legendaryMultiplier = 2.3;
  static const double legendaryOdds = 0.025, epicOdds = 0.075, rareOdds = 0.20;
  static const double bossRarityShift = 2.0; // boss picks roll ~2x better
  static const int freeRerollsPerRun = 1;

  // ── Relics ────────────────────────────────────────────────────────────────
  static const double glassCannonDamage = 1.3, glassCannonHull = 0.75;
  static const double bloodlustPer100Kills = 0.04, bloodlustCap = 0.40;
  static const double luckyStarCrit = 0.08, luckyStarCritMultiplier = 2.25;
  static const double cryoShatterBonus = 1.3;
  static const int vampireKillsPerRepair = 8;
  static const double vampireRepair = 2;
  static const int scrapShieldKills = 25;
  static const double scrapShieldAmount = 15;
  static const double midasCoins = 1.5;

  // ── Hangar (per level) ────────────────────────────────────────────────────
  static const double hangarHull = 10;
  static const double hangarArmor = 0.03; // damage taken −3%/level
  static const double hangarFirepower = 0.04; // +4%/level
  static const double hangarCrit = 0.015;
  static const double hangarNovaStart = 0.15;
  static const double hangarSalvage = 0.10;

  // ── Coins ─────────────────────────────────────────────────────────────────
  static const int coinsPerLevel = 10;
  static const int coinsPerBossStep = 50; // boss n pays 50·n
  static const int coinsPerFlawless = 100;
  static const int maxComboCoins = 200;
}
