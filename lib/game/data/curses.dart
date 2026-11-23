import 'dart:math' as math;
import 'dart:ui' show Color;

import '../novabolt_game.dart';
import 'balance.dart';
import 'upgrade_cards.dart';

/// A risky level-up deal: a big boost with a catch that lasts the whole run.
///
/// Every effect goes through a run setting that the save already stores
/// (damage, fire rate, crit, enemy speed, spawn rate, damage taken, coins,
/// hull, speed, Nova charge), and the curse's title is kept in
/// [NovaboltGame.takenBuffs], so a curse survives a save and resume without
/// any extra storage and is never offered twice.
enum Curse {
  bloodPact('Blood Pact', '+35% damage', 'Enemies hit 30% harder'),
  recklessFire('Reckless Fire', '+30% fire rate', 'Enemies move 20% faster'),
  bountyHunter('Bounty Hunter', '+75% NOVA coins this run', 'Enemies arrive 30% faster'),
  glassHull('Glass Hull', '+20% critical chance', 'Max hull −30%'),
  novaAddict('Nova Addict', 'Nova charges 60% faster', 'Max hull −20%'),
  heavyPlating('Heavy Plating', '+60 max hull, fully repaired', 'Move speed −15%'),
  gambler('Gambler', 'Upgrade cards roll rarer for the rest of the run', 'Enemies hit 20% harder');

  final String title;
  final String boon;
  final String cost;
  const Curse(this.title, this.boon, this.cost);

  bool takenIn(NovaboltGame g) => g.takenBuffs.contains(title);

  /// Not yet taken, and not pointless (Gambler does nothing on a lucky run).
  bool allowedIn(NovaboltGame g) => !takenIn(g) && !(this == gambler && g.luckyCards);

  void apply(NovaboltGame g) {
    final p = g.player;
    void cutHull(double keep) {
      p.maxHp = math.max(1, p.maxHp * keep);
      p.currentHp = math.min(p.currentHp, p.maxHp);
    }

    switch (this) {
      case bloodPact:
        g.damageMultiplier *= 1.35;
        g.damageTakenMultiplier *= 1.30;
      case recklessFire:
        g.fireRateBonus += 0.30;
        g.enemySpeedMultiplier *= 1.20;
      case bountyHunter:
        g.runCoinMultiplier *= 1.75;
        g.spawnIntervalMultiplier /= 1.30;
      case glassHull:
        g.critChance += 0.20;
        cutHull(0.70);
      case novaAddict:
        g.superchargeSystem.chargeBase *= 1.60;
        cutHull(0.80);
      case heavyPlating:
        p.maxHp += 60;
        p.currentHp = p.maxHp;
        p.moveSpeed *= 0.85;
      case gambler:
        g.luckyCards = true;
        g.damageTakenMultiplier *= 1.20;
    }
  }

  static int countIn(NovaboltGame g) => values.where((c) => c.takenIn(g)).length;
}

class CurseCard extends UpgradeCard {
  final Curse curse;
  CurseCard(this.curse);

  @override
  String get title => curse.title;
  @override
  String get description => '${curse.boon}. The catch: ${curse.cost.toLowerCase()}.';
  @override
  CardGlyph get glyph => CardGlyph.curse;
  @override
  UpgradeCategory get category => UpgradeCategory.relic;

  @override
  void apply(NovaboltGame game) {
    game.takenBuffs.add(curse.title);
    curse.apply(game);
    game.announce('Cursed: ${curse.title}', color: const Color(0xFFFF4766));
  }
}

/// Whether this level-up offers a curse. Never on boss rewards or relic
/// chests, never before [Balance.curseMinLevel], at most
/// [Balance.maxCursesPerRun] a run.
bool shouldOfferCurse({
  required int level,
  required bool bossReward,
  required int cursesTaken,
  required double roll,
}) =>
    CurseRules.forceOffer ||
    (!bossReward &&
        level >= Balance.curseMinLevel &&
        cursesTaken < Balance.maxCursesPerRun &&
        roll < Balance.curseChance);

class CurseRules {
  /// Dev harness only (`CURSE=true`): every level-up offers a curse.
  static bool forceOffer = false;
}

/// Swaps one ordinary pick for a curse when [shouldOfferCurse] says so.
/// An evolution on offer is never replaced.
void maybeOfferCurse(NovaboltGame game, List<UpgradeCard> picks, math.Random rng) {
  if (!shouldOfferCurse(
    level: game.xpSystem.currentLevel,
    bossReward: game.isBossReward,
    cursesTaken: Curse.countIn(game),
    roll: rng.nextDouble(),
  )) {
    return;
  }
  final options = Curse.values.where((c) => c.allowedIn(game)).toList();
  if (options.isEmpty) return;
  final replaceable = [
    for (var i = 0; i < picks.length; i++)
      if (picks[i] is! EvolutionCard) i,
  ];
  final card = CurseCard(options[rng.nextInt(options.length)]);
  if (replaceable.isEmpty) {
    picks.add(card);
  } else {
    picks[replaceable[rng.nextInt(replaceable.length)]] = card;
  }
}
