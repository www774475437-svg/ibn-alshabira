import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import 'quiz.dart';
import 'tour.dart';

/// The home-screen widgets (Android): «جواب اليوم», «ذِكر», «قراءتي»,
/// «سؤال اليوم», «بطولة الجمعة» (and the prayer-times one, in prayer.dart).
/// The app writes their text on the phone; nothing is read from the server
/// for them.
class HomeWidgets {
  static const _ch = MethodChannel('ibn_alshabira/icon');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const kinds = [
    ('prayer', 'مواقيت الصلاة', 'الصلاة القادمة وعدّاد لها، وسماء تتغيّر مع الوقت'),
    ('answer', 'جواب اليوم', 'جواب جديد من أجوبة الشيخ كل يوم'),
    ('dhikr', 'ذِكر', 'ذِكر قصير يتجدّد كل يوم، ويفتح الأذكار'),
    ('read', 'قراءتي هذا الشهر', 'كم قرأت من هدفك هذا الشهر'),
    ('quiz', 'سؤال اليوم', 'سؤال من أسئلة كتب الشيخ كل يوم'),
    ('tour', 'بطولة الجمعة', 'موعد البطولة القادمة مع عدّاد تنازلي'),
  ];

  static const _adhkar = [
    'سبحان الله وبحمده، سبحان الله العظيم',
    'لا إله إلا الله وحده لا شريك له، له الملك وله الحمد، وهو على كل شيء قدير',
    'لا حول ولا قوة إلا بالله',
    'سبحان الله، والحمد لله، ولا إله إلا الله، والله أكبر',
    'أستغفر الله وأتوب إليه',
    'رضيت بالله ربًّا، وبالإسلام دينًا، وبمحمد ﷺ نبيًّا',
    'حسبي الله لا إله إلا هو، عليه توكلت، وهو رب العرش العظيم',
    'يا حي يا قيوم برحمتك أستغيث، أصلح لي شأني كله، ولا تكلني إلى نفسي طرفة عين',
    'اللهم إني أسألك العفو والعافية في الدنيا والآخرة',
    'اللهم صلِّ وسلم على نبينا محمد',
  ];

  static int get _day {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).difference(DateTime(2024)).inDays;
  }

  static String _short(String s, int n) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= n ? t : '${t.substring(0, n).trim()}…';
  }

  /// Writes all the widgets' text (cheap; called at start and on resume).
  static Future<void> push() async {
    if (!supported) return;
    try {
      final repo = Repository.instance;
      final data = <String, Object>{};
      // جواب اليوم
      final list = repo.fatwas.where((f) => f.answer.trim().length > 40).toList();
      if (list.isNotEmpty) {
        final f = list[(_day * 7919) % list.length];
        data['answer_title'] = _short(f.title, 90);
        data['answer_body'] = _short(f.answer, 220);
        data['answer_open'] = 'answer:${f.id}';
      }
      // ذِكر
      final h = DateTime.now().hour;
      data['dhikr_title'] = _adhkar[_day % _adhkar.length];
      data['dhikr_body'] = '';
      data['dhikr_label'] = h < 12 ? 'ذِكر الصباح' : 'ذِكر المساء';
      data['dhikr_foot'] = h < 12 ? 'اضغط لأذكار الصباح' : 'اضغط لأذكار المساء';
      // قراءتي
      final p = await SharedPreferences.getInstance();
      final goal = p.getInt('monthGoal') ?? 30;
      final n = repo.readThisMonth;
      data['read_title'] = '$n من $goal';
      data['read_body'] = n == 0
          ? 'ابدأ اليوم بجواب واحد'
          : n >= goal
              ? 'أتممتَ هدفك هذا الشهر، بارك الله فيك'
              : 'بقي ${goal - n} لتتمّ هدفك';
      // سؤال اليوم
      final qs = Quiz.instance.live.where((q) => q.choices.length >= 2).toList();
      if (qs.isNotEmpty) {
        final q = qs[(_day * 104729) % qs.length];
        data['quiz_title'] = _short(q.text, 110);
        data['quiz_body'] = q.choices.map((c) => '• ${_short(c, 40)}').join('\n');
        data['quiz_foot'] = 'اضغط لتجيب';
      }
      // بطولة الجمعة
      final t = Tour.instance;
      final start = Tour.nextStart();
      if (t.showCard) {
        data['tour_title'] = Tour.arabicDate(Tour.keyOf(start));
        data['tour_body'] = 'الساعة 9 مساءً بتوقيت مكة · تبدأ بعد';
        data['tour_at'] = start.millisecondsSinceEpoch;
      } else {
        data['tour_title'] = 'لا بطولة معلنة الآن';
        data['tour_body'] = 'تظهر هنا البطولة القادمة حين تُعلن';
        data['tour_at'] = 0;
      }
      await _ch.invokeMethod('widgets', data);
    } catch (_) {}
  }

  /// A widget the reader tapped: which page to open (once).
  static Future<String?> takeLaunch() async {
    if (!supported) return null;
    try {
      return await _ch.invokeMethod<String>('takeLaunch');
    } catch (_) {
      return null;
    }
  }

  /// Asks the phone to put a widget on the home screen.
  static Future<bool> pin(String kind) async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('pinWidget', kind) ?? false;
    } catch (_) {
      return false;
    }
  }
}
