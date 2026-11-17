import 'package:shared_preferences/shared_preferences.dart';

import '../data/hijri.dart';
import 'cloud.dart';
import 'notifications.dart';

/// «تذكيرات السنن» and lesson reminders, set on the phone itself (no server).
/// Sunnah reminders work only when the sheikh turned them on; each reader
/// can still turn them off for himself.
class Reminders {
  static const kinds = <String, (String, String)>{
    'kahf': ('سورة الكهف', 'اليوم الجمعة: لا تنسَ قراءة سورة الكهف، والإكثار من الصلاة على النبي ﷺ.'),
    'monthu': ('صيام الاثنين والخميس', 'غداً يُستحب صيامه، تذكير بصيام الاثنين والخميس.'),
    'white': ('الأيام البيض', 'تبدأ غداً الأيام البيض (13 و14 و15 من الشهر الهجري)، تذكير بصيامها.'),
    'arafah': ('يوم عرفة', 'غداً يوم عرفة، تذكير بصيامه لغير الحاج.'),
    'ashura': ('عاشوراء', 'تذكير بصيام يوم عاشوراء ويوم قبله.'),
  };

  static String textOf(String k) {
    final t = Cloud.instance.sunanTexts[k]?.trim() ?? '';
    return t.isNotEmpty ? t : kinds[k]!.$2;
  }

  static Future<bool> userOn() async => (await SharedPreferences.getInstance()).getBool('sunanMine') ?? true;
  static Future<void> setUserOn(bool v) async {
    await (await SharedPreferences.getInstance()).setBool('sunanMine', v);
    await schedule();
  }

  /// Sets the next 40 days of reminders (ids 400–439). Called at start.
  static Future<void> schedule() async {
    final on = Cloud.instance.sunanOn && await userOn();
    final items = <(DateTime, String, String)>[];
    if (on) {
      final today = DateTime.now();
      for (var d = 0; d < 40; d++) {
        final day = DateTime(today.year, today.month, today.day).add(Duration(days: d));
        final next = day.add(const Duration(days: 1));
        final h = Hijri.from(next);
        if (day.weekday == DateTime.friday) items.add((day.add(const Duration(hours: 9)), kinds['kahf']!.$1, textOf('kahf')));
        // The evening before Monday and Thursday.
        if (day.weekday == DateTime.sunday || day.weekday == DateTime.wednesday) {
          items.add((day.add(const Duration(hours: 20)), kinds['monthu']!.$1, textOf('monthu')));
        }
        if (h.day == 13 && h.month != 12) items.add((day.add(const Duration(hours: 20)), kinds['white']!.$1, textOf('white')));
        if (h.month == 12 && h.day == 9) items.add((day.add(const Duration(hours: 20)), kinds['arafah']!.$1, textOf('arafah')));
        if (h.month == 1 && h.day == 9) items.add((day.add(const Duration(hours: 20)), kinds['ashura']!.$1, textOf('ashura')));
      }
    }
    await OnceNotifications.replace(400, 40, items);
  }

  // --------------------------------------------------- lesson reminders
  static Future<Set<String>> lessonsAsked() async =>
      ((await SharedPreferences.getInstance()).getStringList('lessonRemind') ?? const []).toSet();

  static Future<void> toggleLesson(String key) async {
    final p = await SharedPreferences.getInstance();
    final s = (p.getStringList('lessonRemind') ?? const []).toSet();
    s.contains(key) ? s.remove(key) : s.add(key);
    await p.setStringList('lessonRemind', s.toList());
    await scheduleLessons();
  }

  /// A reminder 30 minutes before each lesson the reader asked for, for the
  /// next four weeks (ids 450–489).
  static Future<void> scheduleLessons() async {
    final asked = await lessonsAsked();
    final items = <(DateTime, String, String)>[];
    if (Cloud.instance.timetableOn) {
      final now = DateTime.now();
      for (final m in Cloud.instance.timetable) {
        final key = lessonKey(m);
        if (!asked.contains(key)) continue;
        final wd = (m['day'] as num?)?.toInt() ?? 0; // 1 Monday .. 7 Sunday
        final parts = '${m['time'] ?? '00:00'}'.split(':');
        final hh = int.tryParse(parts[0]) ?? 0, mm = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        for (var d = 0; d < 28; d++) {
          final day = DateTime(now.year, now.month, now.day).add(Duration(days: d));
          if (day.weekday != wd) continue;
          final at = DateTime(day.year, day.month, day.day, hh, mm).subtract(const Duration(minutes: 30));
          items.add((at, 'بعد نصف ساعة: ${m['title'] ?? 'درس الشيخ'}', '${m['place'] ?? ''}'));
        }
      }
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    await OnceNotifications.replace(450, 40, items);
  }

  static String lessonKey(Map<String, dynamic> m) => '${m['day']}|${m['time']}|${m['title']}';
}
