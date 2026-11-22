import 'package:shared_preferences/shared_preferences.dart';

import '../cosmetics/catalog.dart';

class CoinManager {
  CoinManager._();
  static final instance = CoinManager._();

  int _totalCoins = 0;
  int get totalCoins => _totalCoins;

  // Pref keys are unchanged from v1.0 so existing purchases carry over.
  static const _selectedKeys = {
    CosmeticKind.ship: 'skin_selected',
    CosmeticKind.shield: 'shield_skin_selected',
    CosmeticKind.beam: 'nova_theme_selected',
    CosmeticKind.thruster: 'thruster_selected',
    CosmeticKind.explosion: 'explosion_selected',
  };

  final Map<CosmeticKind, String> _selected = {
    for (final k in CosmeticKind.values) k: defaultIdFor(k),
  };

  String selected(CosmeticKind kind) => _selected[kind]!;
  String get selectedSkin => selected(CosmeticKind.ship);
  String get selectedShieldSkin => selected(CosmeticKind.shield);
  String get selectedNovaTheme => selected(CosmeticKind.beam);
  String get selectedThruster => selected(CosmeticKind.thruster);
  String get selectedExplosion => selected(CosmeticKind.explosion);

  final Set<String> _owned = {
    for (final k in CosmeticKind.values) catalogFor(k).first.ownId,
  };
  bool owns(String id) => _owned.contains(id);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _totalCoins = prefs.getInt('coins_total') ?? 0;
    for (final k in CosmeticKind.values) {
      _selected[k] = prefs.getString(_selectedKeys[k]!) ?? defaultIdFor(k);
    }
    final saved = prefs.getStringList('items_owned') ?? [];
    _owned.addAll(saved);
  }

  Future<void> addCoins(int amount) async {
    _totalCoins += amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coins_total', _totalCoins);
  }

  /// Spend coins on something that isn't an owned item (hangar upgrades).
  Future<bool> spend(int amount) async {
    if (amount <= 0 || _totalCoins < amount) return false;
    _totalCoins -= amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coins_total', _totalCoins);
    return true;
  }

  Future<bool> purchase(String id, int price) async {
    if (_totalCoins < price || _owned.contains(id)) return false;
    _totalCoins -= price;
    _owned.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coins_total', _totalCoins);
    await prefs.setStringList('items_owned', _owned.toList());
    return true;
  }

  /// Equip an owned item. [item] must come from the catalogue.
  Future<void> select(Cosmetic item) async {
    if (!_owned.contains(item.ownId)) return;
    _selected[item.kind] = item.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedKeys[item.kind]!, item.id);
  }

  Future<void> selectSkin(String skinId) => select(findCosmetic(CosmeticKind.ship, skinId));

  Future<void> selectShieldSkin(String id) => select(findCosmetic(CosmeticKind.shield, id));

  Future<void> selectNovaTheme(String id) => select(findCosmetic(CosmeticKind.beam, id));
}
