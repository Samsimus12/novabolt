import 'package:shared_preferences/shared_preferences.dart';

class StatsManager {
  StatsManager._();
  static final instance = StatsManager._();

  int _bestLevel = 1;
  int _bestKills = 0;

  int get bestLevel => _bestLevel;
  int get bestKills => _bestKills;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _bestLevel = prefs.getInt('stats_best_level') ?? 1;
    _bestKills = prefs.getInt('stats_best_kills') ?? 0;
  }

  // Updates in-memory immediately, persists in background.
  // Returns true if any record was beaten.
  bool submitRun({required int level, required int kills}) {
    bool newBest = false;
    if (level > _bestLevel) {
      _bestLevel = level;
      newBest = true;
    }
    if (kills > _bestKills) {
      _bestKills = kills;
      newBest = true;
    }
    _persist();
    return newBest;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('stats_best_level', _bestLevel);
    await prefs.setInt('stats_best_kills', _bestKills);
  }
}
