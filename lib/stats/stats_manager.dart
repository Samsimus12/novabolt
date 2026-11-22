import 'package:shared_preferences/shared_preferences.dart';

/// Personal bests and lifetime records, persisted locally.
class StatsManager {
  StatsManager._();
  static final instance = StatsManager._();

  int _bestLevel = 1;
  int _bestKills = 0;
  int _bestCombo = 0;
  int _totalKills = 0;
  int _totalRuns = 0;
  int _totalBossKills = 0;
  int _flawlessBossKills = 0;
  final Set<int> _bossesDefeated = {};

  int get bestLevel => _bestLevel;
  int get bestKills => _bestKills;
  int get bestCombo => _bestCombo;
  int get totalKills => _totalKills;
  int get totalRuns => _totalRuns;
  int get totalBossKills => _totalBossKills;
  int get flawlessBossKills => _flawlessBossKills;

  /// Which of the 10 bosses (by index 0–9) have ever been beaten.
  bool hasDefeatedBoss(int index) => _bossesDefeated.contains(index);
  int get bossesDiscovered => _bossesDefeated.length;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _bestLevel = prefs.getInt('stats_best_level') ?? 1;
    _bestKills = prefs.getInt('stats_best_kills') ?? 0;
    _bestCombo = prefs.getInt('stats_best_combo') ?? 0;
    _totalKills = prefs.getInt('stats_total_kills') ?? 0;
    _totalRuns = prefs.getInt('stats_total_runs') ?? 0;
    _totalBossKills = prefs.getInt('stats_total_boss_kills') ?? 0;
    _flawlessBossKills = prefs.getInt('stats_flawless_boss_kills') ?? 0;
    _bossesDefeated
      ..clear()
      ..addAll((prefs.getStringList('stats_bosses_defeated') ?? []).map(int.tryParse).whereType<int>());
  }

  /// A run started (counted once, not again on revive).
  void startRun() {
    _totalRuns++;
    _persist();
  }

  /// Kills are tallied in memory and saved with the next run/boss event.
  void addKill() => _totalKills++;

  void recordBossKill(int index, {required bool flawless}) {
    _totalBossKills++;
    if (flawless) _flawlessBossKills++;
    _bossesDefeated.add(index);
    _persist();
  }

  // Updates in-memory immediately, persists in background.
  // Returns true if any record was beaten.
  bool submitRun({required int level, required int kills, int combo = 0}) {
    bool newBest = false;
    if (level > _bestLevel) {
      _bestLevel = level;
      newBest = true;
    }
    if (kills > _bestKills) {
      _bestKills = kills;
      newBest = true;
    }
    if (combo > _bestCombo) _bestCombo = combo;
    _persist();
    return newBest;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('stats_best_level', _bestLevel);
    await prefs.setInt('stats_best_kills', _bestKills);
    await prefs.setInt('stats_best_combo', _bestCombo);
    await prefs.setInt('stats_total_kills', _totalKills);
    await prefs.setInt('stats_total_runs', _totalRuns);
    await prefs.setInt('stats_total_boss_kills', _totalBossKills);
    await prefs.setInt('stats_flawless_boss_kills', _flawlessBossKills);
    await prefs.setStringList('stats_bosses_defeated', _bossesDefeated.map((i) => '$i').toList());
  }
}
