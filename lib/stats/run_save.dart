import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The one saved, unfinished run ("Continue" on the main menu).
///
/// The snapshot itself is built and applied by `NovaboltGame.snapshot()` /
/// its resume path; this class only stores it. A run is saved when the app
/// goes to the background, after level-ups, on "Save and exit", and every
/// few seconds; it is cleared when the run ends in death or a new run starts.
class RunSaveManager {
  RunSaveManager._();
  static final instance = RunSaveManager._();

  /// Bump when the snapshot format changes incompatibly; older saves are
  /// then discarded instead of half-restored.
  static const version = 1;
  static const _key = 'run_save';

  Map<String, dynamic>? _data;

  bool get hasSave => _data != null;
  Map<String, dynamic>? get data => _data;

  // Summary for the menu.
  int get level => (_data?['lvl'] as int?) ?? 1;
  int get bossesBeaten => (_data?['beaten'] as int?) ?? 0;
  int get seconds => ((_data?['time'] as num?) ?? 0).round();
  String? get dailyDay => _data?['daily'] as String?;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      _data = d['v'] == version ? d : null;
    } catch (_) {
      _data = null;
    }
    if (_data == null) await prefs.remove(_key);
  }

  Future<void> save(Map<String, Object?> snapshot) async {
    _data = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(snapshot));
  }

  Future<void> clear() async {
    if (_data == null) return;
    _data = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
