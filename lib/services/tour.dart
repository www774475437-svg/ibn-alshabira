import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'challenge.dart';
import 'cloud.dart';
import 'quiz.dart';
import 'site_files.dart';

/// One question of a Friday tournament (kept apart from the other questions,
/// so nobody sees it before the tournament).
class TourQ {
  String text;
  List<String> choices;
  int correct;
  String explain;
  TourQ(this.text, this.choices, this.correct, [this.explain = '']);

  factory TourQ.from(Map m) => TourQ('${m['t'] ?? ''}', [for (final c in (m['c'] as List? ?? const [])) '$c'],
      (m['a'] as num?)?.toInt() ?? 0, '${m['x'] ?? ''}');
  Map<String, dynamic> toMap() => {'t': text, 'c': choices, 'a': correct, if (explain.isNotEmpty) 'x': explain};

  QuizQ asQuiz(int i) => QuizQ(id: 'tour_$i', cat: '', text: text, choices: choices, correct: correct, explain: explain);
}

/// One player's result in a tournament.
class TourPlayer {
  final String uid, name;
  final int no, score, right, wrong, ms;
  final bool finished;
  TourPlayer(this.uid, this.name, this.no, this.score, this.right, this.wrong, this.ms, this.finished);

  factory TourPlayer.from(String uid, Map m) {
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return TourPlayer(uid, '${m['name'] ?? 'طالب علم'}', n('no'), n('score'), n('right'), n('wrong'), n('ms'), m['finished'] == true);
  }
  Map<String, dynamic> toMap() =>
      {'name': name, 'no': no, 'score': score, 'right': right, 'wrong': wrong, 'ms': ms, 'finished': finished};
}

/// «بطولة الجمعة»: every Friday at 9 pm Mecca time (18:00 UTC). The room
/// opens ten minutes before; at the time it starts for everyone together.
/// Its questions are written ahead (for any coming Friday) by the developer
/// and the sheikh, and stay locked until the room opens.
/// Players go to the live database (no reads); when it is full they go to
/// Firestore, one small document each. The server makes the record
/// (tours.json) after each tournament: winners, the year's champions.
class Tour extends ChangeNotifier {
  Tour._();
  static final Tour instance = Tour._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  Challenges get _ch => Challenges.instance;

  static const lobbyMinutes = 10;
  static const secs = 15;

  bool on = false;
  /// Coming Fridays that already have questions (from the server file).
  Map<String, int> ready = {};
  /// Past tournaments, newest first: {d, n, q, top: [{n, no, s, r, ms}]}.
  List<Map<String, dynamic>> history = [];

  /// The start of the next tournament (or the one going on now).
  static DateTime nextStart([DateTime? now]) {
    now = (now ?? DateTime.now()).toUtc();
    var d = DateTime.utc(now.year, now.month, now.day, 18);
    while (d.weekday != DateTime.friday || now.isAfter(d.add(const Duration(minutes: 30)))) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  static List<DateTime> coming(int n) {
    final first = nextStart();
    return [for (var i = 0; i < n; i++) first.add(Duration(days: 7 * i))];
  }

  static String keyOf(DateTime startUtc) =>
      '${startUtc.year}-${startUtc.month.toString().padLeft(2, '0')}-${startUtc.day.toString().padLeft(2, '0')}';
  static DateTime startOf(String key) {
    final p = key.split('-').map(int.parse).toList();
    return DateTime.utc(p[0], p[1], p[2], 18);
  }

  static DateTime openOf(String key) => startOf(key).subtract(const Duration(minutes: lobbyMinutes));

  Future<void> load() async {
    try {
      if (Cloud.instance.isAdmin) {
        on = (await _db.doc('config/quiz').get()).data()?['tour'] == true;
      } else {
        on = (await SiteFiles.get('quiz.json'))?['tourOn'] == true;
      }
    } catch (_) {}
    try {
      final m = await SiteFiles.get('tours.json');
      if (m != null) {
        ready = {for (final e in ((m['ready'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num?)?.toInt() ?? 0};
        history = [for (final h in (m['h'] as List? ?? const [])) Map<String, dynamic>.from(h as Map)];
        history.sort((a, b) => '${b['d']}'.compareTo('${a['d']}'));
      }
    } catch (_) {}
    unawaited(_claimPrize());
    notifyListeners();
  }

  /// Whether the next tournament should show on the home page.
  bool get showCard => on && ready.containsKey(keyOf(nextStart()));

  // ------------------------------------------------------------ staff
  Future<String?> setOn(bool v) async {
    try {
      await _db.doc('config/quiz').set({'tour': v}, SetOptions(merge: true));
      on = v;
      await Cloud.instance.logAction(v ? 'بطولة الجمعة: إظهار' : 'بطولة الجمعة: إخفاء');
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  Future<List<TourQ>> questions(String key) async {
    final d = (await _db.doc('tours/$key').get()).data();
    return [for (final q in (d?['qs'] as List? ?? const [])) TourQ.from(q as Map)];
  }

  Future<String?> save(String key, List<TourQ> qs) async {
    try {
      await _db.doc('tours/$key').set({
        'qs': [for (final q in qs) q.toMap()],
        'n': qs.length,
        'openAt': Timestamp.fromDate(openOf(key)),
        'startAt': startOf(key).millisecondsSinceEpoch,
        'by': Cloud.instance.email,
        'at': FieldValue.serverTimestamp(),
      });
      _counts[key] = qs.length;
      if (key == keyOf(nextStart())) {
        needQuestions = qs.isEmpty;
        final p = await SharedPreferences.getInstance();
        await p.setBool('tourRem', needQuestions);
      }
      await Cloud.instance.logAction('بطولة الجمعة: أسئلة $key (${qs.length})');
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ، تأكد من الاتصال.';
    }
  }

  final Map<String, int> _counts = {};

  /// Staff: how many questions each coming Friday has (one read each).
  Future<Map<String, int>> counts({bool fresh = false}) async {
    for (final d in coming(5)) {
      final k = keyOf(d);
      if (!fresh && _counts.containsKey(k)) continue;
      try {
        _counts[k] = ((await _db.doc('tours/$k').get()).data()?['n'] as num?)?.toInt() ?? 0;
      } catch (_) {
        _counts[k] = 0;
      }
    }
    return _counts;
  }

  /// Staff reminder on the home page: the next Friday is four days away or
  /// less and has no questions yet. Looked at once a day.
  bool needQuestions = false;
  Future<void> checkReminder() async {
    if (!Cloud.instance.canManageStaff) return;
    await load();
    if (!on) {
      needQuestions = false;
      notifyListeners();
      return;
    }
    final next = nextStart();
    if (next.difference(DateTime.now().toUtc()).inHours > 96) {
      needQuestions = false;
      notifyListeners();
      return;
    }
    final k = keyOf(next);
    final p = await SharedPreferences.getInstance();
    final day = Challenges.today();
    if (p.getString('tourRemDay') == '$day|$k') {
      needQuestions = p.getBool('tourRem') ?? false;
    } else {
      try {
        _counts[k] = ((await _db.doc('tours/$k').get()).data()?['n'] as num?)?.toInt() ?? 0;
        needQuestions = _counts[k] == 0;
        await p.setString('tourRemDay', '$day|$k');
        await p.setBool('tourRem', needQuestions);
      } catch (_) {}
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ playing
  String? joinedKey;
  bool joinedRt = false;
  List<TourQ> playQs = [];
  final Map<String, TourPlayer> _mine = {};

  TourPlayer? myResult(String key) => _mine[key];

  Future<void> _restore(String key) async {
    if (joinedKey == key) return;
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('tourJoin_$key');
      if (s == null) return;
      final m = jsonDecode(s) as Map;
      joinedKey = key;
      joinedRt = m['rt'] == true;
      playQs = [for (final q in (m['qs'] as List)) TourQ.from(q as Map)];
      if (m['me'] is Map) _mine[key] = TourPlayer.from(Cloud.instance.user?.uid ?? '', m['me'] as Map);
    } catch (_) {}
  }

  Future<bool> joined(String key) async {
    await _restore(key);
    return joinedKey == key;
  }

  Future<void> _keep(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          'tourJoin_$key',
          jsonEncode({
            'rt': joinedRt,
            'qs': [for (final q in playQs) q.toMap()],
            if (_mine[key] != null) 'me': _mine[key]!.toMap(),
          }));
    } catch (_) {}
  }

  /// Enters the room (from ten minutes before the start until the start).
  Future<String?> join(String key) async {
    final u = Cloud.instance.user;
    if (u == null) return 'سجّل الدخول أولاً لتدخل البطولة.';
    if (await joined(key)) return null;
    final now = DateTime.now().toUtc();
    if (now.isBefore(openOf(key))) return 'يُفتح الدخول قبل البطولة بعشر دقائق.';
    if (!now.isBefore(startOf(key))) return 'بدأت البطولة، فلا يمكن الدخول الآن. موعدنا الجمعة القادمة إن شاء الله.';
    List<TourQ> qs;
    try {
      qs = await questions(key); // one read: the questions, locked until now
    } catch (_) {
      return 'لم تُفتح البطولة بعد، حاول بعد دقيقة.';
    }
    if (qs.isEmpty) return 'لا توجد بطولة هذا الأسبوع.';
    final me = TourPlayer(u.uid, _ch.myName, askerNo(u.uid), 0, 0, 0, 0, false);
    var rt = false;
    if (await _ch.rtOk()) {
      try {
        final s = await _ch.rtDb.ref('tour/$key/p').once().timeout(const Duration(seconds: 8));
        final n = s.snapshot.value is Map ? (s.snapshot.value as Map).length : 0;
        if (n < 95) {
          await _ch.rtDb.ref('tour/$key/p/${u.uid}').set(me.toMap()).timeout(const Duration(seconds: 8));
          rt = true;
        }
      } catch (_) {}
    }
    if (!rt) {
      try {
        await _db.doc('tours/$key/p/${u.uid}').set(me.toMap());
      } catch (_) {
        return 'تعذّر الدخول، حاول مرة أخرى.';
      }
    }
    joinedKey = key;
    joinedRt = rt;
    playQs = qs;
    await _keep(key);
    notifyListeners();
    return null;
  }

  /// The players in the live room, at every change (no reads counted).
  Stream<List<TourPlayer>> livePlayers(String key) => _ch.rtDb.ref('tour/$key/p').onValue.map((e) {
        final v = e.snapshot.value;
        if (v is! Map) return <TourPlayer>[];
        return [for (final x in v.entries) if (x.value is Map) TourPlayer.from('${x.key}', x.value as Map)];
      });

  /// A player in Firestore (the live room was full): the live room's board,
  /// read once as a small plain request.
  Future<List<TourPlayer>> liveBoardOnce(String key) async {
    final u = Cloud.instance.user;
    if (u == null) return [];
    try {
      final token = await u.getIdToken();
      final r = await _ch.web.get(Uri.parse('${Challenges.rtUrl}/tour/$key/p.json?auth=$token')).timeout(const Duration(seconds: 10));
      final m = jsonDecode(r.body);
      if (m is! Map) return [];
      return [for (final x in m.entries) if (x.value is Map) TourPlayer.from('${x.key}', x.value as Map)];
    } catch (_) {
      return [];
    }
  }

  Future<void> finish(String key, {required int right, required int wrong, required int score, required int ms}) async {
    final u = Cloud.instance.user;
    if (u == null) return;
    final me = TourPlayer(u.uid, _ch.myName, askerNo(u.uid), score, right, wrong, ms, true);
    _mine[key] = me;
    await _keep(key);
    notifyListeners();
    try {
      if (joinedRt) {
        await _ch.rtDb.ref('tour/$key/p/${u.uid}').set(me.toMap());
      } else {
        await _db.doc('tours/$key/p/${u.uid}').set(me.toMap());
      }
    } catch (_) {}
  }

  static List<TourPlayer> rank(Iterable<TourPlayer> l) => [...l]
    ..sort((a, b) => b.score != a.score ? b.score.compareTo(a.score) : (a.ms == 0 ? 1 << 30 : a.ms).compareTo(b.ms == 0 ? 1 << 30 : b.ms));

  Future<void> saveBoard(String key, List<TourPlayer> board) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('tourBoard_$key', jsonEncode([for (final x in board) {...x.toMap(), 'uid': x.uid}]));
    } catch (_) {}
  }

  Future<List<TourPlayer>> savedBoard(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('tourBoard_$key');
      if (s == null) return [];
      return [for (final m in (jsonDecode(s) as List)) TourPlayer.from('${(m as Map)['uid']}', m)];
    } catch (_) {
      return [];
    }
  }

  // ------------------------------------------------------------ the record
  /// The year's champions: who won the most tournaments this year.
  List<(String name, int no, int wins)> champions(int year) {
    final m = <int, (String, int)>{};
    for (final h in history) {
      if (!'${h['d']}'.startsWith('$year-')) continue;
      final top = (h['top'] as List?) ?? const [];
      if (top.isEmpty) continue;
      final w = Map<String, dynamic>.from(top.first as Map);
      if (((w['s'] as num?) ?? 0) <= 0) continue;
      final no = (w['no'] as num?)?.toInt() ?? 0;
      final old = m[no];
      m[no] = ('${w['n'] ?? 'طالب علم'}', (old?.$2 ?? 0) + 1);
    }
    final l = [for (final e in m.entries) (e.value.$1, e.key, e.value.$2)]..sort((a, b) => b.$3.compareTo(a.$3));
    return l;
  }

  int winsOf(int no) {
    var n = 0;
    for (final h in history) {
      final top = (h['top'] as List?) ?? const [];
      if (top.isNotEmpty && ((top.first as Map)['no'] as num?)?.toInt() == no && (((top.first as Map)['s'] as num?) ?? 0) > 0) n++;
    }
    return n;
  }

  /// The three first of a tournament get two extra challenges each, once.
  Future<void> _claimPrize() async {
    final u = Cloud.instance.user;
    if (u == null || history.isEmpty) return;
    final no = askerNo(u.uid);
    final p = await SharedPreferences.getInstance();
    for (final h in history.take(4)) {
      final top = (h['top'] as List?) ?? const [];
      final place = top.take(3).toList().indexWhere((x) => ((x as Map)['no'] as num?)?.toInt() == no && ((x['s'] as num?) ?? 0) > 0);
      if (place < 0) continue;
      final key = 'tourPrize_${h['d']}';
      if (p.getBool(key) == true) continue;
      await p.setBool(key, true);
      try {
        await _db.doc('quizUsers/${u.uid}').set({'credits': FieldValue.increment(2)}, SetOptions(merge: true));
        _ch.credits += 2;
        prizeNote = 'مبارك! حللتَ في المركز ${place + 1} في بطولة الجمعة، فأُضيف لك تحدّيان هدية.';
        notifyListeners();
      } catch (_) {}
    }
  }

  String? prizeNote;

  static String arabicDate(String key) {
    const months = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    final d = startOf(key);
    return 'الجمعة ${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

