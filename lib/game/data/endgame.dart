import 'package:shared_preferences/shared_preferences.dart';

import '../../stats/stats_manager.dart';

/// One Ascension rule. Ascension N applies rules 1..N, so every level keeps
/// everything below it and adds one more.
enum AscensionRule {
  hardened('Hardened', 'Enemies have 20% more hull'),
  quickened('Quickened', 'Enemies move 15% faster'),
  swarming('Swarming', 'Enemies arrive 20% faster'),
  eliteSurge('Elite surge', 'Elites appear twice as often'),
  sharpened('Sharpened', 'Enemies hit 20% harder'),
  titans('Titans', 'Bosses have 30% more hull'),
  thinHull('Thin hull', 'Start with 20% less max hull'),
  scarcity('Scarcity', 'Health and shield drops are 40% rarer'),
  noRerolls('No rerolls', 'Card rerolls are disabled'),
  noMercy('No mercy', 'No revives of any kind');

  final String title;
  final String description;
  const AscensionRule(this.title, this.description);

  /// 1-based level that introduces this rule.
  int get level => index + 1;

  static List<AscensionRule> forLevel(int level) => values.take(level.clamp(0, values.length)).toList();
}

/// Endgame tuning (Ascension and boss rush).
abstract final class EndgameBalance {
  static const int maxAscension = 10;

  /// Extra NOVA per Ascension level (A10 = +150%).
  static const double ascensionCoinsPerLevel = 0.15;
  static double ascensionCoinMultiplier(int level) => 1 + ascensionCoinsPerLevel * level;

  /// Index of the Singularity, the 10th and final boss.
  static const int finalBossIndex = 9;

  /// Boss rush: no waves or leveling, so the build comes from these picks.
  static const int rushStartPicks = 8;
  static const int rushPicksPerBoss = 5;

  /// Boss rush bosses keep their normal level but have less hull, since the
  /// ship has had far fewer upgrades than in a normal run by that point.
  static const double rushBossHp = 0.6;

  /// Seconds between a boss rush pick screen closing and the next boss.
  static const double rushBossDelay = 1.6;

  /// Extra NOVA for a boss rush run.
  static const double rushCoinMultiplier = 1.5;
}

/// Which kind of run this is. Daily challenges are separate (see
/// `DailyChallenge`); an endgame run is never a daily.
class RunMode {
  /// 0 = a normal run.
  final int ascension;
  final bool bossRush;
  const RunMode({this.ascension = 0, this.bossRush = false});

  static const normal = RunMode();

  bool get isEndgame => ascension > 0 || bossRush;

  /// The run ends in a Victory when the final boss falls.
  bool get endsInVictory => isEndgame;

  String get label => bossRush ? 'Boss rush' : (ascension > 0 ? 'Ascension $ascension' : 'Normal');
}

/// Persists Ascension progress. Ascension 1 opens after the Singularity has
/// been beaten once (in any run); clearing Ascension N opens N+1.
class EndgameManager {
  EndgameManager._();
  static final instance = EndgameManager._();

  int _cleared = 0;
  bool _rushCleared = false;

  /// Highest Ascension level beaten (0 = none).
  int get highestCleared => _cleared;
  bool get rushCleared => _rushCleared;

  /// Endgame modes appear once the Singularity has fallen.
  bool get unlocked => StatsManager.instance.hasDefeatedBoss(EndgameBalance.finalBossIndex);

  /// Highest Ascension level the player may pick (0 when locked).
  int get maxAvailable => unlocked ? (_cleared + 1).clamp(1, EndgameBalance.maxAscension) : 0;

  /// Bosses in a boss rush: every boss ever beaten, in their normal order.
  List<int> get rushBosses => [
        for (var i = 0; i <= EndgameBalance.finalBossIndex; i++)
          if (StatsManager.instance.hasDefeatedBoss(i)) i,
      ];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cleared = prefs.getInt('ascension_cleared') ?? 0;
    _rushCleared = prefs.getBool('boss_rush_cleared') ?? false;
  }

  /// Records a won endgame run. Returns true when it opened a new
  /// Ascension level.
  Future<bool> recordVictory(RunMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode.bossRush) {
      _rushCleared = true;
      await prefs.setBool('boss_rush_cleared', true);
      return false;
    }
    if (mode.ascension <= _cleared) return false;
    final opened = mode.ascension < EndgameBalance.maxAscension;
    _cleared = mode.ascension;
    await prefs.setInt('ascension_cleared', _cleared);
    return opened;
  }
}
