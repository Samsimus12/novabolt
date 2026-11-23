import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../coins/coin_manager.dart';

/// The arcade's mini-games. Add a value here when a new game ships; the
/// Arcade screen lists them in this order.
enum ArcadeGame {
  threadTheNeedle(
    'thread',
    'Thread the Needle',
    'Tap to burst up. Fly through the gaps.',
  ),
  groundAssault(
    'assault',
    'Ground Assault',
    'Crash-landed. Fight your way back to the ship.',
  );

  /// Stable id used in prefs keys. Never rename.
  final String id;
  final String title;
  final String tagline;
  const ArcadeGame(this.id, this.title, this.tagline);

  /// Every game is out now. A future game that isn't ready can override this
  /// (the hub shows a dimmed "Coming soon" card for it).
  bool get available => true;
}

/// The result of one arcade round, after the payout has been worked out.
class ArcadeResult {
  final int score;
  final int bonus; // e.g. NOVA shards picked up
  final int coins; // what was actually paid (after the daily cap)
  final int uncapped; // what the round was worth before the cap
  final bool newBest;
  final int best;
  const ArcadeResult({
    required this.score,
    required this.bonus,
    required this.coins,
    required this.uncapped,
    required this.newBest,
    required this.best,
  });

  bool get capped => coins < uncapped;
}

/// High scores per game and the arcade's NOVA payout. The arcade pays a
/// little NOVA per round, limited to [dailyCap] a day across all games, so
/// it is a fun break, not a better coin farm than the main game.
class ArcadeManager {
  ArcadeManager._();
  static final instance = ArcadeManager._();

  static const int dailyCap = 300;
  static const int coinsPerPoint = 2;
  static const int coinsPerBonus = 5;

  final Map<String, int> _best = {};
  final Map<String, int> _plays = {};
  String _day = '';
  int _earnedToday = 0;

  /// Overridable clock for tests.
  DateTime Function() now = DateTime.now;

  int best(ArcadeGame g) => _best[g.id] ?? 0;
  int plays(ArcadeGame g) => _plays[g.id] ?? 0;

  int get earnedToday => _day == _key(now()) ? _earnedToday : 0;
  int get leftToday => math.max(0, dailyCap - earnedToday);

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    for (final g in ArcadeGame.values) {
      _best[g.id] = prefs.getInt('arcade_best_${g.id}') ?? 0;
      _plays[g.id] = prefs.getInt('arcade_plays_${g.id}') ?? 0;
    }
    _day = prefs.getString('arcade_day') ?? '';
    _earnedToday = prefs.getInt('arcade_earned') ?? 0;
  }

  /// What a round is worth before the daily cap.
  static int worth(int score, int bonus) => score * coinsPerPoint + bonus * coinsPerBonus;

  /// Records a finished round: updates the best score and pays NOVA (up to
  /// what is left of today's cap).
  Future<ArcadeResult> finishRound(ArcadeGame g, {required int score, int bonus = 0}) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _key(now());
    if (_day != today) {
      _day = today;
      _earnedToday = 0;
    }
    final uncapped = worth(score, bonus);
    final paid = math.min(uncapped, leftToday);
    _earnedToday += paid;

    final previous = best(g);
    final newBest = score > previous;
    if (newBest) _best[g.id] = score;
    _plays[g.id] = plays(g) + 1;

    await prefs.setString('arcade_day', _day);
    await prefs.setInt('arcade_earned', _earnedToday);
    await prefs.setInt('arcade_best_${g.id}', best(g));
    await prefs.setInt('arcade_plays_${g.id}', plays(g));
    if (paid > 0) await CoinManager.instance.addCoins(paid);

    return ArcadeResult(
      score: score,
      bonus: bonus,
      coins: paid,
      uncapped: uncapped,
      newBest: newBest && previous > 0,
      best: best(g),
    );
  }
}
