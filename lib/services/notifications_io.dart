import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// One-off alerts (new question for staff, reply for the asker).
class AppAlerts {
  static int _n = 100;
  static bool _asked = false;
  static Future<void> show(String title, String body) async {
    if (!DailyNotifications._ready) return;
    try {
      if (!_asked) {
        _asked = true;
        await DailyNotifications._plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      await DailyNotifications._plugin.show(
        _n++,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'questions',
            'الأسئلة والأجوبة',
            channelDescription: 'تنبيه عند وصول سؤال جديد أو جواب سؤالك',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (_) {}
  }
}

class DailyNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _id = 1;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> setEnabled(bool enabled, {int hour = 8, int minute = 0}) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_id);
      if (!enabled) return;

      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, hour, minute);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      final when = tz.TZDateTime.from(next, tz.UTC);

      await _plugin.zonedSchedule(
        _id,
        'جواب اليوم',
        'افتح تطبيق «ابن الشابرة» واقرأ جواب اليوم',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_fatwa',
            'جواب اليوم',
            channelDescription: 'تنبيه يومي بجواب اليوم',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      // Never let a notification problem crash the app.
    }
  }
}

/// Morning and evening adhkar reminders, each switched on by the user himself.
class AdhkarNotifications {
  static Future<void> set(int id, bool enabled, int hour, int minute, String title) async {
    if (!DailyNotifications._ready) return;
    try {
      await DailyNotifications._plugin.cancel(id);
      if (!enabled) return;
      await DailyNotifications._plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, hour, minute);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      await DailyNotifications._plugin.zonedSchedule(
        id,
        title,
        'افتح الأذكار في تطبيق «ابن الشابرة»',
        tz.TZDateTime.from(next, tz.UTC),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'adhkar',
            'تذكير الأذكار',
            channelDescription: 'تذكير بأذكار الصباح والمساء في الوقت الذي تختاره',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }
}


/// Every few hours, even with the app closed, Android asks whether a newer
/// version is out; if so, one notification per version tells the reader.
@pragma('vm:entry-point')
void updateWatchDispatcher() {
  Workmanager().executeTask((task, input) async {
    await UpdateWatch.checkNow();
    return true;
  });
}

class UpdateWatch {
  static Future<void> start() async {
    if (AppConfig.buildNumber == 0 || AppConfig.fromPlay) return;
    try {
      await Workmanager().initialize(updateWatchDispatcher);
      await Workmanager().registerPeriodicTask(
        'ibn-alshabira-update-watch',
        'updateWatch',
        frequency: const Duration(hours: 3),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
      await DailyNotifications._plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static Future<void> checkNow() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.latestReleaseApi)).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final latest = int.tryParse('${j['tag_name'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (latest <= AppConfig.buildNumber) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt('updateNotified') == latest) return;
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await plugin.show(
        9,
        'تحديث جديد لتطبيق «ابن الشابرة» 🎉',
        'افتح التطبيق واضغط «يوجد تحديث جديد» لتحميل النسخة الجديدة',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'updates',
            'تحديثات التطبيق',
            channelDescription: 'إشعار عند نزول نسخة جديدة من التطبيق',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      await prefs.setInt('updateNotified', latest);
    } catch (_) {}
  }
}
