import 'dart:math' as math;
import 'dart:ui' show Color;

import '../components/player.dart';
import '../components/weapon.dart';
import '../components/weapon_explosive_bolt.dart';
import '../components/weapon_frost_shard.dart';
import '../components/weapon_homing_bolt.dart';
import '../components/weapon_magic_bolt.dart';
import '../components/weapon_rapid_fire.dart';
import '../components/weapon_spread_shot.dart';
import '../components/weapon_sword_aura.dart';
import '../novabolt_game.dart';
import 'ability_stats.dart';
import 'balance.dart';
import 'curses.dart';
import 'relics.dart';
import 'ship_ability.dart';

enum UpgradeCategory { weapon, nova, mobility, relic, ability }

/// Card rarity scales a stat card's numbers. Rolled per card; boss rewards
/// roll better. Weapon upgrade cards above common also add bonus damage.
enum CardRarity {
  common(1.0, 'Common'),
  rare(Balance.rareMultiplier, 'Rare'),
  epic(Balance.epicMultiplier, 'Epic'),
  legendary(Balance.legendaryMultiplier, 'Legendary');

  final double mult;
  final String label;
  const CardRarity(this.mult, this.label);

  static CardRarity roll(math.Random rng, {bool boss = false}) {
    final r = rng.nextDouble();
    final shift = boss ? Balance.bossRarityShift : 1.0;
    var edge = Balance.legendaryOdds * shift;
    if (r < edge) return CardRarity.legendary;
    edge += Balance.epicOdds * shift;
    if (r < edge) return CardRarity.epic;
    edge += Balance.rareOdds * shift;
    if (r < edge) return CardRarity.rare;
    return CardRarity.common;
  }
}

/// Presentation-only: which icon a card shows on the level-up screen.
enum CardGlyph {
  laser, scatter, pulse, homing, field, rocket, emp,
  targeting, overcharge, novaCharge, novaDuration, novaDamage,
  afterburner, hull, repair, relic, evolve, curse, ability,
}

CardGlyph glyphForWeapon(Weapon w) => switch (w) {
      WeaponSpreadShot() => CardGlyph.scatter,
      WeaponRapidFire() => CardGlyph.pulse,
      WeaponHomingBolt() => CardGlyph.homing,
      WeaponSwordAura() => CardGlyph.field,
      WeaponExplosiveBolt() => CardGlyph.rocket,
      WeaponFrostShard() => CardGlyph.emp,
      _ => CardGlyph.laser,
    };

abstract class UpgradeCard {
  CardRarity get rarity => CardRarity.common;
  String get title;
  String get description;
  CardGlyph get glyph;
  UpgradeCategory get category;
  void apply(NovaboltGame game);
}

class WeaponUpgradeCard extends UpgradeCard {
  final Weapon weapon;
  @override
  final CardRarity rarity;
  WeaponUpgradeCard(this.weapon, {this.rarity = CardRarity.common});

  int get _bonusPct => ((rarity.mult - 1) * 30).round();

  @override
  String get title => '${weapon.label} Lv${weapon.upgradeLevel + 1}';
  @override
  String get description => _bonusPct > 0
      ? '${weapon.nextUpgradeDescription}, plus +$_bonusPct% damage'
      : weapon.nextUpgradeDescription;
  @override
  CardGlyph get glyph => glyphForWeapon(weapon);
  @override
  UpgradeCategory get category => UpgradeCategory.weapon;
  @override
  void apply(NovaboltGame game) {
    weapon.applyUpgrade();
    if (_bonusPct > 0) weapon.damage *= 1 + _bonusPct / 100;
  }
}

class NewWeaponCard extends UpgradeCard {
  final String _title;
  final String _description;
  final Weapon Function() factory;
  @override
  final CardGlyph glyph;

  NewWeaponCard({
    required String title,
    required String description,
    required this.factory,
    required this.glyph,
  })  : _title = title,
        _description = description;

  @override
  String get title => _title;
  @override
  String get description => _description;
  @override
  UpgradeCategory get category => UpgradeCategory.weapon;
  @override
  void apply(NovaboltGame game) => game.player.add(factory());
}

class StatBuffCard extends UpgradeCard {
  final String _title;
  final String _description;
  @override
  final CardGlyph glyph;
  @override
  final CardRarity rarity;
  final UpgradeCategory _category;
  final void Function(NovaboltGame) _apply;

  StatBuffCard({
    required String title,
    required String description,
    required UpgradeCategory category,
    required void Function(NovaboltGame) apply,
    required this.glyph,
    this.rarity = CardRarity.common,
  })  : _title = title,
        _description = description,
        _category = category,
        _apply = apply;

  @override
  String get title => _title;
  @override
  String get description => _description;
  @override
  UpgradeCategory get category => _category;
  @override
  void apply(NovaboltGame game) {
    game.takenBuffs.add(_title);
    _apply(game);
  }
}

/// Boss reward: a run-long relic.
class RelicCard extends UpgradeCard {
  final Relic relic;
  RelicCard(this.relic);

  @override
  CardRarity get rarity => CardRarity.legendary;
  @override
  String get title => relic.title;
  @override
  String get description => relic.description;
  @override
  CardGlyph get glyph => CardGlyph.relic;
  @override
  UpgradeCategory get category => UpgradeCategory.relic;
  @override
  void apply(NovaboltGame game) => game.addRelic(relic);
}

/// A ship ability: a new one (fromLevel 0) or the next level of one owned.
/// The level-up screen tells them apart by [fromLevel].
class AbilityCard extends UpgradeCard {
  final ShipAbility ability;
  final int fromLevel;
  AbilityCard(this.ability, {this.fromLevel = 0});

  bool get isNew => fromLevel == 0;

  /// The level-up line ("Cooldown 18 s to 16.5 s"); empty for a new ability.
  String get change => AbilityStats.change(ability, fromLevel);

  @override
  CardRarity get rarity => isNew ? CardRarity.rare : CardRarity.common;
  @override
  String get title => ability.displayName;
  @override
  String get description => isNew ? '${ability.tagline} ${AbilityStats.summary(ability)}' : change;
  @override
  CardGlyph get glyph => CardGlyph.ability;
  @override
  UpgradeCategory get category => UpgradeCategory.ability;
  @override
  void apply(NovaboltGame game) {
    final lv = game.abilities.take(ability);
    game.announce(isNew ? '${ability.displayName} ready' : '${ability.displayName} Lv$lv', color: const Color(0xFF4DE8FF));
  }
}

/// Ability cards that could be offered now: every ability not yet owned (up
/// to all five) and every owned one below the max level.
List<AbilityCard> abilityCandidates(NovaboltGame game) {
  final a = game.abilities;
  return [
    for (final x in ShipAbility.values)
      if (a.levelOf(x) < ShipAbility.maxLevel) AbilityCard(x, fromLevel: a.levelOf(x)),
  ];
}

/// Puts an ability card into [offer], replacing an ordinary pick (never an
/// evolution, curse or another ability). While the ship owns nothing the first
/// offer always carries Dash; after that a card appears with
/// [AbilityStats.offerChance]. Boss rewards (relic chests) are left alone.
void maybeOfferAbility(NovaboltGame game, List<UpgradeCard> offer, math.Random rng) {
  if (game.isBossReward) return;
  final cands = abilityCandidates(game);
  if (cands.isEmpty || offer.any((c) => c is AbilityCard)) return;
  AbilityCard? card;
  if (game.abilities.owned.isEmpty && !game.abilityDashOffered) {
    card = cands.firstWhere((c) => c.ability == ShipAbility.dash);
    game.abilityDashOffered = true;
  } else if (rng.nextDouble() < AbilityStats.offerChance) {
    card = cands[rng.nextInt(cands.length)];
  }
  if (card == null) return;
  final replaceable = [
    for (var i = 0; i < offer.length; i++)
      if (offer[i] is! EvolutionCard && offer[i] is! CurseCard) i,
  ];
  if (replaceable.isEmpty) {
    offer.add(card);
  } else {
    offer[replaceable[rng.nextInt(replaceable.length)]] = card;
  }
}

/// Fuses a weapon into a stronger form once its recipe is met.
class EvolutionCard extends UpgradeCard {
  final Weapon weapon;
  final String name;
  final String _description;
  final void Function(Weapon) _boost;
  EvolutionCard(this.weapon, this.name, this._description, this._boost);

  @override
  CardRarity get rarity => CardRarity.legendary;
  @override
  String get title => 'Evolve: $name';
  @override
  String get description => _description;
  @override
  CardGlyph get glyph => CardGlyph.evolve;
  @override
  UpgradeCategory get category => UpgradeCategory.weapon;
  @override
  void apply(NovaboltGame game) {
    weapon.evolve(name);
    _boost(weapon);
    game.announce('$name online', color: const Color(0xFFFFC23D));
  }
}

/// Filler pick that is always valid (even at full hull, with every weapon
/// maxed): what the level-up offer falls back on when the real pool runs dry,
/// so the screen can never be empty.
class SupplyCard extends StatBuffCard {
  SupplyCard({
    required super.title,
    required super.description,
    required super.glyph,
    required super.apply,
  }) : super(category: UpgradeCategory.mobility);
}

/// [count] distinct supply cards (there are always at least four kinds).
List<UpgradeCard> supplyCards(NovaboltGame game, [int count = 3, math.Random? rng]) {
  final all = <UpgradeCard>[
    SupplyCard(
      title: 'Hull Repair',
      description: 'Repair half of your hull',
      glyph: CardGlyph.repair,
      apply: (g) => g.player.currentHp = math.min(g.player.maxHp, g.player.currentHp + g.player.maxHp * 0.5),
    ),
    SupplyCard(
      title: 'Reinforced Hull',
      description: '+25 max hull, and repair 25',
      glyph: CardGlyph.hull,
      apply: (g) {
        g.player.maxHp += 25;
        g.player.currentHp = math.min(g.player.maxHp, g.player.currentHp + 25);
      },
    ),
    SupplyCard(
      title: 'Salvage Haul',
      description: '+10% NOVA coins this run',
      glyph: CardGlyph.relic,
      apply: (g) => g.runCoinMultiplier *= 1.10,
    ),
    SupplyCard(
      title: 'Nova Cell',
      description: 'Instantly adds 30% Nova charge',
      glyph: CardGlyph.novaCharge,
      apply: (g) => g.superchargeSystem.addCharge(30 / g.superchargeSystem.chargeMultiplier),
    ),
  ]..shuffle(rng);
  return all.take(count.clamp(1, all.length)).toList();
}

/// An offer that is never empty: [cards] as given, or supplies if the pool
/// ran dry. Every place that builds an offer goes through this.
List<UpgradeCard> ensureOffer(NovaboltGame game, List<UpgradeCard> cards) =>
    cards.isEmpty ? supplyCards(game) : cards;

/// Three relics the player doesn't have yet (fewer when few are left; falls
/// back to supplies if none are, e.g. a resumed save).
List<UpgradeCard> generateRelicCards(NovaboltGame game) {
  final left = Relic.values.where((r) => !game.relics.contains(r) && game.relicAllowed(r)).toList()..shuffle();
  return ensureOffer(game, left.take(3).map<UpgradeCard>(RelicCard.new).toList());
}

/// Evolutions whose recipe is met right now.
List<UpgradeCard> _evolutions(NovaboltGame game) {
  final p = game.player;
  final out = <UpgradeCard>[];
  T? w<T extends Weapon>() => p.activeWeapons.whereType<T>().firstOrNull;
  bool lv(Weapon? x, int n) => x != null && !x.evolved && x.upgradeLevel >= n;

  final laser = w<WeaponMagicBolt>();
  final spread = w<WeaponSpreadShot>();
  final pulse = w<WeaponRapidFire>();
  final homing = w<WeaponHomingBolt>();
  final field = w<WeaponSwordAura>();
  final rocket = w<WeaponExplosiveBolt>();
  final emp = w<WeaponFrostShard>();

  if (lv(laser, 5) && game.takenBuffs.contains('Targeting Array')) {
    out.add(EvolutionCard(laser!, 'Ion Lance', 'Laser Bolt becomes a heavy lance that pierces 3 enemies', (x) => x.damage *= 1.3));
  }
  if (lv(spread, 5) && pulse != null) {
    out.add(EvolutionCard(spread!, 'Bullet Storm', 'Scatter Cannon fires 5 bolts, 50% faster', (x) => x.fireRate *= 1.5));
  }
  if (lv(homing, 5) && game.takenBuffs.contains('Overcharge')) {
    out.add(EvolutionCard(homing!, 'Swarm Missiles', 'Homing Missile launches three missiles per shot', (_) {}));
  }
  if (lv(field, 5) && emp != null) {
    out.add(EvolutionCard(field!, 'Cryo Field', 'Force Field grows wider and slows everything inside it', (x) => x.damage *= 1.2));
  }
  if (rocket != null && !rocket.evolved && lv(spread, 5)) {
    out.add(EvolutionCard(rocket, 'Rocket Barrage', 'Plasma Rocket fires a fan of three rockets', (x) => x.damage *= 1.2));
  }
  return out;
}

List<UpgradeCard> generateUpgradeCards(NovaboltGame game) {
  final rng = math.Random();
  final pool = <UpgradeCard>[];
  final player = game.player;
  final boss = game.isBossReward;
  CardRarity roll() => CardRarity.roll(rng, boss: boss || game.luckyCards);

  // Run-wide stat cards: one clean value per rarity from Balance, added to a
  // capped bonus (two +15% cards = +30%). A maxed bonus isn't offered. The
  // description shows the running total so stacking is easy to read.
  StatBuffCard? bonusCard({
    required String title,
    required String what,
    required UpgradeCategory category,
    required CardGlyph glyph,
    required List<int> tiers,
    required double current,
    required int cap,
    required void Function(NovaboltGame g, double add) apply,
    CardRarity minRarity = CardRarity.common,
  }) {
    final now = (current * 100).round();
    if (now >= cap) return null;
    var r = roll();
    if (r.index < minRarity.index) r = minRarity;
    final p = math.min(tiers[r.index], cap - now);
    final after = now + p;
    return StatBuffCard(
      title: title,
      description: now == 0
          ? '$what +$p%'
          : '$what +$p% (total +$now% → +$after%${after >= cap ? ', max' : ''})',
      category: category,
      glyph: glyph,
      rarity: r,
      apply: (g) => apply(g, p / 100),
    );
  }

  // --- Weapon category ---

  for (final w in player.activeWeapons) {
    if (w.canUpgrade) pool.add(WeaponUpgradeCard(w, rarity: roll()));
  }

  if (!player.hasWeapon<WeaponSpreadShot>()) {
    pool.add(NewWeaponCard(
      title: 'Scatter Cannon',
      description: 'Fires 3 laser blasts in a wide arc',
      factory: WeaponSpreadShot.new,
      glyph: CardGlyph.scatter,
    ));
  }
  if (!player.hasWeapon<WeaponRapidFire>()) {
    pool.add(NewWeaponCard(
      title: 'Pulse Cannon',
      description: '4 pulses/sec at 60% power each',
      factory: WeaponRapidFire.new,
      glyph: CardGlyph.pulse,
    ));
  }
  if (!player.hasWeapon<WeaponHomingBolt>()) {
    pool.add(NewWeaponCard(
      title: 'Homing Missile',
      description: 'Self-guided missile seeks the nearest target',
      factory: WeaponHomingBolt.new,
      glyph: CardGlyph.homing,
    ));
  }
  if (!player.hasWeapon<WeaponSwordAura>()) {
    pool.add(NewWeaponCard(
      title: 'Force Field',
      description: 'Energy ring shreds nearby enemies continuously',
      factory: WeaponSwordAura.new,
      glyph: CardGlyph.field,
    ));
  }
  if (!player.hasWeapon<WeaponExplosiveBolt>()) {
    pool.add(NewWeaponCard(
      title: 'Plasma Rocket',
      description: 'Detonates on impact, blasting all nearby enemies',
      factory: WeaponExplosiveBolt.new,
      glyph: CardGlyph.rocket,
    ));
  }
  if (!player.hasWeapon<WeaponFrostShard>()) {
    pool.add(NewWeaponCard(
      title: 'EMP Burst',
      description: 'EMP pulse slows targets to 40% speed for 2s',
      factory: WeaponFrostShard.new,
      glyph: CardGlyph.emp,
    ));
  }

  // Uncommon all-weapon damage buff (~10% chance), never below Rare.
  if (rng.nextDouble() < 0.10) {
    final c = bonusCard(
      title: 'Targeting Array',
      what: 'Weapon damage',
      category: UpgradeCategory.weapon,
      glyph: CardGlyph.targeting,
      tiers: Balance.weaponDamageTiers,
      current: game.weaponDamageBonus,
      cap: Balance.maxWeaponDamageBonus,
      minRarity: CardRarity.rare,
      apply: (g, add) => g.weaponDamageBonus += add,
    );
    if (c != null) pool.add(c);
  }

  final overcharge = bonusCard(
    title: 'Overcharge',
    what: 'Fire rate',
    category: UpgradeCategory.weapon,
    glyph: CardGlyph.overcharge,
    tiers: Balance.fireRateTiers,
    current: game.fireRateBonus,
    cap: Balance.maxFireRateBonus,
    apply: (g, add) => g.fireRateBonus += add,
  );
  if (overcharge != null) pool.add(overcharge);

  // --- Nova category ---
  final nova = game.superchargeSystem;
  for (final c in [
    bonusCard(
      title: 'Nova Accelerator',
      what: 'Nova charge speed',
      category: UpgradeCategory.nova,
      glyph: CardGlyph.novaCharge,
      tiers: Balance.novaChargeTiers,
      current: nova.chargeBonus,
      cap: Balance.maxNovaChargeBonus,
      apply: (g, add) => g.superchargeSystem.chargeBonus += add,
    ),
    bonusCard(
      title: 'Extended Beam',
      what: 'Nova duration',
      category: UpgradeCategory.nova,
      glyph: CardGlyph.novaDuration,
      tiers: Balance.novaDurationTiers,
      current: nova.durationBonus,
      cap: Balance.maxNovaDurationBonus,
      apply: (g, add) => g.superchargeSystem.durationBonus += add,
    ),
    bonusCard(
      title: 'Nova Overload',
      what: 'Nova damage',
      category: UpgradeCategory.nova,
      glyph: CardGlyph.novaDamage,
      tiers: Balance.novaDamageTiers,
      current: nova.damageBonus,
      cap: Balance.maxNovaDamageBonus,
      apply: (g, add) => g.superchargeSystem.damageBonus += add,
    ),
  ]) {
    if (c != null) pool.add(c);
  }

  // --- Mobility category ---

  if (player.afterburnerStacks < Player.maxAfterburnerStacks) {
    pool.add(StatBuffCard(
      title: 'Afterburner',
      description: 'Thrust upgrade — move speed +25%',
      category: UpgradeCategory.mobility,
      glyph: CardGlyph.afterburner,
      apply: (g) {
        g.player.moveSpeed *= 1.25;
        g.player.afterburnerStacks++;
      },
    ));
  }

  // Pick one random card from each category, then shuffle the result.
  final byCategory = <UpgradeCategory, List<UpgradeCard>>{};
  for (final card in pool) {
    byCategory.putIfAbsent(card.category, () => []).add(card);
  }

  final picks = <UpgradeCard>[];
  for (final cards in byCategory.values) {
    cards.shuffle(rng);
    picks.add(cards.first);
  }
  picks.shuffle(rng);

  // An available evolution always gets offered, in place of the weapon pick.
  final evos = _evolutions(game);
  if (evos.isNotEmpty) {
    final evo = evos[rng.nextInt(evos.length)];
    final i = picks.indexWhere((c) => c.category == UpgradeCategory.weapon);
    if (i >= 0) {
      picks[i] = evo;
    } else {
      picks.insert(0, evo);
    }
  }

  // Guard: pad if the pool was tiny (all weapons maxed, every bonus capped).
  if (picks.length < 3) {
    final chosen = picks.toSet();
    final leftovers = pool.where((c) => !chosen.contains(c)).toList()..shuffle(rng);
    picks.addAll(leftovers.take(3 - picks.length));
  }
  // Still short: supplies, so there are always three valid cards.
  if (picks.length < 3) picks.addAll(supplyCards(game, 3 - picks.length, rng));

  final offer = picks.take(3).toList();
  maybeOfferCurse(game, offer, rng);
  maybeOfferAbility(game, offer, rng);
  return offer;
}

// Rolls 0–2 bonus HP cards (each 20% chance). Caller applies and displays them.
List<StatBuffCard> rollBonusCards(NovaboltGame game) {
  final result = <StatBuffCard>[];
  final rng = math.Random();
  if (rng.nextDouble() < 0.20) {
    result.add(StatBuffCard(
      title: '+25 Hull Plating',
      description: 'Reinforce hull for +25 max HP',
      category: UpgradeCategory.mobility,
      glyph: CardGlyph.hull,
      apply: (g) {
        g.player.maxHp += 25;
        g.player.currentHp = (g.player.currentHp + 25).clamp(0, g.player.maxHp);
      },
    ));
  }
  if (rng.nextDouble() < 0.20) {
    result.add(StatBuffCard(
      title: 'Repair Drones',
      description: 'Emergency repair restores 40 HP',
      category: UpgradeCategory.mobility,
      glyph: CardGlyph.repair,
      apply: (g) {
        g.player.currentHp = (g.player.currentHp + 40).clamp(0, g.player.maxHp);
      },
    ));
  }
  return result;
}
