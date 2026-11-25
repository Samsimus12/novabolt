/// Pure "what should be scheduled" logic for local reminders. No plugin, no
/// storage: everything comes in as arguments so it can be unit-tested.
library;

enum NotificationKind {
  daily(1),
  streak(2),
  missions(3),
  comeback(4);

  const NotificationKind(this.id);
  final int id;
}

class PlannedNotification {
  const PlannedNotification(this.kind, this.when, this.title, this.body);
  final NotificationKind kind;
  final DateTime when;
  final String title;
  final String body;

  int get id => kind.id;

  @override
  String toString() => '${kind.name}@$when "$title"';
}

class NotificationPlan {
  NotificationPlan._();

  static const dailyHour = 18; // 6 pm
  static const streakHour = 20; // 8 pm
  static const missionsDelay = Duration(hours: 2);
  static const comebackDelay = Duration(days: 3);

  /// Notifications that would land in this window are moved to [quietEndHour].
  static const quietStartHour = 22;
  static const quietEndHour = 10;

  /// Everything that should be pending right now. [now] is local time.
  /// [backgrounding] is true when the app is being put away (only then are
  /// "missions ready" scheduled, since while the app is open the player sees
  /// the badge themselves).
  static List<PlannedNotification> plan({
    required DateTime now,
    required bool enabled,
    required bool playedDailyToday,
    required int streak,
    required int claimableMissions,
    required bool backgrounding,
  }) {
    if (!enabled) return const [];
    final out = <PlannedNotification>[];

    // 1. Daily challenge reminder: today at 6 pm if still unplayed and still
    // ahead, otherwise tomorrow at 6 pm.
    final dailyToday = _at(now, 0, dailyHour);
    final dailyWhen = !playedDailyToday && dailyToday.isAfter(now) ? dailyToday : _at(now, 1, dailyHour);
    out.add(PlannedNotification(
      NotificationKind.daily,
      dailyWhen,
      'Daily challenge is live',
      'Two fresh rules, double NOVA. Got a few minutes?',
    ));

    // 2. Streak at risk. Played today: remind tomorrow evening. Not played:
    // only if 8 pm is still ahead (after that the streak is a lost cause).
    if (streak > 0) {
      final streakToday = _at(now, 0, streakHour);
      DateTime? when;
      if (playedDailyToday) {
        when = _at(now, 1, streakHour);
      } else if (streakToday.isAfter(now)) {
        when = streakToday;
      }
      if (when != null) {
        out.add(PlannedNotification(
          NotificationKind.streak,
          when,
          'Your $streak-day streak is on the line',
          'One daily run and it stays alive. Go go go!',
        ));
      }
    }

    // 3. Missions ready, about 2 hours after the app is put away.
    if (backgrounding && claimableMissions > 0) {
      out.add(PlannedNotification(
        NotificationKind.missions,
        _quiet(now.add(missionsDelay)),
        claimableMissions == 1 ? 'A mission is ready' : '$claimableMissions missions are ready',
        'NOVA is waiting to be claimed.',
      ));
    }

    // 4. Comeback nudge: three days after the last open/background.
    out.add(PlannedNotification(
      NotificationKind.comeback,
      _quiet(now.add(comebackDelay)),
      'Pilot, the galaxy misses you',
      'The bosses have been practicing. Come back and show them.',
    ));

    return out;
  }

  static DateTime _at(DateTime now, int addDays, int hour) =>
      DateTime(now.year, now.month, now.day + addDays, hour);

  /// Pushes a time out of the night (10 pm to 10 am) to 10 am.
  static DateTime _quiet(DateTime t) {
    if (t.hour >= quietStartHour) return DateTime(t.year, t.month, t.day + 1, quietEndHour);
    if (t.hour < quietEndHour) return DateTime(t.year, t.month, t.day, quietEndHour);
    return t;
  }
}
