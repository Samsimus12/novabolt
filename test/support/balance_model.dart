// A small analytic model of the player's damage against bosses, used by
// boss_ttk_test.dart to print (and sanity-check) time-to-kill per boss.
//
// It is NOT the game: it is a deterministic, expected-value walk through a
// run (pick by pick) that applies the same formulas the game uses
// (Weapon.applyUpgrade steps, Balance caps, Balance.evolve*, monster_data
// scaling), so a tuning change shows up here before it is play-tested.
//
// Assumptions are listed in [Profile] and in the comments below.
import 'dart:math' as math;

import 'package:novabolt/game/data/balance.dart';
import 'package:novabolt/game/data/monster_data.dart';

/// The rules being modelled. [Rules.legacy] is the game before the Nov 2026
/// rebalance; [Rules.current] reads the real production numbers.
class Rules {
  final String name;

  /// Damage multiplier applied when a weapon is upgraded TO [level].
  final double Function(int level, bool evolved) damageStep;

  /// Fire-rate multiplier of the Pulse Cannon's upgrade TO [level].
  final double Function(int level, bool evolved) rateStep;
  final int Function(bool evolved) maxLevel;

  /// Evolving: damage multiplier relative to the weapon's base damage
  /// (null = keeps whatever levels it had, legacy) and whether levels reset.
  final double? evolvedBaseMult;
  final bool resetsLevel;

  /// Boss (base HP, hp scale per level) for bosses 1..10.
  final List<(double, double)> bosses;
  final double bossHpMult;

  const Rules({
    required this.name,
    required this.damageStep,
    required this.rateStep,
    required this.maxLevel,
    required this.evolvedBaseMult,
    required this.resetsLevel,
    required this.bosses,
    required this.bossHpMult,
  });

  static final legacy = Rules(
    name: 'before',
    damageStep: (_, _) => 1.3,
    rateStep: (_, _) => 1.2,
    maxLevel: (_) => 10,
    evolvedBaseMult: null,
    resetsLevel: false,
    bosses: const [
      (800, 0.5), (1600, 0.5), (2400, 0.45), (3200, 0.45), (2000, 0.4),
      (4000, 0.5), (2800, 0.45), (3600, 0.5), (4800, 0.5), (6000, 0.55),
    ],
    bossHpMult: 1.0,
  );

  static Rules current({String name = 'after'}) => Rules(
        name: name,
        damageStep: (l, e) => Balance.upgradeDamageStep(l, evolved: e),
        rateStep: (l, e) => Balance.upgradeRateStep(l, evolved: e),
        maxLevel: (e) => e ? Balance.evolvedMaxLevel : Balance.maxWeaponLevel,
        evolvedBaseMult: Balance.evolvedDamageMult,
        resetsLevel: true,
        bosses: [
          for (final s in bossStatsByIndex) (s.maxHp, s.hpScaleRate),
        ],
        bossHpMult: Balance.bossHpMultiplier,
      );

  /// HP of boss [n] (1-based), met at level 10n.
  double bossHp(int n) {
    final (base, rate) = bosses[n - 1];
    return base * (1 + (10 * n - 1) * rate) * bossHpMult * Balance.enemyHpMultiplier;
  }
}

/// A player archetype. Everything is an expected value.
class Profile {
  final String name;

  /// Share of normal picks that go to the weapon category.
  final double weaponShare;

  /// Of those, share spent on Overcharge / Targeting Array cards.
  final double statShare;

  /// Weapons owned (including the Laser) after N weapon picks.
  final int Function(int weaponPicks) ownedAt;

  /// true: always upgrade the best weapon first; false: spread evenly.
  final bool focus;

  /// Evolves as soon as a recipe is met (else only after [evolveAfterPicks]).
  final int evolveAfterPicks;

  /// Hangar levels (firepower, crit).
  final int hangarFirepower, hangarCrit;

  /// Relics by boss N: which damage relics are held after beating boss N-1.
  final bool Function(int n) glassCannon, bloodlust, luckyStar;

  /// Fraction of a boss fight the weapons are actually hitting it.
  final double uptime;

  /// Nova: seconds between Novas and bonuses taken (fraction of nova picks).
  final double novaCycle;
  final double novaCardsShare;

  const Profile({
    required this.name,
    required this.weaponShare,
    required this.statShare,
    required this.ownedAt,
    required this.focus,
    required this.evolveAfterPicks,
    required this.hangarFirepower,
    required this.hangarCrit,
    required this.glassCannon,
    required this.bloodlust,
    required this.luckyStar,
    required this.uptime,
    required this.novaCycle,
    required this.novaCardsShare,
  });

  /// A decent player: a mix of weapon and utility picks, a few Hangar levels,
  /// picks up relics as they come, spreads upgrades around.
  static final typical = Profile(
    name: 'typical',
    weaponShare: 0.55,
    statShare: 0.20,
    ownedAt: (w) => w < 2 ? 1 : w < 5 ? 2 : w < 9 ? 3 : w < 15 ? 4 : w < 25 ? 5 : 6,
    focus: false,
    evolveAfterPicks: 14,
    hangarFirepower: 2,
    hangarCrit: 2,
    glassCannon: (n) => n >= 4,
    bloodlust: (n) => n >= 6,
    luckyStar: (n) => false,
    uptime: 0.55,
    novaCycle: 40,
    novaCardsShare: 0.15,
  );

  /// A min-maxer: nearly every pick is damage, fully-upgraded Hangar, takes
  /// every damage relic, evolves at once.
  static final strong = Profile(
    name: 'strong',
    weaponShare: 0.80,
    statShare: 0.30,
    ownedAt: (w) => w < 1 ? 1 : w < 3 ? 2 : w < 5 ? 3 : w < 8 ? 4 : w < 12 ? 5 : 6,
    focus: true,
    evolveAfterPicks: 0,
    hangarFirepower: 5,
    hangarCrit: 5,
    glassCannon: (n) => n >= 2,
    bloodlust: (n) => n >= 3,
    luckyStar: (n) => n >= 4,
    uptime: 0.72,
    novaCycle: 25,
    novaCardsShare: 0.25,
  );
}

class _W {
  final String id;
  final double dmg, rate, hits;
  int level = 1;
  bool evolved = false;
  double dmgMult = 1, rateMult = 1; // level growth
  double boostDmg = 1, boostRate = 1, boostHits = 1;
  _W(this.id, this.dmg, this.rate, this.hits);

  // Per-boss-fight effective damage per second before global multipliers.
  double get dps => dmg * dmgMult * boostDmg * rate * rateMult * boostRate * hits * boostHits;
  bool get upgradeable => id != 'rocket';
}

// Fight-relevant hits per shot against a big target, and how much of the
// fight the weapon connects (the Force Field only works at point-blank).
_W _make(String id) => switch (id) {
      'laser' => _W(id, 15, 2.0, 1),
      'spread' => _W(id, 10, 1.5, 2.2), // 3 bolts, ~2.2 land on a boss
      'pulse' => _W(id, 9, 4.0, 1),
      'homing' => _W(id, 12, 1.5, 1),
      'field' => _W(id, 8, 1.0, 0.4), // dmg/sec while in contact ~40% of the fight
      'frost' => _W(id, 10, 1.2, 1),
      _ => _W(id, 25, 0.8, 1),
    };

const _order = ['laser', 'spread', 'pulse', 'homing', 'field', 'frost', 'rocket'];

class BuildResult {
  final double dps; // effective, after uptime
  final double rawDps;
  final int level;
  final int evolved;
  final double globalMult;
  BuildResult(this.dps, this.rawDps, this.level, this.evolved, this.globalMult);
}

/// Normal picks the player has made before boss [n] (1-based):
/// 9 level-ups per boss (10% / 20-45% of them give 2 picks: ~1.2 avg) plus
/// two ordinary picks from each earlier boss reward (the first is a relic).
int picksBefore(int n) => (1.2 * 9 * n + 2 * (n - 1)).round();

BuildResult buildAt(Profile p, Rules r, int n) {
  final total = picksBefore(n);
  final ws = <_W>[_make('laser')];
  var fireBonus = 0.0, tgtBonus = 0.0;
  var statTick = 0.0; // fractional accumulator for stat picks
  var evolutionsDone = 0;
  var cumulativeWeaponPicks = 0;
  var tgtTaken = false, overTaken = false;

  // Rarity bonus on a weapon upgrade card: expected extra damage multiplier
  // (rare +12%, epic +24%, legendary +39%), odds from Balance.
  double rarityBonus({bool boss = false}) {
    final s = boss ? Balance.bossRarityShift : 1.0;
    final lg = Balance.legendaryOdds * s, ep = Balance.epicOdds * s, ra = Balance.rareOdds * s;
    double pct(double m) => ((m - 1) * 30).round() / 100;
    return 1 +
        lg * pct(Balance.legendaryMultiplier) +
        ep * pct(Balance.epicMultiplier) +
        ra * pct(Balance.rareMultiplier);
  }

  final rb = rarityBonus();

  double avgTier(List<int> tiers, {int min = 0}) {
    final odds = [
      1 - Balance.legendaryOdds - Balance.epicOdds - Balance.rareOdds,
      Balance.rareOdds,
      Balance.epicOdds,
      Balance.legendaryOdds,
    ];
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      s += odds[i] * tiers[math.max(i, min)];
    }
    return s / 100;
  }

  bool recipe(String id) {
    _W? f(String x) => ws.where((w) => w.id == x).firstOrNull;
    final w = f(id);
    if (w == null || w.evolved) return false;
    switch (id) {
      case 'laser':
        return w.level >= 5 && tgtTaken;
      case 'spread':
        return w.level >= 5 && f('pulse') != null;
      case 'homing':
        return w.level >= 5 && overTaken;
      case 'field':
        return w.level >= 5 && f('frost') != null;
      case 'rocket':
        return f('spread') != null && f('spread')!.level >= 5;
    }
    return false;
  }

  void evolve(_W w) {
    w.evolved = true;
    if (r.resetsLevel) {
      w.level = 1;
      w.dmgMult = r.evolvedBaseMult!;
      w.rateMult = 1;
    }
    switch (w.id) {
      case 'laser':
        w.boostDmg = 1.3;
      case 'spread':
        w.boostRate = 1.5;
        w.boostHits = 3.5 / 2.2;
      case 'homing':
        w.boostHits = 3;
      case 'field':
        w.boostDmg = 1.2;
      case 'rocket':
        w.boostDmg = 1.2;
        w.boostHits = 2;
    }
    evolutionsDone++;
  }

  final wp = (total * p.weaponShare).round();
  for (var i = 0; i < wp; i++) {
    cumulativeWeaponPicks++;

    // Evolution (offered whenever a recipe is met; the player takes it).
    if (cumulativeWeaponPicks > p.evolveAfterPicks) {
      final cand = _order.map((id) => ws.where((w) => w.id == id).firstOrNull).whereType<_W>().where((w) => recipe(w.id)).firstOrNull;
      if (cand != null) {
        evolve(cand);
        continue;
      }
    }

    // Stat card: Targeting Array (never common) / Overcharge, whichever is behind.
    statTick += p.statShare;
    if (statTick >= 1) {
      statTick -= 1;
      final tgtCap = Balance.maxWeaponDamageBonus / 100, fireCap = Balance.maxFireRateBonus / 100;
      final wantTgt = tgtBonus < tgtCap && (!tgtTaken || tgtBonus <= fireBonus || fireBonus >= fireCap);
      if (wantTgt) {
        tgtBonus = math.min(tgtCap, tgtBonus + avgTier(Balance.weaponDamageTiers, min: 1));
        tgtTaken = true;
        continue;
      } else if (fireBonus < fireCap) {
        fireBonus = math.min(fireCap, fireBonus + avgTier(Balance.fireRateTiers));
        overTaken = true;
        continue;
      }
    }

    // New weapon?
    if (ws.length < p.ownedAt(cumulativeWeaponPicks) && ws.length < _order.length) {
      ws.add(_make(_order[ws.length]));
      continue;
    }

    // Upgrade.
    final cands = ws.where((w) => w.upgradeable && w.level < r.maxLevel(w.evolved)).toList();
    if (cands.isEmpty) continue;
    _W pick;
    if (p.focus) {
      cands.sort((a, b) => b.dps.compareTo(a.dps));
      pick = cands.first;
    } else {
      cands.sort((a, b) => a.level.compareTo(b.level));
      pick = cands.first;
    }
    pick.level++;
    if (pick.id == 'pulse') {
      pick.rateMult *= r.rateStep(pick.level, pick.evolved);
      pick.dmgMult *= rb;
    } else {
      pick.dmgMult *= r.damageStep(pick.level, pick.evolved) * rb;
    }
  }

  // ── Global multipliers ──
  final hangar = 1 + Balance.hangarFirepower * p.hangarFirepower;
  var out = hangar;
  if (p.glassCannon(n)) out *= Balance.glassCannonDamage;
  if (p.bloodlust(n)) {
    final kills = 330 * n;
    out *= 1 + math.min(Balance.bloodlustCap, (kills ~/ 100) * Balance.bloodlustPer100Kills);
  }
  out = math.min(out, Balance.maxDamageBonus);
  var crit = Balance.baseCritChance + Balance.hangarCrit * p.hangarCrit;
  var critMult = Balance.baseCritMultiplier;
  if (p.luckyStar(n)) {
    crit += Balance.luckyStarCrit;
    critMult = Balance.luckyStarCritMultiplier;
  }
  final critFactor = 1 + crit * (critMult - 1);

  final fireMult = 1 + fireBonus;
  final dmgMult = 1 + tgtBonus;
  final raw = ws.fold<double>(0, (s, w) => s + w.dps) * fireMult * dmgMult * out * critFactor;

  // Nova (laser baseline 120 dps) with the share of nova cards taken.
  final novaPicks = total * (1 - p.weaponShare) * p.novaCardsShare;
  final novaDmgBonus = math.min(Balance.maxNovaDamageBonus / 100, novaPicks / 3 * avgTier(Balance.novaDamageTiers));
  final novaDurBonus = math.min(Balance.maxNovaDurationBonus / 100, novaPicks / 3 * avgTier(Balance.novaDurationTiers));
  final novaDps = Balance.laserDps * (1 + novaDmgBonus) * 5 * (1 + novaDurBonus) / p.novaCycle * p.uptime;

  final eff = raw * p.uptime + novaDps;
  return BuildResult(eff, raw, total, evolutionsDone, out);
}

/// Seconds to kill boss [n], including ~1.5s of stagger per stage change
/// (taken as 2 changes on average).
double ttk(Profile p, Rules r, int n) {
  final b = buildAt(p, r, n);
  return r.bossHp(n) / b.dps + 3;
}
