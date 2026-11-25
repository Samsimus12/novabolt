import 'package:shared_preferences/shared_preferences.dart';

import '../game/data/balance.dart';
import '../game/data/ship_class.dart';
import 'coin_manager.dart';

/// Permanent ship upgrades bought with NOVA coins in the Hangar.
/// Each level is applied at the start of every run by [HangarManager.applyTo].
enum HangarUpgrade {
  hull('Reinforced hull', '+10 max hull per level', maxLevel: 5, baseCost: 150),
  armor('Ablative armor', '−3% damage taken per level', maxLevel: 5, baseCost: 200),
  firepower('Firepower', '+4% damage per level', maxLevel: 5, baseCost: 250),
  critical('Targeting computer', '+1.5% critical hit chance per level', maxLevel: 5, baseCost: 220),
  novaStart('Nova capacitor', 'Start each run with +15% Nova charge per level', maxLevel: 4, baseCost: 150),
  magnet('Tractor beam', 'Pulls pickups toward you from further away', maxLevel: 4, baseCost: 120),
  salvage('Salvage rig', '+10% NOVA coins per level', maxLevel: 5, baseCost: 200),
  reroll('Recalibrator', '+1 extra upgrade reroll per run per level', maxLevel: 3, baseCost: 300),
  revive('Emergency reactor', 'Once per run, revive at half hull for free', maxLevel: 1, baseCost: 1500);

  final String title;
  final String description;
  final int maxLevel;
  final int baseCost;
  const HangarUpgrade(this.title, this.description, {required this.maxLevel, required this.baseCost});

  /// Price of the next level (each level costs 1.6x the last, rounded to 10).
  int costForLevel(int currentLevel) {
    var c = baseCost.toDouble();
    for (var i = 0; i < currentLevel; i++) {
      c *= 1.6;
    }
    return (c / 10).round() * 10;
  }
}

class HangarManager {
  HangarManager._();
  static final instance = HangarManager._();

  final _levels = <HangarUpgrade, int>{};

  // ── Ship classes ──────────────────────────────────────────────────────────
  final _ownedClasses = <ShipClass>{ShipClass.vanguard};
  ShipClass _selectedClass = ShipClass.vanguard;
  ShipClass get selectedClass => _selectedClass;
  bool ownsClass(ShipClass c) => _ownedClasses.contains(c);

  /// Buys [c] and selects it. False if already owned or not enough coins.
  Future<bool> buyClass(ShipClass c) async {
    if (ownsClass(c)) return false;
    if (!await CoinManager.instance.spend(c.cost)) return false;
    _ownedClasses.add(c);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ship_classes', [for (final o in _ownedClasses) o.name]);
    await selectClass(c);
    return true;
  }

  Future<void> selectClass(ShipClass c) async {
    if (!ownsClass(c)) return;
    _selectedClass = c;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ship_class', c.name);
  }

  int level(HangarUpgrade u) => _levels[u] ?? 0;
  int get totalLevels => HangarUpgrade.values.fold(0, (s, u) => s + level(u));
  bool isMaxed(HangarUpgrade u) => level(u) >= u.maxLevel;
  int nextCost(HangarUpgrade u) => u.costForLevel(level(u));

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    for (final u in HangarUpgrade.values) {
      _levels[u] = (prefs.getInt('hangar_${u.name}') ?? 0).clamp(0, u.maxLevel);
    }
    _ownedClasses
      ..clear()
      ..add(ShipClass.vanguard)
      ..addAll((prefs.getStringList('ship_classes') ?? const []).map(ShipClass.byName));
    final sel = ShipClass.byName(prefs.getString('ship_class'));
    _selectedClass = ownsClass(sel) ? sel : ShipClass.vanguard;
  }

  /// Buys the next level. Returns false if maxed or not enough coins.
  Future<bool> buy(HangarUpgrade u) async {
    if (isMaxed(u)) return false;
    if (!await CoinManager.instance.spend(nextCost(u))) return false;
    _levels[u] = level(u) + 1;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hangar_${u.name}', level(u));
    return true;
  }

  // ── Derived values (read by the game at run start) ────────────────────────
  double get bonusHull => Balance.hangarHull * level(HangarUpgrade.hull);
  double get damageTakenMultiplier => 1 - Balance.hangarArmor * level(HangarUpgrade.armor);
  double get damageMultiplier => 1 + Balance.hangarFirepower * level(HangarUpgrade.firepower);
  double get bonusCritChance => Balance.hangarCrit * level(HangarUpgrade.critical);
  double get startNovaFraction => Balance.hangarNovaStart * level(HangarUpgrade.novaStart);
  double get magnetRadius => switch (level(HangarUpgrade.magnet)) {
        0 => 0,
        final l => 50.0 + 45 * l,
      };
  double get coinMultiplier => 1 + Balance.hangarSalvage * level(HangarUpgrade.salvage);
  int get freeRerolls => level(HangarUpgrade.reroll);
  bool get hasFreeRevive => level(HangarUpgrade.revive) > 0;
}
