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
  List<Video> videos = [];
  String lastBookId = '';
  String developerName = '';
  String developerUrl = '';

  Set<String> favorites = {};
  ThemeMode themeMode = ThemeMode.system;
  double fontScale = 1.0;
  bool dailyNotification = true;
  int notifyHour = 8;
  int notifyMinute = 0;

  /// '' = system font, 'Amiri', 'ReemKufi'.
  String fontFamily = 'Amiri';

  /// Text size inside an answer (pinch to zoom).
  double readingScale = 1.0;

  /// Color theme: 'green' (green & gold), 'black' (black & gold), 'paper'.
  String palette = 'teal';

  /// Answers opened, per month: {'2026-11': {'id1', 'id2'}}.
  Map<String, Set<String>> readLog = {};

  Set<String> readLater = {};
  List<String> recentSearches = [];

  Future<void> load(SharedPreferences prefs) async {
    _prefs = prefs;

    final ch = jsonDecode(await rootBundle.loadString('assets/data/chapters.json')) as List;
    chapters = ch.map((e) => Chapter.fromJson(e as Map<String, dynamic>)).toList();
    _baseChapters = List.of(chapters);

    final fw = jsonDecode(await rootBundle.loadString('assets/data/fatwas.json')) as List;
    fatwas = fw.map((e) => Fatwa.fromJson(e as Map<String, dynamic>)).toList();
    for (final f in fatwas) {
      _index(f);
    }
    _bundled = List.of(fatwas);

    final bk = jsonDecode(await rootBundle.loadString('assets/data/books.json')) as List;
    books = bk.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();

    try {
      final cp = jsonDecode(await rootBundle.loadString('assets/data/channel.json')) as List;
      channel = cp.map((e) => ChannelPost.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      channel = [];
    }
    // Channel posts that became answers/articles appear in «من قناة الشيخ» too.
    channel = [
      ...channel,
      for (final f in fatwas)
        if (f.id.startsWith('tg-') && int.tryParse(f.id.substring(3)) != null)
          ChannelPost(
            id: int.parse(f.id.substring(3)),
            text: f.question.isEmpty ? f.answer : '${f.question}\n\nالجواب:\n${f.answer}',
            date: f.date,
            fatwaId: f.id,
          ),
    ]..sort((a, b) => b.id.compareTo(a.id));

    try {
      final vd = jsonDecode(await rootBundle.loadString('assets/data/videos.json')) as List;
      videos = vd.map((e) => Video.fromJson(e as Map<String, dynamic>)).toList();
      _fetchedVideos = videos;
    } catch (_) {
      videos = [];
    }
    lastBookId = prefs.getString('lastBookId') ?? '';

    final ln = jsonDecode(await rootBundle.loadString('assets/data/links.json')) as Map<String, dynamic>;
    sheikhLinks = ((ln['sheikh'] ?? []) as List)
        .map((e) => SocialLink.fromJson(e as Map<String, dynamic>))
        .toList();
    final dev = (ln['developer'] ?? {}) as Map<String, dynamic>;
    developerName = (dev['name'] ?? '') as String;
    developerUrl = (dev['url'] ?? '') as String;

    favorites = (prefs.getStringList('favorites') ?? []).toSet();
    try {
      final raw = jsonDecode(prefs.getString('folders') ?? '{}') as Map<String, dynamic>;
      folders = raw.map((k, v) => MapEntry(k, (v as List).map((e) => '$e').toList()));
    } catch (_) {
      folders = {};
    }
    themeMode = ThemeMode.values[prefs.getInt('themeMode') ?? ThemeMode.system.index];
    fontScale = prefs.getDouble('fontScale') ?? 1.0;
    dailyNotification = prefs.getBool('dailyNotification') ?? true;
    notifyHour = prefs.getInt('notifyHour') ?? 8;
    notifyMinute = prefs.getInt('notifyMinute') ?? 0;
    fontFamily = prefs.getString('fontFamily') ?? 'Amiri';
    readingScale = prefs.getDouble('readingScale') ?? 1.0;
    readLater = (prefs.getStringList('readLater') ?? []).toSet();
    palette = prefs.getString('palette') ?? 'teal';
    try {
      final raw = jsonDecode(prefs.getString('readLog') ?? '{}') as Map<String, dynamic>;
      readLog = raw.map((k, v) => MapEntry(k, (v as List).map((e) => '$e').toSet()));
    } catch (_) {
      readLog = {};
    }
    recentSearches = prefs.getStringList('recentSearches') ?? [];
  }

  late List<Fatwa> _bundled;

  /// Called after saved lists change (to sync with the signed-in account).
  static VoidCallback? onSavedListsChanged;

  void _index(Fatwa f) {
    f.searchText = normalizeArabic(
        '${f.title} ${f.question} ${f.answer} ${f.tags.join(' ')} ${chapterName(f.chapter)}');
  }

  /// Merges answers published from inside the app and edited titles.
  void applyRemote(List<Fatwa> published, Map<String, Map<String, dynamic>> edits) {
    final all = [..._bundled, ...published];
    final known = {for (final c in chapters) c.id};
    for (final f in all) {
      final e = edits[f.id];
      if (e != null) {
        final t = '${e['title'] ?? ''}';
        if (t.isNotEmpty) f.title = t;
        final c = '${e['chapter'] ?? ''}';
        if (c.isNotEmpty && known.contains(c)) f.chapter = c;
        if (e['sub'] != null) f.sub = '${e['sub']}';
      }
      _index(f);
    }
    fatwas = all;
    notifyListeners();
  }

  List<Chapter> _baseChapters = [];

  /// Renamed chapters and chapters added from the admin panel.
  void applyChapterConfig(List<Chapter> extra, Map<String, String> names) {
    chapters = [
      for (final c in [..._baseChapters, ...extra])
        Chapter(id: c.id, name: (names[c.id] ?? '').isNotEmpty ? names[c.id]! : c.name, icon: c.icon),
    ];
    for (final f in fatwas) {
      _index(f);
    }
    notifyListeners();
  }

  bool isBaseChapter(String id) => _baseChapters.any((c) => c.id == id);

  void setSheikhLinks(List<SocialLink> links) {
    sheikhLinks = links;
    notifyListeners();
  }

  /// Answers that look like the text of a question being typed.
  List<Fatwa> similarToText(String text, {int limit = 3}) {
    final words = normalizeArabic(text)
        .split(RegExp(r'[^\p{L}]+', unicode: true))
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .map((w) => w.startsWith('ال') && w.length > 4 ? w.substring(2) : w)
        .toSet();
    if (words.isEmpty) return [];
    final scored = <(Fatwa, int)>[];
    for (final f in fatwas) {
      final n = _keywords(f).intersection(words).length;
      if (n >= (words.length >= 3 ? 2 : 1)) scored.add((f, n));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(limit).map((e) => e.$1).toList();
  }

  void setLastBook(String id) {
    lastBookId = id;
    _prefs.setString('lastBookId', id);
    notifyListeners();
  }

  Book? get lastBook {
    for (final b in books) {
      if (b.id == lastBookId) return b;
    }
    return null;
  }

  void setBooks(List<Book> list) {
    books = list;
    notifyListeners();
  }

  void replaceSavedLists(Set<String> favs, Set<String> later) {
    favorites = favs;
    readLater = later;
    _prefs.setStringList('favorites', favorites.toList());
    _prefs.setStringList('readLater', readLater.toList());
    notifyListeners();
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
  List<Video> _fetchedVideos = [];

  void setExtraVideos(List<Video> extra) {
    final ids = {for (final v in extra) v.id};
    videos = [...extra, ..._fetchedVideos.where((v) => !ids.contains(v.id))];
    notifyListeners();
  }

  /// Posts from the sheikh's Telegram channel (newest first).
  List<ChannelPost> channel = [];

  List<ChannelPost> searchChannel(String query) {
    final words = normalizeArabic(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return channel;
    return channel.where((p) => words.every(p.searchText.contains)).toList();
  }

  /// Words that mean the same thing for search, e.g. الحواجب → النمص.
  /// Built-in pairs plus those the staff add from the admin panel.
  static const _builtinSynonyms = <String, List<String>>{
    'الحواجب': ['النمص'],
    'الحاجب': ['النمص'],
    'نتف': ['النمص'],
    'الاغاني': ['الغناء', 'المعازف'],
    'الموسيقي': ['المعازف', 'الغناء'],
    'الدخان': ['التدخين'],
    'السجاير': ['التدخين'],
    'الشمه': ['التدخين'],
    'القات': ['القات'],
    'الربا': ['الفوائد', 'الربا'],
    'البنك': ['الربا', 'البنوك'],
    'الطلاق': ['الطلاق'],
    'الحيض': ['الحيض', 'الدوره'],
    'الدوره': ['الحيض'],
  };
  Map<String, List<String>> extraSynonyms = {};

  /// Every form a search word may take: itself plus its related words.
  List<String> _forms(String w) {
    final out = <String>{w};
    void add(Map<String, List<String>> m) {
      for (final e in m.entries) {
        final k = normalizeArabic(e.key);
        final vals = e.value.map(normalizeArabic).toList();
        if (k == w || (w.length > 3 && (k.contains(w) || w.contains(k)))) out.addAll(vals);
        if (vals.contains(w)) out.add(k);
      }
    }

    add(_builtinSynonyms);
    add(extraSynonyms);
    return out.where((e) => e.isNotEmpty).toList();
  }

  List<Fatwa> search(String query) {
    final words = normalizeArabic(query)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return [];
    var results = fatwas.where((f) => words.every(f.searchText.contains)).toList();
    if (results.isEmpty) {
      // Search by meaning: try the related words too.
      final forms = [for (final w in words) _forms(w)];
      results = fatwas.where((f) => forms.every((alts) => alts.any(f.searchText.contains))).toList();
    }
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

  void setNotifyTime(int hour, int minute) {
    notifyHour = hour;
    notifyMinute = minute;
    _prefs.setInt('notifyHour', hour);
    _prefs.setInt('notifyMinute', minute);
    notifyListeners();
  }

  void setFontFamily(String f) {
    fontFamily = f;
    _prefs.setString('fontFamily', f);
    notifyListeners();
  }

  /// Saved without notifying: pinch-zoom updates its own screen.
  void saveReadingScale(double v) {
    readingScale = v;
    _prefs.setDouble('readingScale', v);
  }

  void setPalette(String p) {
    palette = p;
    _prefs.setString('palette', p);
    notifyListeners();
  }

  static String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  void markRead(String id) {
    final key = _monthKey(DateTime.now());
    final set = readLog.putIfAbsent(key, () => <String>{});
    if (set.add(id)) {
      _prefs.setString('readLog', jsonEncode(readLog.map((k, v) => MapEntry(k, v.toList()))));
    }
  }

  int get readThisMonth => readLog[_monthKey(DateTime.now())]?.length ?? 0;

  Set<String> get everRead => readLog.values.expand((e) => e).toSet();

  /// A random answer the reader hasn't opened yet (or any, if all read).
  Fatwa? randomUnread() {
    if (fatwas.isEmpty) return null;
    final read = everRead;
    final pool = fatwas.where((f) => !read.contains(f.id)).toList();
    final list = pool.isEmpty ? fatwas : pool;
    return list[DateTime.now().microsecondsSinceEpoch % list.length];
  }

  /// Words to suggest while typing in search.
  List<String> suggestions(String query, List<String> extraTopics) {
    final q = normalizeArabic(query.trim());
    if (q.isEmpty) return [];
    final seen = <String>{};
    final out = <String>[];
    void consider(String w) {
      final n = normalizeArabic(w);
      if (n.length < 2 || n == q || !seen.add(n)) return;
      if (n.startsWith(q) || (n.startsWith('ال') && n.substring(2).startsWith(q))) out.add(w);
    }
    for (final t in extraTopics) {
      consider(t);
    }
    for (final c in chapters) {
      consider(c.name);
    }
    for (final f in fatwas) {
      for (final w in '${f.title} ${f.tags.join(' ')}'.split(RegExp(r'[^\p{L}]+', unicode: true))) {
        consider(w);
      }
      if (out.length > 12) break;
    }
    return out.take(6).toList();
  }

  // ---- Backup -----------------------------------------------------------
  String exportBackup() => jsonEncode({
        'app': 'ibn_alshabira',
        'favorites': favorites.toList(),
        'readLater': readLater.toList(),
        'recentSearches': recentSearches,
        'readLog': readLog.map((k, v) => MapEntry(k, v.toList())),
        'fontFamily': fontFamily,
        'palette': palette,
        'fontScale': fontScale,
        'readingScale': readingScale,
      });

  /// Returns false if the text isn't a valid backup.
  bool importBackup(String text) {
    try {
      final m = jsonDecode(text.trim()) as Map<String, dynamic>;
      if (m['app'] != 'ibn_alshabira') return false;
      favorites = ((m['favorites'] ?? []) as List).map((e) => '$e').toSet();
      readLater = ((m['readLater'] ?? []) as List).map((e) => '$e').toSet();
      recentSearches = ((m['recentSearches'] ?? []) as List).map((e) => '$e').toList();
      readLog = ((m['readLog'] ?? {}) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).map((e) => '$e').toSet()));
      fontFamily = (m['fontFamily'] ?? fontFamily) as String;
      palette = (m['palette'] ?? palette) as String;
      fontScale = ((m['fontScale'] ?? fontScale) as num).toDouble();
      readingScale = ((m['readingScale'] ?? readingScale) as num).toDouble();
      _prefs.setStringList('favorites', favorites.toList());
      _prefs.setStringList('readLater', readLater.toList());
      _prefs.setStringList('recentSearches', recentSearches);
      _prefs.setString('readLog', jsonEncode(readLog.map((k, v) => MapEntry(k, v.toList()))));
      _prefs.setString('fontFamily', fontFamily);
      _prefs.setString('palette', palette);
      _prefs.setDouble('fontScale', fontScale);
      _prefs.setDouble('readingScale', readingScale);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool isReadLater(String id) => readLater.contains(id);

  void toggleReadLater(String id) {
    if (!readLater.remove(id)) readLater.add(id);
    _prefs.setStringList('readLater', readLater.toList());
    notifyListeners();
    onSavedListsChanged?.call();
  }

  List<Fatwa> get readLaterFatwas => fatwas.where((f) => readLater.contains(f.id)).toList();

  void addRecentSearch(String q) {
    q = q.trim();
    if (q.length < 2) return;
    recentSearches.remove(q);
    recentSearches.insert(0, q);
    if (recentSearches.length > 10) recentSearches = recentSearches.sublist(0, 10);
    _prefs.setStringList('recentSearches', recentSearches);
    notifyListeners();
  }

  void clearRecentSearches() {
    recentSearches = [];
    _prefs.setStringList('recentSearches', recentSearches);
    notifyListeners();
  }

  void setDailyNotification(bool v) {
    dailyNotification = v;
    _prefs.setBool('dailyNotification', v);
    notifyListeners();
  }

  // ---- Folders of saved answers (named by the reader) -------------------
  Map<String, List<String>> folders = {};

  void _saveFolders() {
    _prefs.setString('folders', jsonEncode(folders));
    notifyListeners();
  }

  bool addFolder(String name) {
    final n = name.trim();
    if (n.isEmpty || folders.containsKey(n)) return false;
    folders[n] = [];
    _saveFolders();
    return true;
  }

  void deleteFolder(String name) {
    folders.remove(name);
    _saveFolders();
  }

  void toggleInFolder(String name, String id) {
    final list = folders.putIfAbsent(name, () => []);
    if (!list.remove(id)) list.add(id);
    _saveFolders();
  }

  List<Fatwa> folderFatwas(String name) {
    final ids = folders[name] ?? const [];
    return fatwas.where((f) => ids.contains(f.id)).toList();
  }

  List<Fatwa> byTag(String tag) => fatwas.where((f) => f.tags.contains(tag)).toList();

  bool isFavorite(String id) => favorites.contains(id);

  void toggleFavorite(String id) {
    if (!favorites.remove(id)) favorites.add(id);
    _prefs.setStringList('favorites', favorites.toList());
    notifyListeners();
    onSavedListsChanged?.call();
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
