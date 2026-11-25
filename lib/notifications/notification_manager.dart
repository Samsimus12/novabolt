import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../game/data/daily_challenge.dart';
import '../stats/mission_manager.dart';
import 'notification_planner.dart';

/// Local reminders (no server, no push). Everything pending is canceled and
/// re-planned each time the app opens or goes to the background; what to
/// schedule is decided by [NotificationPlan].
class NotificationManager {
  NotificationManager._();
  static final instance = NotificationManager._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _enabled = true;
  bool _asked = false;

  /// The Settings toggle (on by default; nothing is shown until the player
  /// has also allowed notifications in the system prompt).
  bool get enabled => _enabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('notif_enabled') ?? true;
    _asked = prefs.getBool('notif_asked') ?? false;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          // Permission is requested later, at a friendly moment.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_enabled', v);
    if (v) await requestPermission();
    await reschedule();
  }

  /// Shows the system permission prompt, once, if the player hasn't been
  /// asked yet. Call it at a friendly moment (first finished run, first time
  /// the daily card is opened), never at launch.
  Future<void> maybeAskPermission() async {
    if (_asked || !_enabled) return;
    await requestPermission();
    await reschedule();
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    _asked = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_asked', true);
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true, badge: false);
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Notification permission failed: $e');
    }
  }

  /// Replaces everything pending with what [NotificationPlan] says is due now.
  /// Does nothing until permission has been asked (nothing could show anyway).
  Future<void> reschedule({bool backgrounding = false}) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      if (!_asked) return;
      final daily = DailyManager.instance;
      final plan = NotificationPlan.plan(
        now: DateTime.now(),
        enabled: _enabled,
        playedDailyToday: daily.playedToday,
        streak: daily.streak,
        claimableMissions: MissionManager.instance.claimableCount,
        backgrounding: backgrounding,
      );
      for (final n in plan) {
        await _plugin.zonedSchedule(
          id: n.id,
          title: n.title,
          body: n.body,
          scheduledDate: tz.TZDateTime.from(n.when, tz.local),
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(),
            android: AndroidNotificationDetails('reminders', 'Reminders',
                channelDescription: 'Daily challenge, streak and mission reminders'),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Scheduling notifications failed: $e');
    }
  }
}
