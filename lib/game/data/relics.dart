import 'balance.dart';

/// Run-long passive effects. One is chosen (from three) after each boss kill.
/// The effects are implemented where they apply: NovaboltGame's damage/kill
/// hooks, Projectile (ricochet) and Player (second wind). Descriptions are
/// built from [Balance] so the text always matches the numbers.
enum Relic {
  ricochet('Ricochet rounds'),
  cryoShatter('Cryo shatter'),
  overkill('Overkill'),
  bloodlust('Bloodlust'),
  vampire('Vampiric hull'),
  luckyStar('Lucky star'),
  glassCannon('Glass cannon'),
  magnetCore('Magnet core'),
  secondWind('Second wind'),
  midas('Midas engine'),
  scrapShield('Scrap shield');

  final String title;
  const Relic(this.title);

  static String _pct(double multiplierOrFraction, {bool isMultiplier = true}) =>
      '${((isMultiplier ? multiplierOrFraction - 1 : multiplierOrFraction) * 100).round()}%';

  String get description => switch (this) {
        Relic.ricochet => 'Your shots bounce once to another nearby enemy',
        Relic.cryoShatter =>
          'Slowed enemies take +${_pct(Balance.cryoShatterBonus)} damage and chill their neighbours when they die',
        Relic.overkill => 'Damage past a kill carries over to the nearest enemy',
        Relic.bloodlust =>
          '+${_pct(Balance.bloodlustPer100Kills, isMultiplier: false)} damage for every 100 kills this run (up to +${_pct(Balance.bloodlustCap, isMultiplier: false)})',
        Relic.vampire => 'Repair ${Balance.vampireRepair.round()} hull for every ${Balance.vampireKillsPerRepair} kills',
        Relic.luckyStar =>
          '+${_pct(Balance.luckyStarCrit, isMultiplier: false)} critical chance; crits deal ${Balance.luckyStarCritMultiplier}x',
        Relic.glassCannon =>
          '+${_pct(Balance.glassCannonDamage)} damage, but −${_pct(1 - Balance.glassCannonHull, isMultiplier: false)} max hull',
        Relic.magnetCore => 'Pickups fly to you from anywhere on screen',
        Relic.secondWind => 'Extra life: once this run, a killing blow leaves you at ${_pct(Balance.secondWindHull, isMultiplier: false)} hull instead',
        Relic.midas => '+${_pct(Balance.midasCoins)} NOVA coins from this run',
        Relic.scrapShield => 'Gain ${Balance.scrapShieldAmount.round()} shield for every ${Balance.scrapShieldKills} kills',
      };
}
