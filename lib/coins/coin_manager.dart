import 'package:shared_preferences/shared_preferences.dart';

class CoinManager {
  CoinManager._();
  static final instance = CoinManager._();

  int _totalCoins = 0;
  int get totalCoins => _totalCoins;

  String _selectedSkin = 'default';
  String get selectedSkin => _selectedSkin;

  String _selectedBackground = 'default';
  String get selectedBackground => _selectedBackground;

  final Set<String> _owned = {'skin_default', 'bg_default'};
  bool owns(String id) => _owned.contains(id);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _totalCoins = prefs.getInt('coins_total') ?? 0;
    _selectedSkin = prefs.getString('skin_selected') ?? 'default';
    _selectedBackground = prefs.getString('bg_selected') ?? 'default';
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

  Future<void> selectBackground(String bgId) async {
    if (!_owned.contains('bg_$bgId')) return;
    _selectedBackground = bgId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_selected', bgId);
  }
}
