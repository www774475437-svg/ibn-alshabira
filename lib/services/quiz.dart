import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud.dart';
import 'ai.dart';
import 'day_log.dart';
import 'site_files.dart';

/// One category of questions (a button in «الأسئلة»), named by the sheikh.
class QuizCat {
  final String id;
  String name;
  String icon; // a key of chapterIcons
  int color; // ARGB
  int order;
  bool hidden;

  QuizCat({
    required this.id,
    required this.name,
    this.icon = 'i_library_books_outlined',
    this.color = 0xFF1F5E3B,
    this.order = 0,
    this.hidden = false,
  });

  factory QuizCat.fromMap(String id, Map<String, dynamic> m) => QuizCat(
        id: id,
        name: '${m['name'] ?? ''}',
        icon: '${m['icon'] ?? 'i_library_books_outlined'}',
        color: (m['color'] as num?)?.toInt() ?? 0xFF1F5E3B,
        order: (m['order'] as num?)?.toInt() ?? 0,
        hidden: m['hidden'] == true,
      );

  Map<String, dynamic> toMap() =>
      {'name': name, 'icon': icon, 'color': color, 'order': order, 'hidden': hidden};
}

/// Question kinds: one right choice, true/false, or put items in order.
enum QuizType { choice, trueFalse, order }

class QuizQ {
  final String id;
  String cat;
  QuizType type;
  String text;
  String quote; // a verse, hadith or text shown inside the question
  String image; // optional picture link
  List<String> choices; // for «order»: the items in their RIGHT order
  int correct; // index of the right choice (choice / trueFalse: 0 = صح)
  String explain;
  String hint;
  bool showHint;
  String linkTitle;
  String linkUrl;
  int level; // 1 مبتدئ، 2 متوسط، 3 متقدم
  int order;
  bool draft;
  bool hidden;
  bool kids;
  DateTime? releaseAt;
  DateTime? createdAt;
  String suggestedBy;
  bool showSuggester;
  /// More than one right choice (indexes); empty = only [correct].
  List<int> corrects;
  /// Where the answer comes from (book and page).
  String src;
  /// The answers chapter whose «اختبر نفسك» holds this question ('' = none).
  String series;

  QuizQ({
    required this.id,
    required this.cat,
    this.type = QuizType.choice,
    this.text = '',
    this.quote = '',
    this.image = '',
    List<String>? choices,
    this.correct = 0,
    this.explain = '',
    this.hint = '',
    this.showHint = false,
    this.linkTitle = '',
    this.linkUrl = '',
    this.level = 1,
    this.order = 0,
    this.draft = false,
    this.hidden = false,
    this.kids = false,
    this.releaseAt,
    this.createdAt,
    this.suggestedBy = '',
    this.showSuggester = false,
    List<int>? corrects,
    this.src = '',
    this.series = '',
  })  : choices = choices ?? ['', ''],
        corrects = corrects ?? [];

  bool get multi => type == QuizType.choice && corrects.length > 1;

  /// The right choice indexes.
  Set<int> get rightSet => multi ? corrects.toSet() : {correct};

  static DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory QuizQ.fromMap(String id, Map<String, dynamic> m) => QuizQ(
        id: id,
        cat: '${m['cat'] ?? ''}',
        type: QuizType.values.firstWhere((t) => t.name == m['type'], orElse: () => QuizType.choice),
        text: '${m['text'] ?? ''}',
        quote: '${m['quote'] ?? ''}',
        image: '${m['image'] ?? ''}',
        choices: [for (final c in (m['choices'] as List? ?? const [])) '$c'],
        correct: (m['correct'] as num?)?.toInt() ?? 0,
        explain: '${m['explain'] ?? ''}',
        hint: '${m['hint'] ?? ''}',
        showHint: m['showHint'] == true,
        linkTitle: '${m['linkTitle'] ?? ''}',
        linkUrl: '${m['linkUrl'] ?? ''}',
        level: (m['level'] as num?)?.toInt() ?? 1,
        order: (m['order'] as num?)?.toInt() ?? 0,
        draft: m['draft'] == true,
        hidden: m['hidden'] == true,
        kids: m['kids'] == true,
        releaseAt: _date(m['releaseAt']),
        createdAt: _date(m['createdAt']),
        suggestedBy: '${m['suggestedBy'] ?? ''}',
        showSuggester: m['showSuggester'] == true,
        corrects: [for (final c in (m['corrects'] as List? ?? const [])) (c as num).toInt()],
        src: '${m['src'] ?? ''}',
        series: '${m['series'] ?? ''}',
      );

  Map<String, dynamic> toMap() => {
        'cat': cat,
        'type': type.name,
        'text': text,
        'quote': quote,
        'image': image,
        'choices': choices,
        'correct': correct,
        'explain': explain,
        'hint': hint,
        'showHint': showHint,
        'linkTitle': linkTitle,
        'linkUrl': linkUrl,
        'level': level,
        'order': order,
        'draft': draft,
        'hidden': hidden,
        'kids': kids,
        'releaseAt': releaseAt == null ? null : Timestamp.fromDate(releaseAt!),
        'suggestedBy': suggestedBy,
        'showSuggester': showSuggester,
        'corrects': corrects,
        'src': src,
        'series': series,
      };

  QuizQ copy({String? id, String? cat}) => QuizQ.fromMap(id ?? this.id, toMap()..['cat'] = cat ?? this.cat)
    ..createdAt = createdAt;

  /// What everyone (not only the staff) may see now.
  bool get isLive => !draft && !hidden && (releaseAt == null || !releaseAt!.isAfter(DateTime.now()));

  bool get isNew => createdAt != null && DateTime.now().difference(createdAt!).inDays < 7;
}

/// The reader's own record of one answered question. It is never changed.
class QuizMark {
  final bool ok;
  final int choice; // the chosen index (or -1 for «order»)
  final DateTime at;
  QuizMark(this.ok, this.choice, this.at);

  Map<String, dynamic> toJson() => {'ok': ok, 'c': choice, 'at': at.millisecondsSinceEpoch};
  factory QuizMark.fromJson(Map<String, dynamic> j) =>
      QuizMark(j['ok'] == true, (j['c'] as num?)?.toInt() ?? -1, DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()));
}

class LeaderRow {
  final String name;
  final int score;
  final bool me;
  LeaderRow(this.name, this.score, this.me);
}

/// Everything about «الأسئلة»: questions, categories, the reader's answers
/// (kept on the phone, and in the account when signed in), and the boards.
class Quiz extends ChangeNotifier {
  Quiz._();
  static final Quiz instance = Quiz._();

  static const levelNames = {1: 'مبتدئ', 2: 'متوسط', 3: 'متقدم'};
  static const defaultCats = [
    ('العقيدة', 'i_shield_outlined', 0xFF1F5E3B),
    ('الطهارة', 'i_water_drop_outlined', 0xFF2E6B73),
    ('الصلاة', 'i_mosque_outlined', 0xFF145A32),
    ('الزكاة', 'i_volunteer_activism_outlined', 0xFF8E6B1E),
    ('الصيام', 'i_nightlight_round', 0xFF3B4A8C),
    ('الحج', 'i_flight_takeoff', 0xFF7A4A1E),
    ('الحديث', 'i_library_books_outlined', 0xFF5B3A7A),
    ('السيرة', 'i_spa_outlined', 0xFF9C3D3D),
    ('الآداب', 'i_favorite_border', 0xFFB0602A),
  ];

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  bool loaded = false;
  bool loading = false;
  List<QuizCat> cats = [];
  List<QuizQ> all = []; // staff see drafts and hidden too
  final Map<String, QuizMark> marks = {};
  final Set<String> saved = {};
  final Map<String, (int, int)> stats = {}; // qid -> (answered, right)
  final Map<String, List<int>> choiceStats = {}; // qid -> how many picked each choice
  String nick = '';
  bool showName = true;
  bool timer = false;
  bool kidsMode = false;
  int streak = 0;
  String lastDay = '';
  String thanks = '';

  // ------------------------------------------------------------ loading
  Future<void> load({bool force = false}) async {
    if (loading || (loaded && !force)) return;
    loading = true;
    await _loadLocal();
    // Readers take the quiz from the site file (made four times a day), which
    // costs no Firestore reads. The staff work on Firestore itself, live.
    if (!Cloud.instance.isAdmin) {
      await _loadFromSite();
    } else {
      await _loadFromCloud();
    }
    if (cats.isEmpty) {
      // Nothing yet: show the starting buttons all the same.
      cats = [
        for (var i = 0; i < defaultCats.length; i++)
          QuizCat(id: 'd$i', name: defaultCats[i].$1, icon: defaultCats[i].$2, color: defaultCats[i].$3, order: i)
      ];
    }
    loaded = true;
    fromCloud = Cloud.instance.isAdmin;
    loading = false;
    notifyListeners();
  }

  /// True when the questions came from Firestore (staff), not the site file.
  bool fromCloud = false;

  Future<void> _loadFromSite() async {
    final m = await SiteFiles.get('quiz.json', fresh: loaded);
    if (m != null) {
      cats = [for (final c in (m['cats'] as List? ?? const [])) QuizCat.fromMap('${c['id']}', Map<String, dynamic>.from(c as Map))]
        ..sort((a, b) => a.order.compareTo(b.order));
      all = [for (final q in (m['qs'] as List? ?? const [])) QuizQ.fromMap('${q['id']}', Map<String, dynamic>.from(q as Map))]
        ..sort((a, b) => a.order.compareTo(b.order));
      thanks = '${m['thanks'] ?? ''}';
    }
    try {
      await _syncAccount();
    } catch (_) {}
    unawaited(_loadStats());
  }

  Future<void> _loadFromCloud() async {
    try {
      final cq = await _db.collection('quizCats').get();
      cats = [for (final d in cq.docs) QuizCat.fromMap(d.id, d.data())]..sort((a, b) => a.order.compareTo(b.order));
      if (cats.isEmpty && Cloud.instance.isAdmin) await _seedCats();
      final qq = await _db.collection('quizQs').get();
      all = [for (final d in qq.docs) QuizQ.fromMap(d.id, d.data())]..sort((a, b) => a.order.compareTo(b.order));
      final cfg = await _db.doc('config/quiz').get();
      thanks = '${cfg.data()?['thanks'] ?? ''}';
      await _syncAccount();
      unawaited(_loadStats());
    } catch (e) {
      debugPrint('quiz load: $e');
    }
  }

  Future<void> _seedCats() async {
    final batch = _db.batch();
    for (var i = 0; i < defaultCats.length; i++) {
      final ref = _db.collection('quizCats').doc();
      final c = QuizCat(id: ref.id, name: defaultCats[i].$1, icon: defaultCats[i].$2, color: defaultCats[i].$3, order: i);
      batch.set(ref, c.toMap());
      cats.add(c);
    }
    await batch.commit();
  }

  Future<void> _loadStats() async {
    try {
      // From the site file (four times a day), for everyone: no Firestore reads.
      final m = await SiteFiles.get('stats.json');
      for (final e in ((m?['q'] ?? {}) as Map).entries) {
        final l = [for (final x in e.value as List) (x as num).toInt()];
        if (l.length < 10) continue;
        stats['${e.key}'] = (l[0], l[1]);
        choiceStats['${e.key}'] = l.sublist(2, 10);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadLocal() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('quizMarks');
    if (raw != null) {
      try {
        (jsonDecode(raw) as Map<String, dynamic>)
            .forEach((k, v) => marks[k] = QuizMark.fromJson(v as Map<String, dynamic>));
      } catch (_) {}
    }
    saved
      ..clear()
      ..addAll(p.getStringList('quizSaved') ?? const []);
    nick = p.getString('quizNick') ?? '';
    showName = p.getBool('quizShowName') ?? true;
    timer = p.getBool('quizTimer') ?? false;
    kidsMode = p.getBool('quizKids') ?? false;
    streak = p.getInt('quizStreak') ?? 0;
    lastDay = p.getString('quizLastDay') ?? '';
  }

  Future<void> _saveLocal() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('quizMarks', jsonEncode({for (final e in marks.entries) e.key: e.value.toJson()}));
    await p.setStringList('quizSaved', saved.toList());
    await p.setString('quizNick', nick);
    await p.setBool('quizShowName', showName);
    await p.setBool('quizTimer', timer);
    await p.setBool('quizKids', kidsMode);
    await p.setInt('quizStreak', streak);
    await p.setString('quizLastDay', lastDay);
  }

  /// Answers made on the phone (even without internet) go up to the account,
  /// and answers made on another phone come down. A mark is never replaced.
  Future<void> _syncAccount() async {
    final u = Cloud.instance.user;
    if (u == null) return;
    final p = await SharedPreferences.getInstance();
    // Older versions kept one document per answer; read them once only.
    if (p.getBool('quizMoved_${u.uid}') != true) {
      try {
        final remote = await _db.collection('quizUsers').doc(u.uid).collection('a').get();
        for (final d in remote.docs) {
          marks.putIfAbsent(d.id, () => QuizMark.fromJson(d.data()));
        }
        await p.setBool('quizMoved_${u.uid}', true);
        _profileDirty = true;
      } catch (_) {}
    }
    final prof = await _db.doc('quizUsers/${u.uid}').get();
    if (prof.exists) {
      final m = prof.data()!;
      // Answers made on another phone (one map in the same document).
      for (final e in ((m['m'] ?? {}) as Map).entries) {
        final v = e.value;
        if (v is List && v.length >= 3) {
          marks.putIfAbsent('${e.key}',
              () => QuizMark(v[1] == true, (v[0] as num).toInt(), DateTime.fromMillisecondsSinceEpoch((v[2] as num).toInt())));
        }
      }
      if (nick.isEmpty) nick = '${m['nick'] ?? ''}';
      showName = m['showName'] != false;
    }
    await _saveLocal();
    _profileDirty = true;
  }

  // ------------------------------------------------------------ views
  bool get isStaff => Cloud.instance.isAdmin;

  List<QuizCat> get visibleCats => isStaff ? cats : cats.where((c) => !c.hidden).toList();

  List<QuizQ> get live => all.where((q) => q.isLive && (!kidsMode || q.kids)).toList();

  List<QuizQ> inCat(String cat, {int level = 0}) => (isStaff ? all : live)
      .where((q) => q.cat == cat && (level == 0 || q.level == level))
      .toList();

  int answeredIn(String cat) => live.where((q) => q.cat == cat && marks.containsKey(q.id)).length;
  int liveIn(String cat) => live.where((q) => q.cat == cat).length;
  /// «اختبر نفسك» in an answers chapter: the questions the sheikh added to it.
  List<QuizQ> inSeries(String chapter) => live.where((q) => q.series == chapter).toList();
  bool hasNewIn(String cat) => live.any((q) => q.cat == cat && q.isNew && !marks.containsKey(q.id));

  int get right => marks.values.where((m) => m.ok).length;
  int get wrong => marks.values.where((m) => !m.ok).length;
  /// Points: a hard question is worth more.
  int get score {
    var p = 0;
    final lv = {for (final q in all) q.id: q.level};
    for (final e in marks.entries) {
      if (e.value.ok) p += 10 * (lv[e.key] ?? 1);
    }
    return p;
  }

  List<QuizQ> get wrongOnes => [for (final q in all) if (marks[q.id]?.ok == false) q];
  List<QuizQ> get savedOnes => [for (final q in all) if (saved.contains(q.id)) q];

  String get levelTitle {
    final r = right;
    if (r >= 300) return 'طالب علم';
    if (r >= 150) return 'طالب مجتهد';
    if (r >= 60) return 'طالب متقدم';
    if (r >= 20) return 'طالب متوسط';
    return 'طالب مبتدئ';
  }

  /// Small rewards, all worked out from the reader's own answers.
  List<(String, IconData)> get badges {
    final out = <(String, IconData)>[];
    if (marks.isNotEmpty) out.add(('أول جواب', Icons.flag_outlined));
    if (right >= 20) out.add(('20 جواباً صحيحاً', Icons.military_tech_outlined));
    if (right >= 100) out.add(('100 جواب صحيح', Icons.emoji_events_outlined));
    if (streak >= 7) out.add(('أسبوع متواصل', Icons.local_fire_department_outlined));
    for (final c in cats) {
      final n = liveIn(c.id);
      if (n >= 5 && answeredIn(c.id) == n) out.add(('أتممت ${c.name}', Icons.workspace_premium_outlined));
    }
    return out;
  }

  /// One question a day for the home page: the same for everyone that day,
  /// skipping what the reader has already answered when possible.
  QuizQ? get ofTheDay {
    final pool = live.where((q) => q.type != QuizType.order).toList();
    if (pool.isEmpty) return null;
    final day = DateTime.now().difference(DateTime(2024)).inDays;
    final fresh = pool.where((q) => !marks.containsKey(q.id)).toList();
    final list = fresh.isNotEmpty ? fresh : pool;
    list.sort((a, b) => a.id.compareTo(b.id));
    return list[day % list.length];
  }

  /// The next question the reader has not answered, in order (the path goes
  /// from easy to hard).
  QuizQ? nextIn(String cat, {int level = 0}) {
    final l = inCat(cat, level: level).where((q) => q.isLive).toList()
      ..sort((a, b) => a.level != b.level ? a.level.compareTo(b.level) : a.order.compareTo(b.order));
    for (final q in l) {
      if (!marks.containsKey(q.id)) return q;
    }
    return null;
  }

  int? percentRight(String id) {
    final s = stats[id];
    if (s == null || s.$1 == 0) return null;
    return (s.$2 * 100 / s.$1).round();
  }

  List<QuizQ> search(String text) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    return live
        .where((q) => q.text.contains(t) || q.explain.contains(t) || q.choices.any((c) => c.contains(t)))
        .toList();
  }

  static String weekKey([DateTime? d]) {
    final now = d ?? DateTime.now();
    final start = DateTime(now.year, 1, 1);
    return '${now.year}-w${(now.difference(start).inDays ~/ 7) + 1}';
  }

  static String monthKey([DateTime? d]) {
    final now = d ?? DateTime.now();
    return '${now.year}-${now.month}';
  }

  // ------------------------------------------------------------ answering
  /// Records the answer once. Returns false if it was already answered.
  Future<bool> answer(QuizQ q, {required bool ok, int choice = -1}) async {
    if (marks.containsKey(q.id)) return false;
    final now = DateTime.now();
    marks[q.id] = QuizMark(ok, choice, now);
    final today = '${now.year}-${now.month}-${now.day}';
    if (lastDay != today) {
      final y = now.subtract(const Duration(days: 1));
      streak = lastDay == '${y.year}-${y.month}-${y.day}' ? streak + 1 : 1;
      lastDay = today;
    }
    final s = stats[q.id] ?? (0, 0);
    stats[q.id] = (s.$1 + 1, s.$2 + (ok ? 1 : 0));
    if (choice >= 0 && choice < 8) {
      final cs = choiceStats[q.id] ?? List.filled(8, 0);
      cs[choice]++;
      choiceStats[q.id] = cs;
    }
    await _saveLocal();
    notifyListeners();
    // Sent later with everything else, in one write (see DayLog).
    DayLog.instance.answer(q.id, choice, ok);
    _profileDirty = true;
    return true;
  }

  bool _profileDirty = false;

  /// Sends the reader's quiz record (score, name, and his answers as one map)
  /// in one write, only when something changed. Called by DayLog.
  Future<void> flushProfile() async {
    if (!_profileDirty) return;
    _profileDirty = false;
    await _pushProfile();
  }

  Future<void> _pushProfile() async {
    final u = Cloud.instance.user;
    if (u == null) return;
    final week = weekKey(), month = monthKey();
    var w = 0, m = 0;
    final now = DateTime.now();
    for (final mk in marks.values) {
      if (!mk.ok) continue;
      if (weekKey(mk.at) == week) w++;
      if (monthKey(mk.at) == month && mk.at.year == now.year) m++;
    }
    try {
      await _db.doc('quizUsers/${u.uid}').set({
        'nick': nick.trim().isEmpty ? 'طالب علم' : nick.trim(),
        'showName': showName,
        'score': right,
        'wrong': wrong,
        'week': week,
        'weekScore': w,
        'month': month,
        'monthScore': m,
        'streak': streak,
        'm': {for (final e in marks.entries) e.key: [e.value.choice, e.value.ok, e.value.at.millisecondsSinceEpoch]},
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> setProfile({String? nick, bool? showName}) async {
    if (nick != null) this.nick = nick.trim();
    if (showName != null) this.showName = showName;
    await _saveLocal();
    notifyListeners();
    await _pushProfile();
  }

  Future<void> setTimer(bool v) async {
    timer = v;
    await _saveLocal();
    notifyListeners();
  }

  Future<void> setKids(bool v) async {
    kidsMode = v;
    await _saveLocal();
    notifyListeners();
  }

  Future<void> toggleSaved(String id) async {
    saved.contains(id) ? saved.remove(id) : saved.add(id);
    await _saveLocal();
    notifyListeners();
  }

  /// period: 'week', 'month' or 'all'.
  Future<List<LeaderRow>> leaders(String period) async {
    final field = period == 'week' ? 'weekScore' : period == 'month' ? 'monthScore' : 'score';
    final key = period == 'week' ? weekKey() : period == 'month' ? monthKey() : '';
    final me = Cloud.instance.user?.uid;
    final q = await _db.collection('quizUsers').orderBy(field, descending: true).limit(150).get();
    final out = <LeaderRow>[];
    for (final d in q.docs) {
      final m = d.data();
      if (period == 'week' && m['week'] != key) continue;
      if (period == 'month' && m['month'] != key) continue;
      final s = (m[field] as num?)?.toInt() ?? 0;
      if (s <= 0) continue;
      final name = m['showName'] == false ? 'مشارك' : '${m['nick'] ?? 'طالب علم'}';
      out.add(LeaderRow(name, s, d.id == me));
      if (out.length >= 50) break;
    }
    return out;
  }

  // ------------------------------------------------------------ suggestions
  Future<String?> suggest(String cat, String text, List<String> choices, int correct, String explain) async {
    final u = Cloud.instance.user;
    if (u == null) return 'سجّل الدخول أولاً لتقترح سؤالاً.';
    final p = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';
    final n = p.getString('quizSugDay') == today ? (p.getInt('quizSugN') ?? 0) : 0;
    if (n >= 3) return 'تستطيع اقتراح 3 أسئلة في اليوم فقط. عُد غداً إن شاء الله.';
    try {
      await _db.collection('quizSuggest').add({
        'uid': u.uid,
        'nick': nick.trim().isEmpty ? 'طالب علم' : nick.trim(),
        'cat': cat,
        'text': text.trim(),
        'choices': choices,
        'correct': correct,
        'explain': explain.trim(),
        'status': 'pending',
        'at': FieldValue.serverTimestamp(),
      });
      await p.setString('quizSugDay', today);
      await p.setInt('quizSugN', n + 1);
      return null;
    } catch (e) {
      return 'تعذّر الإرسال، حاول لاحقاً.';
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> suggestions() =>
      _db.collection('quizSuggest').orderBy('at', descending: true).limit(100).snapshots();

  Future<void> dropSuggestion(String id) => _db.doc('quizSuggest/$id').set({'status': 'rejected'}, SetOptions(merge: true));
  Future<void> acceptSuggestion(String id) => _db.doc('quizSuggest/$id').set({'status': 'accepted'}, SetOptions(merge: true));

  /// The reader's own suggestions with their state.
  Future<List<Map<String, dynamic>>> mySuggestions() async {
    final u = Cloud.instance.user;
    if (u == null) return const [];
    final q = await _db.collection('quizSuggest').where('uid', isEqualTo: u.uid).get();
    final l = [for (final d in q.docs) d.data()];
    l.sort((a, b) => '${b['at']}'.compareTo('${a['at']}'));
    return l;
  }

  /// For the staff: who answered a question (names only).
  Future<List<Map<String, dynamic>>> answersOf(String qid) async {
    // Each phone's day document holds its answers; only those with this
    // question come back (names only).
    final q = await _db.collection('searches').orderBy('a.$qid').limit(300).get();
    return [
      for (final d in q.docs)
        if (d.data()['a']?[qid] is List)
          {
            'name': d.data()['name'] ?? 'زائر',
            'choice': (d.data()['a'][qid] as List)[0],
            'ok': (d.data()['a'][qid] as List)[1] == true,
          }
    ];
  }

  /// Many questions at once from pasted text. Each question is a block:
  ///   س: نص السؤال
  ///   - خيار
  ///   * خيار صحيح
  ///   شرح: …   (اختياري)   مصدر: …   (اختياري)
  /// Blocks are separated by an empty line. They are saved as drafts.
  static List<QuizQ> parseBulk(String text, String cat, int level) {
    final out = <QuizQ>[];
    for (final block in text.split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isEmpty) continue;
      var qText = '', explain = '', src = '';
      final choices = <String>[];
      final right = <int>[];
      for (final l in lines) {
        if (RegExp(r'^(س|سؤال|السؤال)\s*[:：]').hasMatch(l)) {
          qText = l.replaceFirst(RegExp(r'^(س|سؤال|السؤال)\s*[:：]\s*'), '');
        } else if (l.startsWith('*') || l.startsWith('✓') || l.startsWith('✅')) {
          right.add(choices.length);
          choices.add(l.replaceFirst(RegExp(r'^[*✓✅]\s*'), ''));
        } else if (l.startsWith('-') || l.startsWith('•')) {
          choices.add(l.replaceFirst(RegExp(r'^[-•]\s*'), ''));
        } else if (RegExp(r'^(شرح|الشرح)\s*[:：]').hasMatch(l)) {
          explain = l.replaceFirst(RegExp(r'^(شرح|الشرح)\s*[:：]\s*'), '');
        } else if (RegExp(r'^(مصدر|المصدر)\s*[:：]').hasMatch(l)) {
          src = l.replaceFirst(RegExp(r'^(مصدر|المصدر)\s*[:：]\s*'), '');
        } else if (qText.isEmpty) {
          qText = l;
        } else if (choices.isEmpty) {
          qText = '$qText\n$l';
        } else {
          explain = explain.isEmpty ? l : '$explain\n$l';
        }
      }
      if (qText.isEmpty || choices.length < 2 || right.isEmpty) continue;
      out.add(QuizQ(
        id: '',
        cat: cat,
        text: qText,
        choices: choices,
        correct: right.first,
        corrects: right.length > 1 ? right : [],
        explain: explain,
        src: src,
        level: level,
        draft: true,
      ));
    }
    return out;
  }

  Future<String?> saveMany(List<QuizQ> list) async {
    try {
      var order = all.length;
      for (final q in list) {
        await _db.collection('quizQs').add(q.toMap()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['order'] = order++);
      }
      await Cloud.instance.logAction('الأسئلة: إضافة ${list.length} سؤالاً دفعة واحدة');
      await load(force: true);
      return null;
    } catch (e) {
      return 'تعذّر الحفظ: $e';
    }
  }

  // ------------------------------------------------ AI suggestions (staff)
  /// All AI-suggested questions sit in ONE document, so opening them is one
  /// read and each change one write. Nobody but the staff can see them.
  DocumentReference<Map<String, dynamic>> get _aiDoc => _db.doc('drafts/aiQuiz');

  Future<List<Map<String, dynamic>>> aiList() async {
    try {
      final d = (await _aiDoc.get()).data() ?? {};
      return [for (final e in (d['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    } catch (_) {
      return [];
    }
  }

  Future<String?> aiKeep(List<Map<String, dynamic>> items) async {
    try {
      await _aiDoc.set({'items': items.take(800).toList()});
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  /// Turns one suggestion into a question (published unless [draft]).
  QuizQ aiToQ(Map<String, dynamic> m, {bool draft = false}) {
    final name = '${m['cat'] ?? ''}';
    final cat = cats.where((c) => c.name == name).firstOrNull ?? (cats.isEmpty ? null : cats.first);
    return QuizQ.fromMap('', {
      'cat': cat?.id ?? '',
      'type': 'choice',
      'text': m['text'],
      'choices': m['choices'],
      'correct': m['correct'],
      'explain': m['explain'],
      'src': m['src'],
      'level': m['level'],
      'draft': draft,
    });
  }

  /// Asks the AI for [count] new questions, [batch] at a time, and adds them
  /// to the suggestions. [onStep] gets how many are ready so far.
  Future<String?> aiGenerate(int count, {String cat = '', int level = 0, void Function(int)? onStep}) async {
    final have = await aiList();
    final names = cat.isEmpty ? [for (final c in cats) if (c.id.length > 3) c.name] : [cat];
    if (names.isEmpty) return 'أضف تصنيفاً واحداً على الأقل أولاً';
    final avoid = [...all.map((q) => q.text), ...have.map((m) => '${m['text']}')];
    var made = 0, fails = 0;
    while (made < count && fails < 3) {
      final n = math.min(20, count - made);
      final l = await Ai.quizQuestions(count: n, cats: names, level: level, avoid: avoid.reversed.toList());
      if (l.isEmpty) {
        fails++;
        continue;
      }
      final seen = avoid.toSet();
      final fresh = [
        for (final m in l)
          if (!seen.contains(m['text'])) {...m, 'k': '${DateTime.now().microsecondsSinceEpoch}${made + l.indexOf(m)}'}
      ];
      have.addAll(fresh);
      avoid.addAll(fresh.map((m) => '${m['text']}'));
      made += fresh.length;
      final err = await aiKeep(have);
      if (err != null) return err;
      onStep?.call(made);
    }
    if (made == 0) return Ai.supported ? 'لم يرجع الذكاء الاصطناعي بأسئلة، حاول بعد قليل' : 'هذا يعمل من تطبيق الأندرويد';
    return null;
  }

  /// «أرسل الأسئلة الآن»: the server looks every half hour and, when asked,
  /// makes the readers' file again at once (otherwise every six hours).
  Future<String?> publishNow() async {
    try {
      await _db.doc('answers/_quizNow').set({'at': FieldValue.serverTimestamp(), 'by': Cloud.instance.email});
      await Cloud.instance.logAction('الأسئلة: أرسل الأسئلة الآن');
      return null;
    } catch (_) {
      return 'تعذّر الإرسال';
    }
  }

  /// This month's summary: answered, right, and the strongest category.
  (int, int, String) get monthSummary {
    final now = DateTime.now();
    final catOf = {for (final q in all) q.id: q.cat};
    var n = 0, ok = 0;
    final per = <String, int>{};
    for (final e in marks.entries) {
      if (e.value.at.year != now.year || e.value.at.month != now.month) continue;
      n++;
      if (e.value.ok) {
        ok++;
        final c = catOf[e.key];
        if (c != null) per[c] = (per[c] ?? 0) + 1;
      }
    }
    var best = '';
    if (per.isNotEmpty) {
      final top = per.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      best = cats.where((c) => c.id == top).firstOrNull?.name ?? '';
    }
    return (n, ok, best);
  }

  Future<bool> report(QuizQ q, String note) async {
    try {
      await _db.collection('reports').add({
        'answerId': 'quiz:${q.id}',
        'title': 'سؤال: ${q.text.length > 80 ? q.text.substring(0, 80) : q.text}',
        'note': note.trim(),
        'by': Cloud.instance.email ?? '',
        'at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ staff
  Future<String?> saveCat(QuizCat c) async {
    try {
      if (c.id.startsWith('d') && c.id.length <= 3) {
        final ref = _db.collection('quizCats').doc();
        await ref.set(c.toMap());
      } else {
        await _db.doc('quizCats/${c.id}').set(c.toMap());
      }
      await Cloud.instance.logAction('الأسئلة: حفظ تصنيف', c.name);
      await load(force: true);
      return null;
    } catch (e) {
      return 'تعذّر الحفظ: $e';
    }
  }

  Future<String?> reorderCats(List<QuizCat> list) async {
    try {
      final b = _db.batch();
      for (var i = 0; i < list.length; i++) {
        list[i].order = i;
        b.set(_db.doc('quizCats/${list[i].id}'), {'order': i}, SetOptions(merge: true));
      }
      await b.commit();
      cats = list;
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذّر الحفظ';
    }
  }

  Future<String?> saveQ(QuizQ q) async {
    try {
      if (q.id.isEmpty) {
        final m = q.toMap()
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['order'] = inCat(q.cat).length;
        await _db.collection('quizQs').add(m);
        await Cloud.instance.logAction('الأسئلة: إضافة سؤال', q.text);
      } else {
        await _db.doc('quizQs/${q.id}').set(q.toMap(), SetOptions(merge: true));
        await Cloud.instance.logAction('الأسئلة: تعديل سؤال', q.text);
      }
      await load(force: true);
      return null;
    } catch (e) {
      return 'تعذّر الحفظ: $e';
    }
  }

  Future<String?> copyTo(QuizQ q, String cat) async {
    final c = q.copy(id: '', cat: cat)..draft = q.draft;
    return saveQ(c);
  }

  Future<String?> deleteQ(QuizQ q) async {
    try {
      await _db.doc('quizQs/${q.id}').delete();
      await Cloud.instance.logAction('الأسئلة: حذف سؤال', q.text);
      await load(force: true);
      return null;
    } catch (e) {
      return 'تعذّر الحذف';
    }
  }

  Future<String?> reorderQs(List<QuizQ> list) async {
    try {
      final b = _db.batch();
      for (var i = 0; i < list.length; i++) {
        list[i].order = i;
        b.set(_db.doc('quizQs/${list[i].id}'), {'order': i}, SetOptions(merge: true));
      }
      await b.commit();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذّر الحفظ';
    }
  }

  Future<String?> setThanks(String text) async {
    try {
      await _db.doc('config/quiz').set({'thanks': text.trim()}, SetOptions(merge: true));
      thanks = text.trim();
      notifyListeners();
      return null;
    } catch (e) {
      return 'تعذّر الحفظ';
    }
  }

  /// For the sheikh: questions with how many answered and how many erred,
  /// the most-missed first.
  List<(QuizQ, int, int)> get missed {
    final out = <(QuizQ, int, int)>[];
    for (final q in all) {
      final s = stats[q.id];
      if (s == null || s.$1 == 0) continue;
      out.add((q, s.$1, s.$1 - s.$2));
    }
    out.sort((a, b) => (b.$3 / math.max(1, b.$2)).compareTo(a.$3 / math.max(1, a.$2)));
    return out;
  }
}
