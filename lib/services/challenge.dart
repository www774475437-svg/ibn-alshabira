import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud.dart';
import 'quiz.dart';
import 'site_files.dart';

/// One player inside a challenge.
class ChPlayer {
  final String uid, name;
  final int score, right, wrong, ms;
  final bool finished;
  ChPlayer(this.uid, this.name, this.score, this.right, this.wrong, this.ms, this.finished);
  int get done => right + wrong;
}

/// A challenge room: two people or a group, on the same questions.
/// Lobby (up to two minutes) → everyone plays at once, 15 seconds a
/// question, nothing sent until each one finishes → the ranking at the end.
/// No messaging between players: names (or numbers) and results only.
class Challenge {
  final String code, host, hostName, mode; // duel | group
  final List<String> qids;
  final int secs;
  final String status; // lobby | play | done
  final List<ChPlayer> players;
  final DateTime? at;
  final int lobbyUntil, startAt; // ms
  final String rematch, rematchBy;
  Challenge(this.code, this.host, this.hostName, this.mode, this.qids, this.secs, this.status, this.players, this.at,
      this.lobbyUntil, this.startAt, this.rematch, this.rematchBy);

  int get max => mode == 'duel' ? 2 : 30;
  bool get allFinished => players.isNotEmpty && players.every((p) => p.finished);
  int get now => DateTime.now().millisecondsSinceEpoch;
  bool get inLobby => status == 'lobby' && now < lobbyUntil;
  bool get playing => !over && (status == 'play' || (status == 'lobby' && now >= lobbyUntil));
  int get playStart => startAt > 0 ? startAt : lobbyUntil;
  /// The last moment anyone can still be answering.
  int get deadline => playStart + qids.length * secs * 1000 + 45000;

  bool get over =>
      status == 'done' ||
      (allFinished && players.length >= 2) ||
      (status != 'lobby' || now >= lobbyUntil) && now > deadline ||
      (at != null && DateTime.now().difference(at!).inHours >= 24);

  /// Higher score first; same score: who finished faster.
  List<ChPlayer> get ranked => [...players]
    ..sort((a, b) => b.score != a.score ? b.score.compareTo(a.score) : (a.ms == 0 ? 1 << 30 : a.ms).compareTo(b.ms == 0 ? 1 << 30 : b.ms));

  factory Challenge.from(String code, Map<String, dynamic> m) {
    final ps = <ChPlayer>[];
    for (final e in ((m['players'] ?? {}) as Map).entries) {
      final p = e.value as Map;
      int n(String k) => (p[k] as num?)?.toInt() ?? 0;
      ps.add(ChPlayer('${e.key}', '${p['name'] ?? ''}', n('score'), n('right'), n('wrong'), n('ms'), p['finished'] == true));
    }
    return Challenge(
      code,
      '${m['host'] ?? ''}',
      '${m['hostName'] ?? ''}',
      '${m['mode'] ?? 'duel'}',
      [for (final q in (m['qids'] as List? ?? const [])) '$q'],
      (m['secs'] as num?)?.toInt() ?? 15,
      '${m['status'] ?? 'lobby'}',
      ps,
      m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : null,
      (m['lobbyUntil'] as num?)?.toInt() ?? 0,
      (m['startAt'] as num?)?.toInt() ?? 0,
      '${m['rematch'] ?? ''}',
      '${m['rematchBy'] ?? ''}',
    );
  }
}

class LeaderWin {
  final String name;
  final int wins;
  final bool me;
  LeaderWin(this.name, this.wins, this.me);
}

class Challenges extends ChangeNotifier {
  Challenges._();
  static final Challenges instance = Challenges._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  // Settings the sheikh controls (config/quiz).
  int perDay = 2;
  bool readPoints = false;

  /// The questions this reader got wrong in each challenge (kept on the phone).
  final Map<String, List<String>> myWrong = {};

  Future<void> markWrong(String code, String qid) async {
    (myWrong[code] ??= []).add(qid);
    try {
      final p = await SharedPreferences.getInstance();
      p.setStringList('chWrong_$code', myWrong[code]!);
    } catch (_) {}
  }

  Future<List<String>> wrongOf(String code) async {
    if (myWrong[code] != null) return myWrong[code]!;
    try {
      return (await SharedPreferences.getInstance()).getStringList('chWrong_$code') ?? const [];
    } catch (_) {
      return const [];
    }
  }

  // The reader's own counters (quizUsers/{uid}).
  int usedToday = 0;
  int credits = 0;
  int wins = 0, winsDuel = 0, winsGroup = 0, played = 0;

  static String today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  Future<void> load() async {
    try {
      // Staff see the setting live; readers take it from the site file.
      final Map<String, dynamic>? cfg =
          Cloud.instance.isAdmin ? (await _db.doc('config/quiz').get()).data() : await SiteFiles.get('quiz.json');
      perDay = (cfg?['chPerDay'] as num?)?.toInt() ?? 2;
      readPoints = cfg?['readPoints'] == true;
    } catch (_) {}
    final u = Cloud.instance.user;
    if (u != null) {
      try {
        final d = (await _db.doc('quizUsers/${u.uid}').get()).data() ?? {};
        usedToday = d['chDay'] == today() ? (d['chUsed'] as num?)?.toInt() ?? 0 : 0;
        credits = (d['credits'] as num?)?.toInt() ?? 0;
        wins = (d['chWins'] as num?)?.toInt() ?? 0;
        winsDuel = (d['chWinsDuel'] as num?)?.toInt() ?? 0;
        winsGroup = (d['chWinsGroup'] as num?)?.toInt() ?? 0;
        played = (d['chPlayed'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    notifyListeners();
  }

  int get left => math.max(0, perDay - usedToday) + credits;

  /// Takes one challenge from today's free ones, or else from the credits.
  Future<bool> _spend() async {
    final u = Cloud.instance.user;
    if (u == null) return false;
    await load();
    final data = <String, dynamic>{'chDay': today(), 'chPlayed': FieldValue.increment(1)};
    if (usedToday < perDay) {
      usedToday++;
      data['chUsed'] = usedToday;
    } else if (credits > 0) {
      credits--;
      data['credits'] = credits;
      data['chUsed'] = usedToday;
    } else {
      return false;
    }
    played++;
    await _db.doc('quizUsers/${u.uid}').set(data, SetOptions(merge: true));
    notifyListeners();
    return true;
  }

  String get _name {
    final n = Quiz.instance.nick.trim();
    return n.isEmpty ? ((Cloud.instance.user?.displayName ?? '').trim().isNotEmpty ? Cloud.instance.user!.displayName!.trim() : 'طالب علم') : n;
  }

  /// Picks the questions: approved and published only, those the host has
  /// not seen first; if they run out, older ones in a new order.
  /// [cat] and [books] may hold several ids, separated by commas; empty = all.
  List<String> pick({String cat = '', String books = '', int level = 0, int count = 5}) {
    final quiz = Quiz.instance;
    final cs = cat.split(',').where((x) => x.isNotEmpty).toSet();
    final bs = books.split(',').where((x) => x.isNotEmpty).toSet();
    bool from(QuizQ q) {
      if (cs.isEmpty && bs.isEmpty) return true;
      return cs.contains(q.cat) || bs.contains(q.book);
    }

    final pool = quiz.live
        .where((q) => q.type != QuizType.order && !q.multi && from(q) && (level == 0 || q.level == level))
        .toList()
      ..shuffle();
    final fresh = pool.where((q) => !quiz.marks.containsKey(q.id)).toList();
    final seen = pool.where((q) => quiz.marks.containsKey(q.id)).toList();
    return [...fresh, ...seen].take(count).map((q) => q.id).toList();
  }

  Future<(String?, String?)> create(
      {required String mode, String cat = '', String books = '', int level = 0, int count = 5, int secs = 15}) async {
    final u = Cloud.instance.user;
    if (u == null) return (null, 'سجّل الدخول أولاً لتبدأ تحدّياً.');
    final qids = pick(cat: cat, books: books, level: level, count: count);
    if (qids.length < 3) return (null, 'لا توجد أسئلة كافية لهذا الاختيار بعد.');
    if (!await _spend()) return (null, 'انتهت تحدّياتك اليوم. اطلب من الشيخ تحدّيات إضافية.');
    final rnd = math.Random();
    for (var tries = 0; tries < 6; tries++) {
      final code = '${10000 + rnd.nextInt(89999)}';
      final ref = _db.doc('challenges/$code');
      try {
        final ok = await _db.runTransaction<bool>((t) async {
          final snap = await t.get(ref);
          if (snap.exists) return false;
          t.set(ref, {
            'host': u.uid,
            'hostName': _name,
            'mode': mode,
            'qids': qids,
            'secs': 15,
            'status': 'lobby',
            'cat': cat,
            'books': books,
            'level': level,
            'lobbyUntil': DateTime.now().millisecondsSinceEpoch + 120000,
            'at': FieldValue.serverTimestamp(),
            'players': {
              u.uid: {'name': _name, 'score': 0, 'right': 0, 'wrong': 0, 'ms': 0, 'finished': false}
            },
          });
          return true;
        });
        if (ok) {
          await _remember(code);
          return (code, null);
        }
      } catch (e) {
        return (null, 'تعذّر إنشاء التحدّي، تأكد من الاتصال.');
      }
    }
    return (null, 'تعذّر إنشاء التحدّي، حاول مرة أخرى.');
  }

  Future<String?> join(String code) async {
    final u = Cloud.instance.user;
    if (u == null) return 'سجّل الدخول أولاً لتدخل التحدّي.';
    final ref = _db.doc('challenges/${code.trim()}');
    final snap = await ref.get();
    if (!snap.exists) return 'لا يوجد تحدٍّ بهذا الرمز.';
    final c = Challenge.from(snap.id, snap.data()!);
    if (c.players.any((p) => p.uid == u.uid)) return null; // already inside
    if (c.over) return 'انتهى هذا التحدّي.';
    if (!c.inLobby) return 'بدأ هذا التحدّي، فلا يمكن الدخول الآن.';
    if (c.players.length >= c.max) return 'التحدّي ممتلئ.';
    if (!await _spend()) return 'انتهت تحدّياتك اليوم. اطلب من الشيخ تحدّيات إضافية.';
    await ref.update({
      'players.${u.uid}': {'name': _name, 'score': 0, 'right': 0, 'wrong': 0, 'ms': 0, 'finished': false}
    });
    await _remember(code.trim());
    return null;
  }

  Stream<Challenge?> watch(String code) => _db
      .doc('challenges/$code')
      .snapshots()
      .map((s) => s.exists ? Challenge.from(s.id, s.data()!) : null);

  /// The host starts before the two minutes are up.
  Future<void> startNow(Challenge c) => _db
      .doc('challenges/${c.code}')
      .update({'status': 'play', 'startAt': DateTime.now().millisecondsSinceEpoch});

  /// Sends the reader's result once, at the end (one write for the game).
  Future<void> finish(Challenge c, {required int right, required int wrong, required int score, required int ms}) async {
    final u = Cloud.instance.user;
    if (u == null) return;
    try {
      await _db.doc('challenges/${c.code}').update({
        'players.${u.uid}.score': score,
        'players.${u.uid}.right': right,
        'players.${u.uid}.wrong': wrong,
        'players.${u.uid}.ms': ms,
        'players.${u.uid}.finished': true,
        if (c.status == 'lobby') 'status': 'play',
      });
    } catch (_) {}
  }

  /// «إعادة»: a new room with the same kind of questions; the others see a
  /// button to join it (each one spends one of his challenges).
  Future<(String?, String?)> rematch(Challenge c) async {
    final m = (await _db.doc('challenges/${c.code}').get()).data() ?? {};
    final r = await create(
        mode: c.mode, cat: '${m['cat'] ?? ''}', books: '${m['books'] ?? ''}', level: (m['level'] as num?)?.toInt() ?? 0, count: c.qids.length);
    if (r.$1 != null) {
      try {
        await _db.doc('challenges/${c.code}').update({'rematch': r.$1, 'rematchBy': _name});
      } catch (_) {}
    }
    return r;
  }

  Future<void> close(Challenge c) => _db.doc('challenges/${c.code}').update({'status': 'done'});

  /// Counts the win once, when the reader sees the final board.
  Future<void> countResult(Challenge c) async {
    final u = Cloud.instance.user;
    if (u == null || !c.over || c.players.length < 2) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'chCounted_${c.code}';
    if (prefs.getBool(key) == true) return;
    await prefs.setBool(key, true);
    final r = c.ranked;
    final top = r.first.score;
    if (top <= 0 || r.where((p) => p.score == top).length > 1) return; // a draw: no winner
    if (r.first.uid != u.uid) return;
    final week = Quiz.weekKey(), month = Quiz.monthKey();
    final d = (await _db.doc('quizUsers/${u.uid}').get()).data() ?? {};
    await _db.doc('quizUsers/${u.uid}').set({
      'chWins': FieldValue.increment(1),
      if (c.mode == 'duel') 'chWinsDuel': FieldValue.increment(1) else 'chWinsGroup': FieldValue.increment(1),
      'chWeek': week,
      'chWeekWins': d['chWeek'] == week ? FieldValue.increment(1) : 1,
      'chMonth': month,
      'chMonthWins': d['chMonth'] == month ? FieldValue.increment(1) : 1,
      'nick': _name,
    }, SetOptions(merge: true));
    await load();
  }

  Future<void> _remember(String code) async {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('myChallenges') ?? [];
    l.remove(code);
    l.insert(0, code);
    await p.setStringList('myChallenges', l.take(30).toList());
  }

  Future<List<Challenge>> mine() async {
    final p = await SharedPreferences.getInstance();
    final out = <Challenge>[];
    for (final code in p.getStringList('myChallenges') ?? const <String>[]) {
      try {
        final s = await _db.doc('challenges/$code').get();
        if (s.exists) out.add(Challenge.from(s.id, s.data()!));
      } catch (_) {}
    }
    return out;
  }

  /// Winners' board: period 'week', 'month' or 'all'. Names are shown.
  Future<List<LeaderWin>> board(String period) async {
    final field = period == 'week' ? 'chWeekWins' : period == 'month' ? 'chMonthWins' : 'chWins';
    final keyField = period == 'week' ? 'chWeek' : period == 'month' ? 'chMonth' : '';
    final key = period == 'week' ? Quiz.weekKey() : Quiz.monthKey();
    final me = Cloud.instance.user?.uid;
    final q = await _db.collection('quizUsers').orderBy(field, descending: true).limit(100).get();
    return [
      for (final d in q.docs)
        if ((keyField.isEmpty || d.data()[keyField] == key) && ((d.data()[field] as num?)?.toInt() ?? 0) > 0)
          LeaderWin('${d.data()['nick'] ?? 'طالب علم'}', (d.data()[field] as num).toInt(), d.id == me),
    ];
  }

  // ------------------------------------------------------------ more challenges
  Future<String?> requestMore(String note) async {
    final u = Cloud.instance.user;
    if (u == null) return 'سجّل الدخول أولاً.';
    try {
      await _db.collection('creditRequests').add({
        'uid': u.uid,
        'name': _name,
        'note': note.trim(),
        'status': 'pending',
        'at': FieldValue.serverTimestamp(),
      });
      return null;
    } catch (_) {
      return 'تعذّر الإرسال.';
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> requests() =>
      _db.collection('creditRequests').where('status', isEqualTo: 'pending').limit(100).snapshots();

  /// Staff: gives challenges to a reader (and closes his request).
  Future<String?> grant(String uid, int n, {String? requestId}) async {
    try {
      await _db.doc('quizUsers/$uid').set({'credits': FieldValue.increment(n)}, SetOptions(merge: true));
      if (requestId != null) {
        await _db.doc('creditRequests/$requestId').set({'status': 'done', 'given': n}, SetOptions(merge: true));
      }
      await Cloud.instance.logAction('التحدّيات: إرسال $n تحدّيات');
      return null;
    } catch (e) {
      return 'تعذّر الإرسال';
    }
  }

  Future<String?> reject(String requestId) async {
    try {
      await _db.doc('creditRequests/$requestId').set({'status': 'rejected'}, SetOptions(merge: true));
      return null;
    } catch (_) {
      return 'تعذّر';
    }
  }

  /// Staff: daily limit and the reading points switch.
  Future<String?> setSettings({int? perDay, bool? readPoints}) async {
    try {
      await _db.doc('config/quiz').set({
        if (perDay != null) 'chPerDay': perDay,
        if (readPoints != null) 'readPoints': readPoints,
      }, SetOptions(merge: true));
      if (perDay != null) this.perDay = perDay;
      if (readPoints != null) this.readPoints = readPoints;
      await Cloud.instance.logAction('التحدّيات: تعديل الإعدادات');
      notifyListeners();
      return null;
    } catch (_) {
      return 'تعذّر الحفظ';
    }
  }

  /// Reading points: every 10 answers read in a day give one challenge
  /// (at most 3 a day), when the sheikh has switched it on.
  Future<void> onRead() async {
    if (!readPoints) return;
    final u = Cloud.instance.user;
    if (u == null) return;
    final p = await SharedPreferences.getInstance();
    final k = 'readPts_${today()}';
    final n = (p.getInt(k) ?? 0) + 1;
    await p.setInt(k, n);
    if (n % 10 == 0 && n <= 30) {
      try {
        await _db.doc('quizUsers/${u.uid}').set({'credits': FieldValue.increment(1)}, SetOptions(merge: true));
        credits++;
        notifyListeners();
      } catch (_) {}
    }
  }

  /// Staff: numbers for every reader, worked out at most once a day.
  Future<List<Map<String, dynamic>>> staffStats({bool force = false}) async {
    final p = await SharedPreferences.getInstance();
    final day = today();
    if (!force && p.getString('chStatsDay') == day) {
      try {
        return [for (final e in (await Future.value(p.getStringList('chStats') ?? const <String>[]))) _decode(e)];
      } catch (_) {}
    }
    final q = await _db.collection('quizUsers').orderBy('chPlayed', descending: true).limit(200).get();
    final rows = [
      for (final d in q.docs)
        {
          'name': '${d.data()['nick'] ?? 'طالب علم'}',
          'played': (d.data()['chPlayed'] as num?)?.toInt() ?? 0,
          'wins': (d.data()['chWins'] as num?)?.toInt() ?? 0,
          'credits': (d.data()['credits'] as num?)?.toInt() ?? 0,
          'right': (d.data()['score'] as num?)?.toInt() ?? 0,
          'uid': d.id,
        }
    ];
    await p.setString('chStatsDay', day);
    await p.setStringList('chStats', [for (final r in rows) _encode(r)]);
    return rows;
  }

  static String _encode(Map<String, dynamic> r) =>
      [r['name'], r['played'], r['wins'], r['credits'], r['right'], r['uid']].join('\u0001');
  static Map<String, dynamic> _decode(String s) {
    final p = s.split('\u0001');
    return {
      'name': p[0],
      'played': int.tryParse(p[1]) ?? 0,
      'wins': int.tryParse(p[2]) ?? 0,
      'credits': int.tryParse(p[3]) ?? 0,
      'right': int.tryParse(p[4]) ?? 0,
      'uid': p.length > 5 ? p[5] : '',
    };
  }
}
