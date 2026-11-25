// B3 verification: planner invariants over a full year (so DST changes in
// whatever zone the machine is in are covered; run with TZ=... to try others),
// boundary instants, and the manager with the platform channels mocked.
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/notifications/notification_manager.dart';
import 'package:novabolt/notifications/notification_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planner', () {
    test('invariants hold at every half hour of a whole year (covers both DST changes)', () {
      var checked = 0;
      var t = DateTime(2026, 1, 1, 0, 7);
      final end = DateTime(2027, 1, 2);
      while (t.isBefore(end)) {
        for (final played in [false, true]) {
          final l = plan(t, played: played, streak: 3, claimable: 2, bg: true);
          final label = '$t played=$played';
          // Unique ids; everything strictly in the future.
          expect(l.map((n) => n.id).toSet().length, l.length, reason: label);
          for (final n in l) {
            expect(n.when.isAfter(t), isTrue, reason: '$label ${n.kind}');
          }
          // Wall-clock hours are exactly right even across a DST change.
          final d = of(l, NotificationKind.daily)!;
          expect((d.when.hour, d.when.minute), (18, 0), reason: label);
          final todayAt18 = DateTime(t.year, t.month, t.day, 18);
          if (!played && todayAt18.isAfter(t)) {
            expect(d.when, todayAt18, reason: label);
          } else {
            expect(d.when, DateTime(t.year, t.month, t.day + 1, 18), reason: label);
          }
          final s = of(l, NotificationKind.streak);
          if (s != null) {
            expect((s.when.hour, s.when.minute), (20, 0), reason: label);
            if (!played) expect(s.when, DateTime(t.year, t.month, t.day, 20), reason: label);
          } else {
            expect(played, isFalse, reason: 'with a streak and a play today, tomorrow\'s must exist: $label');
            expect(DateTime(t.year, t.month, t.day, 20).isAfter(t), isFalse, reason: label);
          }
          // Missions and comeback never land in the quiet hours (22:00-10:00).
          for (final k in [NotificationKind.missions, NotificationKind.comeback]) {
            final n = of(l, k)!;
            expect(n.when.hour, inInclusiveRange(10, 21), reason: '$label $k at ${n.when}');
          }
          final c = of(l, NotificationKind.comeback)!;
          final gap = c.when.difference(t);
          expect(gap, greaterThan(const Duration(hours: 70)), reason: label);
          expect(gap, lessThan(const Duration(days: 4)), reason: label);
          final m = of(l, NotificationKind.missions)!;
          expect(m.when.difference(t), greaterThanOrEqualTo(const Duration(hours: 1)), reason: label);
          expect(m.when.difference(t), lessThan(const Duration(hours: 24)), reason: label);
          checked++;
        }
        t = t.add(const Duration(minutes: 30));
      }
      expect(checked, greaterThan(17000));
    });

    test('boundaries: exactly 6 pm / 8 pm / 10 pm / 10 am', () {
      // 6:00:00 pm exactly: today's 6 pm is not in the future, so tomorrow.
      expect(of(plan(DateTime(2026, 11, 24, 18)), NotificationKind.daily)!.when, DateTime(2026, 11, 25, 18));
      expect(of(plan(DateTime(2026, 11, 24, 17, 59, 59)), NotificationKind.daily)!.when, DateTime(2026, 11, 24, 18));
      // 8:00:00 pm exactly with a streak and no play: gone.
      expect(of(plan(DateTime(2026, 11, 24, 20), streak: 5), NotificationKind.streak), isNull);
      expect(of(plan(DateTime(2026, 11, 24, 19, 59), streak: 5), NotificationKind.streak)!.when, DateTime(2026, 11, 24, 20));
      // Quiet window edges for the comeback nudge (3 days after "now").
      expect(of(plan(DateTime(2026, 11, 24, 21, 59)), NotificationKind.comeback)!.when, DateTime(2026, 11, 27, 21, 59));
      expect(of(plan(DateTime(2026, 11, 24, 22, 0)), NotificationKind.comeback)!.when, DateTime(2026, 11, 28, 10));
      expect(of(plan(DateTime(2026, 11, 24, 9, 59)), NotificationKind.comeback)!.when, DateTime(2026, 11, 27, 10));
      expect(of(plan(DateTime(2026, 11, 24, 10, 0)), NotificationKind.comeback)!.when, DateTime(2026, 11, 27, 10));
    });

    test('month and year rollover', () {
      final l = plan(DateTime(2026, 12, 31, 21, 30), streak: 9, played: true, claimable: 1, bg: true);
      expect(of(l, NotificationKind.daily)!.when, DateTime(2027, 1, 1, 18));
      expect(of(l, NotificationKind.streak)!.when, DateTime(2027, 1, 1, 20));
      expect(of(l, NotificationKind.comeback)!.when, DateTime(2027, 1, 3, 21, 30));
      expect(of(l, NotificationKind.missions)!.when, DateTime(2027, 1, 1, 10));
      final feb = plan(DateTime(2028, 2, 28, 12), played: true); // leap year
      expect(of(feb, NotificationKind.daily)!.when, DateTime(2028, 2, 29, 18));
    });

    test('toggle off schedules nothing for any input', () {
      for (final bg in [true, false]) {
        for (final played in [true, false]) {
          expect(plan(DateTime(2026, 11, 24, 12), enabled: false, played: played, streak: 5, claimable: 3, bg: bg), isEmpty);
        }
      }
    });

    test('a played daily moves the daily reminder to tomorrow, never drops it', () {
      for (final h in [0, 6, 12, 17, 18, 19, 23]) {
        final l = plan(DateTime(2026, 11, 24, h), played: true);
        expect(of(l, NotificationKind.daily)!.when, DateTime(2026, 11, 25, 18), reason: 'hour $h');
      }
    });

    test('streak-at-risk needs a streak: zero streak never schedules one', () {
      for (final h in [0, 12, 19, 23]) {
        for (final played in [true, false]) {
          expect(of(plan(DateTime(2026, 11, 24, h), played: played), NotificationKind.streak), isNull);
        }
      }
    });

    test('titles are plain and singular/plural is right', () {
      final one = of(plan(DateTime(2026, 11, 24, 12), streak: 1), NotificationKind.streak)!;
      expect(one.title, contains('1-day'));
      expect(of(plan(DateTime(2026, 11, 24, 12), claimable: 1, bg: true), NotificationKind.missions)!.title, 'A mission is ready');
      expect(of(plan(DateTime(2026, 11, 24, 12), claimable: 2, bg: true), NotificationKind.missions)!.title, '2 missions are ready');
    });
  });

  group('manager (platform channels mocked)', () {
    final calls = <String>[];
    const notif = MethodChannel('dexterous.com/flutter/local_notifications');
    const tz = MethodChannel('flutter_timezone');

    setUp(() {
      calls.clear();
      AndroidFlutterLocalNotificationsPlugin.registerWith(); // a real app does this at startup
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(notif, (c) async {
        calls.add(c.method);
        return switch (c.method) {
          'initialize' => true,
          'requestNotificationsPermission' => true,
          _ => null,
        };
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(tz, (c) async => 'America/Denver');
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(notif, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(tz, null);
    });

    int count(String m) => calls.where((c) => c == m).length;

    test('first launch: no permission prompt, nothing scheduled', () async {
      final m = NotificationManager.instance;
      await m.init();
      await m.reschedule();
      await m.reschedule(backgrounding: true);
      expect(count('requestNotificationsPermission'), 0, reason: 'never ask at launch');
      expect(count('zonedSchedule'), 0, reason: 'nothing scheduled before permission was asked');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_asked'), isNull);
    });

    test('after the friendly moment: asks exactly once, then schedules', () async {
      final m = NotificationManager.instance;
      await m.init();
      await m.maybeAskPermission();
      expect(count('requestNotificationsPermission'), 1);
      expect(count('zonedSchedule'), greaterThanOrEqualTo(2), reason: 'daily + comeback at least');
      await m.maybeAskPermission(); // a second friendly moment
      expect(count('requestNotificationsPermission'), 1, reason: 'only ever asked once');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_asked'), isTrue);
    });

    test('Settings toggle off cancels everything and schedules nothing; back on asks only if never asked', () async {
      final m = NotificationManager.instance;
      await m.init();
      await m.maybeAskPermission();
      calls.clear();
      await m.setEnabled(false);
      expect(calls.where((c) => c.startsWith('cancel')).length, greaterThanOrEqualTo(1), reason: '$calls');
      expect(count('zonedSchedule'), 0);
      await m.reschedule(backgrounding: true);
      expect(count('zonedSchedule'), 0, reason: 'stays silent while off, even when backgrounding');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('notif_enabled'), isFalse);
      // Persisted: a restart is still off and still schedules nothing.
      await m.init();
      expect(m.enabled, isFalse);
      calls.clear();
      await m.reschedule();
      expect(count('zonedSchedule'), 0);
      expect(await (() async {
        await m.maybeAskPermission();
        return count('requestNotificationsPermission');
      })(), 0, reason: 'disabled players are not prompted');
    });

    test('the toggle is on by default and survives a missing platform plugin', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(notif, null);
      final m = NotificationManager.instance;
      SharedPreferences.setMockInitialValues({});
      await m.init(); // initialize() throws MissingPluginException: must not crash
      expect(m.enabled, isTrue);
      await m.reschedule();
      await m.maybeAskPermission();
      await m.setEnabled(false);
      await m.setEnabled(true);
    });
  });
}
