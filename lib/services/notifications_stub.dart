class AppAlerts {
  static Future<void> show(String title, String body) async {}
}

class DailyNotifications {
  static Future<void> init() async {}
  static Future<void> setEnabled(bool enabled, {int hour = 8, int minute = 0}) async {}
}
