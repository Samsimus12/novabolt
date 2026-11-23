import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/data/endgame.dart';
import 'package:novabolt/stats/stats_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final em = EndgameManager.instance;

  Future<void> boot(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    await StatsManager.instance.init();
    await em.init();
  }

  test('Ascension N stacks rules 1..N, one new rule per level', () {
    expect(AscensionRule.forLevel(0), isEmpty);
    expect(AscensionRule.forLevel(1), [AscensionRule.hardened]);
    expect(AscensionRule.forLevel(3).last, AscensionRule.swarming);
    expect(AscensionRule.forLevel(10), hasLength(EndgameBalance.maxAscension));
    expect(AscensionRule.forLevel(99), hasLength(EndgameBalance.maxAscension));
    for (final r in AscensionRule.values) {
      expect(r.level, r.index + 1);
    }
  });

  test('higher Ascension pays more NOVA', () {
    expect(EndgameBalance.ascensionCoinMultiplier(0), 1);
    expect(EndgameBalance.ascensionCoinMultiplier(10), closeTo(2.5, 1e-9));
  });

  test('endgame is locked until the Singularity has been beaten', () async {
    await boot({'stats_bosses_defeated': ['0', '1', '2']});
    expect(em.unlocked, isFalse);
    expect(em.maxAvailable, 0);
    expect(em.rushBosses, [0, 1, 2]);

    await boot({'stats_bosses_defeated': ['0', '2', '9']});
    expect(em.unlocked, isTrue);
    expect(em.maxAvailable, 1);
    expect(em.rushBosses, [0, 2, 9], reason: 'beaten bosses only, in order');
  });

  test('clearing Ascension N opens N+1, up to 10, and is remembered', () async {
    await boot({'stats_bosses_defeated': ['9']});
    expect(await em.recordVictory(const RunMode(ascension: 1)), isTrue);
    expect(em.maxAvailable, 2);
    expect(await em.recordVictory(const RunMode(ascension: 1)), isFalse, reason: 'already cleared');

    await em.init(); // reload from prefs
    expect(em.highestCleared, 1);

    expect(await em.recordVictory(const RunMode(ascension: 10)), isFalse, reason: 'nothing above 10');
    expect(em.maxAvailable, 10);

    expect(em.rushCleared, isFalse);
    await em.recordVictory(const RunMode(bossRush: true));
    expect(em.rushCleared, isTrue);
  });

  test('run modes', () {
    expect(RunMode.normal.isEndgame, isFalse);
    expect(const RunMode(ascension: 2).label, 'Ascension 2');
    expect(const RunMode(bossRush: true).endsInVictory, isTrue);
  });
}
