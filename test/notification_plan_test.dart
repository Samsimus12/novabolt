import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/notifications/notification_planner.dart';

List<PlannedNotification> plan(
  DateTime now, {
  bool enabled = true,
  bool played = false,
  int streak = 0,
  int claimable = 0,
  bool bg = false,
}) =>
    NotificationPlan.plan(
      now: now,
      enabled: enabled,
      playedDailyToday: played,
      streak: streak,
      claimableMissions: claimable,
      backgrounding: bg,
    );

PlannedNotification? of(List<PlannedNotification> l, NotificationKind k) {
  for (final n in l) {
    if (n.kind == k) return n;
  }
  return null;
}

void main() {
  final noon = DateTime(2026, 11, 24, 12);

  test('disabled schedules nothing', () {
    expect(plan(noon, enabled: false, streak: 3, claimable: 2, bg: true), isEmpty);
  });

  test('daily reminder: today 6 pm if unplayed, tomorrow if played or too late', () {
    expect(of(plan(noon), NotificationKind.daily)!.when, DateTime(2026, 11, 24, 18));
    expect(of(plan(noon, played: true), NotificationKind.daily)!.when, DateTime(2026, 11, 25, 18));
    expect(of(plan(DateTime(2026, 11, 24, 19)), NotificationKind.daily)!.when, DateTime(2026, 11, 25, 18));
  });

  test('streak at risk needs a streak and only fires while still saveable', () {
    expect(of(plan(noon), NotificationKind.streak), isNull);
    final s = of(plan(noon, streak: 4), NotificationKind.streak)!;
    expect(s.when, DateTime(2026, 11, 24, 20));
    expect(s.title, contains('4-day'));
    // Past 8 pm and not played: nothing (the streak is gone at midnight).
    expect(of(plan(DateTime(2026, 11, 24, 21), streak: 4), NotificationKind.streak), isNull);
    // Played today: the reminder moves to tomorrow evening.
    expect(of(plan(noon, streak: 4, played: true), NotificationKind.streak)!.when, DateTime(2026, 11, 25, 20));
  });

  test('missions ready only when backgrounding with something to claim, ~2 h later', () {
    expect(of(plan(noon, claimable: 2), NotificationKind.missions), isNull);
    expect(of(plan(noon, bg: true), NotificationKind.missions), isNull);
    final m = of(plan(noon, claimable: 1, bg: true), NotificationKind.missions)!;
    expect(m.when, DateTime(2026, 11, 24, 14));
    expect(m.title, 'A mission is ready');
    expect(of(plan(noon, claimable: 3, bg: true), NotificationKind.missions)!.title, '3 missions are ready');
  });

  test('comeback is 3 days out and never lands at night', () {
    expect(of(plan(noon), NotificationKind.comeback)!.when, DateTime(2026, 11, 27, 12));
    expect(of(plan(DateTime(2026, 11, 24, 22, 30)), NotificationKind.comeback)!.when, DateTime(2026, 11, 28, 10));
    expect(of(plan(DateTime(2026, 11, 24, 3)), NotificationKind.comeback)!.when, DateTime(2026, 11, 27, 10));
    // Missions: backgrounding at 9 pm -> 11 pm is night -> next morning.
    expect(of(plan(DateTime(2026, 11, 24, 21), claimable: 1, bg: true), NotificationKind.missions)!.when,
        DateTime(2026, 11, 25, 10));
  });

  test('everything is in the future and ids are unique', () {
    for (final h in [0, 9, 12, 17, 19, 21, 23]) {
      final now = DateTime(2026, 12, 31, h, 30);
      final l = plan(now, streak: 2, claimable: 1, bg: true);
      expect(l.every((n) => n.when.isAfter(now)), isTrue, reason: 'hour $h');
      expect(l.map((n) => n.id).toSet().length, l.length);
    }
  });
}
