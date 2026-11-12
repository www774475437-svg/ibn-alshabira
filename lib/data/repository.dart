import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

final _tashkeel = RegExp(r'[ؐ-ًؚ-ٰٟۖ-ۭـ]');

/// Makes Arabic search forgiving: drops tashkeel and tatweel,
/// unifies alef / ya / ta marbuta / hamza forms.
String normalizeArabic(String s) {
  return s
      .replaceAll(_tashkeel, '')
      .replaceAll(RegExp('[إأآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .toLowerCase();
}

class Repository extends ChangeNotifier {
  Repository._();
  static final Repository instance = Repository._();

  late SharedPreferences _prefs;

  List<Chapter> chapters = [];
  List<Fatwa> fatwas = [];
  List<Book> books = [];
  List<SocialLink> sheikhLinks = [];
  String developerName = '';
  String developerUrl = '';

  Set<String> favorites = {};
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1.0;
  bool dailyNotification = true;

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;

    final ch = jsonDecode(await rootBundle.loadString('assets/data/chapters.json')) as List;
    chapters = ch.map((e) => Chapter.fromJson(e as Map<String, dynamic>)).toList();

    final fw = jsonDecode(await rootBundle.loadString('assets/data/fatwas.json')) as List;
    fatwas = fw.map((e) => Fatwa.fromJson(e as Map<String, dynamic>)).toList();
    for (final f in fatwas) {
      f.searchText = normalizeArabic(
          '${f.title} ${f.question} ${f.answer} ${f.tags.join(' ')} ${chapterName(f.chapter)}');
    }

    final bk = jsonDecode(await rootBundle.loadString('assets/data/books.json')) as List;
    books = bk.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();

    final ln = jsonDecode(await rootBundle.loadString('assets/data/links.json')) as Map<String, dynamic>;
    sheikhLinks = ((ln['sheikh'] ?? []) as List)
        .map((e) => SocialLink.fromJson(e as Map<String, dynamic>))
        .toList();
    final dev = (ln['developer'] ?? {}) as Map<String, dynamic>;
    developerName = (dev['name'] ?? '') as String;
    developerUrl = (dev['url'] ?? '') as String;

    favorites = (prefs.getStringList('favorites') ?? []).toSet();
    themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? ThemeMode.system.index];
    fontScale = prefs.getDouble('fontScale') ?? 1.0;
    dailyNotification = prefs.getBool('dailyNotification') ?? true;
  }

  String chapterName(String id) {
    for (final c in chapters) {
      if (c.id == id) return c.name;
    }
    return 'متفرقات';
  }

  List<Fatwa> byChapter(String id) => fatwas.where((f) => f.chapter == id).toList();

  int countInChapter(String id) => fatwas.where((f) => f.chapter == id).length;

  /// Every word of the query must appear (in any order).
  List<Fatwa> search(String query) {
    final words = normalizeArabic(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return [];
    final results = fatwas.where((f) => words.every(f.searchText.contains)).toList();
    // Title matches first.
    results.sort((a, b) {
      final at = words.every(normalizeArabic(a.title).contains) ? 0 : 1;
      final bt = words.every(normalizeArabic(b.title).contains) ? 0 : 1;
      return at.compareTo(bt);
    });
    return results;
  }

  Fatwa? findById(String id) {
    for (final f in fatwas) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// One fatwa per day, the same for everyone, changing at midnight.
  Fatwa? get fatwaOfDay {
    final pool = fatwas.where((f) => f.type == 'fatwa').toList();
    final list = pool.isEmpty ? fatwas : pool;
    if (list.isEmpty) return null;
    final now = DateTime.now();
    final day = DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 86400000;
    return list[day % list.length];
  }

  static final _stopWords = {
    'ما', 'حكم', 'في', 'من', 'علي', 'الي', 'عن', 'هل', 'او', 'ان', 'لا', 'مع', 'هذا', 'هذه',
    'التي', 'الذي', 'ذلك', 'يجوز', 'السوال', 'الجواب', 'كان', 'اذا', 'قد', 'به', 'بها', 'له', 'لها',
  };

  Set<String> _keywords(Fatwa f) => normalizeArabic('${f.title} ${f.question} ${f.tags.join(' ')}')
      .split(RegExp(r'[^\p{L}]+', unicode: true))
      .where((w) => w.length > 2 && !_stopWords.contains(w))
      .map((w) => w.startsWith('ال') && w.length > 4 ? w.substring(2) : w)
      .toSet();

  /// Fatwas on the same topic: shared keywords first, then the same chapter.
  List<Fatwa> related(Fatwa f, {int limit = 5}) {
    final mine = _keywords(f);
    final scored = <(Fatwa, int)>[];
    for (final o in fatwas) {
      if (o.id == f.id) continue;
      var score = _keywords(o).intersection(mine).length * 3;
      if (o.chapter == f.chapter) score += 1;
      if (score > 0) scored.add((o, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  void setDailyNotification(bool v) {
    dailyNotification = v;
    _prefs.setBool('dailyNotification', v);
    notifyListeners();
  }

  bool isFavorite(String id) => favorites.contains(id);

  void toggleFavorite(String id) {
    if (!favorites.remove(id)) favorites.add(id);
    _prefs.setStringList('favorites', favorites.toList());
    notifyListeners();
  }

  List<Fatwa> get favoriteFatwas => fatwas.where((f) => favorites.contains(f.id)).toList();

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  void setFontScale(double v) {
    fontScale = v;
    _prefs.setDouble('fontScale', v);
    notifyListeners();
  }

  bool get onboarded => _prefs.getBool('onboarded') ?? false;

  void setOnboarded() => _prefs.setBool('onboarded', true);
}
