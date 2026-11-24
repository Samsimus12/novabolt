import 'package:shared_preferences/shared_preferences.dart';

/// What a finished stage attempt changed in the saved progress.
class AssaultStageRecord {
  final int stage;
  final int percent; // this attempt, 0..100
  final int score;
  final bool cleared;
  final int previousBestPercent;
  final int previousBestScore;

  /// Beat the stored best completion (a first attempt counts if percent > 0).
  final bool newBestPercent;
  final bool newBestScore;

  /// This attempt unlocked the next stage for the first time.
  final bool unlockedNext;
  const AssaultStageRecord({
    required this.stage,
    required this.percent,
    required this.score,
    required this.cleared,
    required this.previousBestPercent,
    required this.previousBestScore,
    required this.newBestPercent,
    required this.newBestScore,
    required this.unlockedNext,
  });
}

/// Saved Ground Assault progress (SharedPreferences):
/// `assault_unlocked` (highest unlocked stage index, 0 = only stage 1),
/// `assault_best_pct_<i>` and `assault_best_score_<i>` per stage.
/// Stage scores still pay NOVA through ArcadeManager; this is only the
/// per-stage record keeping.
abstract final class AssaultProgress {
  static const unlockedKey = 'assault_unlocked';
  static String pctKey(int i) => 'assault_best_pct_$i';
  static String scoreKey(int i) => 'assault_best_score_$i';

  static Future<int> unlocked({int stageCount = 1}) async {
    final p = await SharedPreferences.getInstance();
    return (p.getInt(unlockedKey) ?? 0).clamp(0, stageCount - 1);
  }

  static Future<int> bestPercent(int stage) async => (await SharedPreferences.getInstance()).getInt(pctKey(stage)) ?? 0;
  static Future<int> bestScore(int stage) async => (await SharedPreferences.getInstance()).getInt(scoreKey(stage)) ?? 0;

  /// Records an attempt. Clearing stage i unlocks stage i + 1 (if it exists).
  static Future<AssaultStageRecord> record({
    required int stage,
    required int stageCount,
    required int percent,
    required int score,
    required bool cleared,
  }) async {
    final p = await SharedPreferences.getInstance();
    final prevPct = p.getInt(pctKey(stage)) ?? 0;
    final prevScore = p.getInt(scoreKey(stage)) ?? 0;
    final pct = cleared ? 100 : percent.clamp(0, 99);
    final newPct = pct > prevPct;
    final newScore = score > prevScore;
    if (newPct) await p.setInt(pctKey(stage), pct);
    if (newScore) await p.setInt(scoreKey(stage), score);
    var unlockedNext = false;
    if (cleared && stage + 1 < stageCount) {
      final u = p.getInt(unlockedKey) ?? 0;
      if (stage + 1 > u) {
        await p.setInt(unlockedKey, stage + 1);
        unlockedNext = true;
      }
    }
    return AssaultStageRecord(
      stage: stage,
      percent: pct,
      score: score,
      cleared: cleared,
      previousBestPercent: prevPct,
      previousBestScore: prevScore,
      newBestPercent: newPct,
      newBestScore: newScore,
      unlockedNext: unlockedNext,
    );
  }
}
