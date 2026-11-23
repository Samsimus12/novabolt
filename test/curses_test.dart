import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/game/data/balance.dart';
import 'package:novabolt/game/data/curses.dart';

void main() {
  bool offer({int level = 10, bool boss = false, int taken = 0, double roll = 0}) =>
      shouldOfferCurse(level: level, bossReward: boss, cursesTaken: taken, roll: roll);

  test('curses are offered only on ordinary level-ups past the minimum level', () {
    expect(offer(), isTrue);
    expect(offer(boss: true), isFalse, reason: 'never a boss reward');
    expect(offer(level: Balance.curseMinLevel - 1), isFalse);
    expect(offer(level: Balance.curseMinLevel), isTrue);
  });

  test('the chance and the per-run cap apply', () {
    expect(offer(roll: Balance.curseChance - 0.001), isTrue);
    expect(offer(roll: Balance.curseChance), isFalse);
    expect(offer(taken: Balance.maxCursesPerRun - 1), isTrue);
    expect(offer(taken: Balance.maxCursesPerRun), isFalse);
  });

  test('every curse has a unique name, a boon and a catch', () {
    final titles = Curse.values.map((c) => c.title).toSet();
    expect(titles, hasLength(Curse.values.length));
    for (final c in Curse.values) {
      expect(c.boon, isNotEmpty, reason: c.title);
      expect(c.cost, isNotEmpty, reason: c.title);
      expect(CurseCard(c).description, contains('The catch'));
    }
  });
}
