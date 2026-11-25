import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../coins/coin_manager.dart';
import '../stats/stats_manager.dart';

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
  ),
  swarmSiege(
    'invaders',
    'Swarm Siege',
    "Hold the line. Don't let the swarm land.",
  ),
  cockpit(
    'cockpit',
    'Mayday',
    'Alarms everywhere. Fix the cockpit before time runs out.',
  ),
  shmup(
    'shmup',
    'Rift Runner',
    'Fly the rift, dodge the rock, break its guardian.',
  ),
  starport(
    'starport',
    'Boarding Call',
    'Clear the hangar. Board every passenger.',
  );

  /// Stable id used in prefs keys. Never rename.
  final String id;
  final String title;
  final String tagline;
  const ArcadeGame(this.id, this.title, this.tagline);

}

/// How a locked game opens: beating a main-game boss (0-based index, so
/// boss 2 is 1) or paying [price] NOVA early.
class ArcadeUnlock {
  final int bossIndex;
  final int price;
  const ArcadeUnlock(this.bossIndex, this.price);

  /// "Boss 2", for display.
  int get bossNumber => bossIndex + 1;
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

  /// THE unlock table (tune boss and price here). Games not listed are free
  /// from the start (Thread the Needle).
  static const Map<ArcadeGame, ArcadeUnlock> unlocks = {
    ArcadeGame.groundAssault: ArcadeUnlock(1, 500),
    ArcadeGame.swarmSiege: ArcadeUnlock(2, 750),
    ArcadeGame.cockpit: ArcadeUnlock(3, 1000),
    ArcadeGame.shmup: ArcadeUnlock(4, 1250),
    ArcadeGame.starport: ArcadeUnlock(5, 1500),
  };

  static const int dailyCap = 300;
  static const int coinsPerPoint = 2;
  static const int coinsPerBonus = 5;

  final Map<String, int> _best = {};
  final Map<String, int> _plays = {};
  final Set<String> _unlocked = {};

  /// Games a boss kill opened that the hub hasn't announced yet (persisted,
  /// so an unlock granted at app start still gets its banner).
  final List<String> _unseen = [];
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
    _unlocked
      ..clear()
      ..addAll(prefs.getStringList('arcade_unlocked') ?? const []);
    _unseen
      ..clear()
      ..addAll(prefs.getStringList('arcade_unseen') ?? const []);
    refreshUnlocks(); // after StatsManager.init (see main.dart)
  }

  /// Can the player open this game?
  bool isUnlocked(ArcadeGame g) => !unlocks.containsKey(g) || _unlocked.contains(g.id);

  /// NOVA price to unlock early (0 for a free or already unlocked game).
  int unlockPrice(ArcadeGame g) => isUnlocked(g) ? 0 : unlocks[g]!.price;

  /// Why it is locked, for the card ("" when unlocked).
  String unlockReason(ArcadeGame g) =>
      isUnlocked(g) ? '' : 'Beat boss ${unlocks[g]!.bossNumber} in the main game';

  /// Grants every unlock that has been earned: the boss was beaten, or the
  /// game already has a record here (players from before unlocks existed keep
  /// what they've played). Persisted once granted, so it sticks. Returns the
  /// games that were just unlocked.
  List<ArcadeGame> refreshUnlocks() {
    final fresh = <ArcadeGame>[];
    for (final e in unlocks.entries) {
      final g = e.key;
      if (_unlocked.contains(g.id)) continue;
      final played = best(g) > 0 || plays(g) > 0;
      if (StatsManager.instance.hasDefeatedBoss(e.value.bossIndex) || played) {
        _unlocked.add(g.id);
        fresh.add(g);
        // Only a boss kill is news; a game kept from before unlocks isn't.
        if (!played) _unseen.add(g.id);
      }
    }
    if (fresh.isNotEmpty) _saveUnlocked();
    return fresh;
  }

  /// Games a boss kill opened since the hub last showed them, in table
  /// order; clears the list. The hub calls this once when it opens.
  List<ArcadeGame> takeNewUnlocks() {
    if (_unseen.isEmpty) return const [];
    final out = [for (final g in unlocks.keys) if (_unseen.contains(g.id)) g];
    _unseen.clear();
    _saveUnlocked();
    return out;
  }

  /// Buys a locked game early. False if it's free/unlocked or NOVA is short.
  /// Single-flight: a second call for the same game while one is running
  /// returns false without charging.
  Future<bool> buy(ArcadeGame g) async {
    if (isUnlocked(g) || !_buying.add(g)) return false;
    try {
      if (!await CoinManager.instance.spend(unlocks[g]!.price)) return false;
      _unlocked.add(g.id);
      await _saveUnlocked();
      return true;
    } finally {
      _buying.remove(g);
    }
  }

  final Set<ArcadeGame> _buying = {};

  Future<void> _saveUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('arcade_unlocked', _unlocked.toList());
    await prefs.setStringList('arcade_unseen', _unseen.toList());
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
