import 'package:shared_preferences/shared_preferences.dart';

class CoinManager {
  CoinManager._();
  static final instance = CoinManager._();

  int _totalCoins = 0;
  int get totalCoins => _totalCoins;

  String _selectedSkin = 'default';
  String get selectedSkin => _selectedSkin;

  String _selectedShieldSkin = 'shield_default';
  String get selectedShieldSkin => _selectedShieldSkin;

  String _selectedNovaTheme = 'nova_default';
  String get selectedNovaTheme => _selectedNovaTheme;

  final Set<String> _owned = {'skin_default', 'shield_default', 'nova_default'};
  bool owns(String id) => _owned.contains(id);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _totalCoins = prefs.getInt('coins_total') ?? 0;
    _selectedSkin = prefs.getString('skin_selected') ?? 'default';
    _selectedShieldSkin = prefs.getString('shield_skin_selected') ?? 'shield_default';
    _selectedNovaTheme = prefs.getString('nova_theme_selected') ?? 'nova_default';
    final saved = prefs.getStringList('items_owned') ?? [];
    _owned.addAll(saved);
  }

  Future<void> addCoins(int amount) async {
    _totalCoins += amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coins_total', _totalCoins);
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

  Future<void> selectSkin(String skinId) async {
    if (!_owned.contains('skin_$skinId')) return;
    _selectedSkin = skinId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('skin_selected', skinId);
  }

  Future<void> selectShieldSkin(String id) async {
    if (!_owned.contains(id)) return;
    _selectedShieldSkin = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shield_skin_selected', id);
  }

  Future<void> selectNovaTheme(String id) async {
    if (!_owned.contains(id)) return;
    _selectedNovaTheme = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nova_theme_selected', id);
  }
}
