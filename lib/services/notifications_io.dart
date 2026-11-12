import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class DailyNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static const _id = 1;
  static const _hour = 8; // 8 AM on the phone's clock

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

  static Future<void> setEnabled(bool enabled) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(_id);
      if (!enabled) return;

      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, _hour);
      if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
      final when = tz.TZDateTime.from(next, tz.UTC);

      await _plugin.zonedSchedule(
        _id,
        'فتوى اليوم',
        'افتح تطبيق «ابن الشابرة» واقرأ فتوى اليوم',
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_fatwa',
            'فتوى اليوم',
            channelDescription: 'تنبيه يومي بفتوى اليوم',
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
