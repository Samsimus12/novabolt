import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// One rule that changes a daily-challenge run.
enum DailyModifier {
  speedDemons('Speed demons', 'Enemies move 35% faster'),
  swarm('Swarm', 'Enemies arrive 40% faster'),
  novaRush('Nova rush', 'Nova charges twice as fast'),
  arsenal('Arsenal', 'Start with Scatter Cannon and Homing Missile'),
  glassCannon('Glass cannon', 'Start with the Glass cannon relic'),
  ironclad('Ironclad', '+60 max hull, but enemies hit 30% harder'),
  relicHunter('Relic hunter', 'Start with two random relics'),
  lucky('Lucky day', 'Upgrade cards roll rarer, +10% critical chance');

  final String title;
  final String description;
  const DailyModifier(this.title, this.description);
}

/// Today's challenge: the same two modifiers for everyone on a given date,
/// double NOVA coins, and a streak bonus for playing on consecutive days.
class DailyChallenge {
  final String dayKey; // yyyy-mm-dd, local time
  final List<DailyModifier> modifiers;
  final int seed;

  DailyChallenge._(this.dayKey, this.modifiers, this.seed);

  factory DailyChallenge.forDate(DateTime d) {
    final key = _key(d);
    // Stable per-date seed (not DateTime.hashCode, which isn't stable).
    final seed = d.year * 10000 + d.month * 100 + d.day;
    final rng = math.Random(seed);
    final pool = DailyModifier.values.toList()..shuffle(rng);
    return DailyChallenge._(key, pool.take(2).toList(), seed);
  }

  factory DailyChallenge.today() => DailyChallenge.forDate(DateTime.now());

  bool has(DailyModifier m) => modifiers.contains(m);

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const coinMultiplier = 2.0;
}

/// Persists the daily streak and today's best.
class DailyManager {
  DailyManager._();
  static final instance = DailyManager._();

  String? _lastPlayedDay;
  int _streak = 0;
  int _bestLevelToday = 0;
  String? _bestDay;

  DailyChallenge get today => DailyChallenge.today();

  /// Streak as it stands today (0 if a day was missed).
  int get streak {
    final t = today.dayKey;
    if (_lastPlayedDay == t || _lastPlayedDay == _yesterdayKey()) return _streak;
    return 0;
  }

  bool get playedToday => _lastPlayedDay == today.dayKey;
  int get bestLevelToday => _bestDay == today.dayKey ? _bestLevelToday : 0;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _lastPlayedDay = prefs.getString('daily_last_day');
    _streak = prefs.getInt('daily_streak') ?? 0;
    _bestDay = prefs.getString('daily_best_day');
    _bestLevelToday = prefs.getInt('daily_best_level') ?? 0;
  }

  /// Records a finished daily run. Returns the streak bonus in coins, paid
  /// only for the first daily run of the day.
  int completeRun({required int level}) {
    final t = today.dayKey;
    var bonus = 0;
    if (_lastPlayedDay != t) {
      _streak = _lastPlayedDay == _yesterdayKey() ? _streak + 1 : 1;
      _lastPlayedDay = t;
      bonus = 50 * math.min(_streak, 7);
    }
    if (_bestDay != t || level > _bestLevelToday) {
      _bestDay = t;
      _bestLevelToday = level;
    }
    _persist();
    return bonus;
  }

  /// What [completeRun] would pay if called now (for showing it up front).
  int get pendingStreakBonus {
    if (playedToday) return 0;
    final next = _lastPlayedDay == _yesterdayKey() ? _streak + 1 : 1;
    return 50 * math.min(next, 7);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_lastPlayedDay != null) await prefs.setString('daily_last_day', _lastPlayedDay!);
    await prefs.setInt('daily_streak', _streak);
    if (_bestDay != null) await prefs.setString('daily_best_day', _bestDay!);
    await prefs.setInt('daily_best_level', _bestLevelToday);
  }

  String _yesterdayKey() => DailyChallenge.forDate(DateTime.now().subtract(const Duration(days: 1))).dayKey;
}
