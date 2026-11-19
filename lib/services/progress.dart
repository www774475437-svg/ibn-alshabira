import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import 'challenge.dart';
import 'quiz.dart';

/// One total of points for everything a reader does (reading, listening,
/// the quiz, challenges, memorizing), and the badges he earned. Worked out
/// on the phone; sent once a day inside the quiz record (one write).
class Progress {
  static int listens = 0;
  static int hifzPages = 0;
  static int listenSeconds = 0;
  static int finishedBooks = 0;
  static Map<String, dynamic>? daily; // today's «تحدّي اليوم» result

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    listens = p.getInt('listens') ?? 0;
    listenSeconds = p.getInt('listenSeconds') ?? 0;
    // A book is finished when the reader reached its last pages.
    var done = 0;
    for (final k in p.getKeys().where((k) => k.startsWith('book_pages_'))) {
      final pages = p.getInt(k) ?? 0;
      final page = p.getInt('book_page_${k.substring(11)}') ?? 0;
      if (pages > 5 && page >= pages - 1) done++;
    }
    finishedBooks = done;
    try {
      final d = p.getString('dailyChallenge');
      daily = d == null ? null : Map<String, dynamic>.from(jsonDecode(d) as Map);
    } catch (_) {}
    try {
      hifzPages = (jsonDecode(p.getString('hifz') ?? '{}') as Map).length;
    } catch (_) {
      hifzPages = 0;
    }
  }

  /// Time spent listening (counted while a recording plays).
  static Future<void> addListen(int seconds) async {
    final p = await SharedPreferences.getInstance();
    listenSeconds = (p.getInt('listenSeconds') ?? 0) + seconds;
    await p.setInt('listenSeconds', listenSeconds);
  }

  /// «مبتدئ ← طالب علم ← متقدّم ← متمكّن», by points.
  static String rankOf(int pts) => pts >= 3000
      ? 'متمكّن'
      : pts >= 1000
          ? 'متقدّم'
          : pts >= 200
              ? 'طالب علم'
              : 'مبتدئ';

  static String get rank => rankOf(points);

  /// A recording started playing.
  static Future<void> listened() async {
    final p = await SharedPreferences.getInstance();
    listens = (p.getInt('listens') ?? 0) + 1;
    await p.setInt('listens', listens);
  }

  static int get reads => Repository.instance.everRead.length;

  /// (what, how many, points)
  static List<(String, int, int)> get parts {
    final q = Quiz.instance, ch = Challenges.instance;
    return [
      ('الأجوبة المقروءة', reads, reads * 2),
      ('التسجيلات المسموعة', listens, listens * 2),
      ('نقاط الأسئلة', q.right, q.score),
      ('الفوز في التحديات', ch.wins, ch.wins * 20),
      ('صفحات الحفظ', hifzPages, hifzPages * 3),
      ('أيام القراءة المتتالية', Repository.instance.streak, Repository.instance.streak * 5),
    ];
  }

  static int get points => parts.fold(0, (a, b) => a + b.$3);

  /// (id, title, icon, earned)
  static List<(String, String, IconData, bool)> get badges {
    final repo = Repository.instance, q = Quiz.instance, ch = Challenges.instance;
    final done = <String>[];
    for (final c in repo.chapters) {
      final all = repo.byChapter(c.id);
      if (all.length >= 5 && all.every((f) => repo.everRead.contains(f.id))) done.add(c.name);
    }
    return [
      ('r10', 'قارئ مبتدئ (10 أجوبة)', Icons.menu_book_outlined, reads >= 10),
      ('r100', 'قارئ نشيط (100 جواب)', Icons.auto_stories, reads >= 100),
      ('r500', 'قارئ متمكّن (500 جواب)', Icons.workspace_premium, reads >= 500),
      for (final n in done) ('c:$n', 'أتمّ باب $n', Icons.verified, true),
      ('l10', 'مستمع (10 تسجيلات)', Icons.headphones, listens >= 10),
      ('q50', 'مجيب (50 إجابة صحيحة)', Icons.quiz, q.right >= 50),
      ('w1', 'أول فوز في تحدٍّ', Icons.emoji_events_outlined, ch.wins >= 1),
      ('w10', 'بطل التحديات (10 انتصارات)', Icons.emoji_events, ch.wins >= 10),
      // The days in a row: a badge at each step.
      for (final d in const [7, 30, 60, 90, 120, 360])
        ('s$d', 'مواظب ($d يوماً متتالية)', Icons.local_fire_department, repo.streak >= d),
      ('b1', 'ختم كتاباً من كتب الشيخ', Icons.menu_book, finishedBooks >= 1),
      ('b5', 'ختم 5 كتب من كتب الشيخ', Icons.library_books, finishedBooks >= 5),
      ('lh5', 'مستمع (5 ساعات استماع)', Icons.headset, listenSeconds >= 5 * 3600),
      ('lh20', 'مستمع مواظب (20 ساعة استماع)', Icons.headset_mic, listenSeconds >= 20 * 3600),
      ('h20', 'حافظ (20 صفحة)', Icons.psychology, hifzPages >= 20),
    ];
  }

  static List<String> get earnedIds => [for (final b in badges) if (b.$4) b.$1];

  /// What goes into the public profile (the quiz record), once a day.
  static Map<String, dynamic> get public => {
        'pts': points,
        'reads': reads,
        'listens': listens,
        'hifz': hifzPages,
        'days': Repository.instance.streak,
        // This month's reading (for «سباق القراءة» among those one follows).
        'rm': Repository.instance.readThisMonth,
        'mk': '${DateTime.now().year}-${DateTime.now().month}',
        if (daily != null) 'dc': daily,
        'badges': [for (final b in badges) if (b.$4) b.$2],
      };
}
