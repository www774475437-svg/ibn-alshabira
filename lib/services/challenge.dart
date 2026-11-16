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
  final int score, done;
  final bool finished;
  ChPlayer(this.uid, this.name, this.score, this.done, this.finished);
}

/// A challenge between two people, or a group, on the same questions.
/// Everyone answers at his own pace; the board updates live for all.
/// There is no messaging between players: names and scores only.
class Challenge {
  final String code, host, hostName, mode; // duel | group
  final List<String> qids;
  final int secs;
  final String status; // open | done
  final List<ChPlayer> players;
  final DateTime? at;
  Challenge(this.code, this.host, this.hostName, this.mode, this.qids, this.secs, this.status, this.players, this.at);

  int get max => mode == 'duel' ? 2 : 30;
  bool get allFinished => players.isNotEmpty && players.every((p) => p.finished);

  /// Over when everyone finished, the host closed it, or a day has passed.
  bool get over =>
      status == 'done' || (allFinished && players.length >= 2) || (at != null && DateTime.now().difference(at!).inHours >= 24);

  List<ChPlayer> get ranked => [...players]..sort((a, b) => b.score != a.score ? b.score.compareTo(a.score) : b.done.compareTo(a.done));

  factory Challenge.from(String code, Map<String, dynamic> m) {
    final ps = <ChPlayer>[];
    for (final e in ((m['players'] ?? {}) as Map).entries) {
      final p = e.value as Map;
      ps.add(ChPlayer('${e.key}', '${p['name'] ?? ''}', (p['score'] as num?)?.toInt() ?? 0,
          (p['done'] as num?)?.toInt() ?? 0, p['finished'] == true));
    }
    return Challenge(
      code,
      '${m['host'] ?? ''}',
      '${m['hostName'] ?? ''}',
      '${m['mode'] ?? 'duel'}',
      [for (final q in (m['qids'] as List? ?? const [])) '$q'],
      (m['secs'] as num?)?.toInt() ?? 0,
      '${m['status'] ?? 'open'}',
      ps,
      m['at'] is Timestamp ? (m['at'] as Timestamp).toDate() : null,
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
  List<String> pick({String cat = '', int level = 0, int count = 5}) {
    final quiz = Quiz.instance;
    final pool = quiz.live
        .where((q) => q.type != QuizType.order && !q.multi && (cat.isEmpty || q.cat == cat) && (level == 0 || q.level == level))
        .toList()
      ..shuffle();
    final fresh = pool.where((q) => !quiz.marks.containsKey(q.id)).toList();
    final seen = pool.where((q) => quiz.marks.containsKey(q.id)).toList();
    return [...fresh, ...seen].take(count).map((q) => q.id).toList();
  }

  Future<(String?, String?)> create({required String mode, String cat = '', int level = 0, int count = 5, int secs = 30}) async {
    final u = Cloud.instance.user;
    if (u == null) return (null, 'سجّل الدخول أولاً لتبدأ تحدّياً.');
    final qids = pick(cat: cat, level: level, count: count);
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
            'secs': secs,
            'status': 'open',
            'at': FieldValue.serverTimestamp(),
            'players': {
              u.uid: {'name': _name, 'score': 0, 'done': 0, 'finished': false}
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
    if (c.players.length >= c.max) return 'التحدّي ممتلئ.';
    if (!await _spend()) return 'انتهت تحدّياتك اليوم. اطلب من الشيخ تحدّيات إضافية.';
    await ref.update({
      'players.${u.uid}': {'name': _name, 'score': 0, 'done': 0, 'finished': false}
    });
    await _remember(code.trim());
    return null;
  }

  Stream<Challenge?> watch(String code) => _db
      .doc('challenges/$code')
      .snapshots()
      .map((s) => s.exists ? Challenge.from(s.id, s.data()!) : null);

  /// Records one answer of the reader in the challenge.
  Future<void> answer(Challenge c, int index, bool ok, int secondsLeft) async {
    final u = Cloud.instance.user;
    if (u == null) return;
    final me = c.players.firstWhere((p) => p.uid == u.uid, orElse: () => ChPlayer(u.uid, _name, 0, 0, false));
    final gain = ok ? 10 + (c.secs > 0 ? math.max(0, secondsLeft) ~/ 3 : 0) : 0;
    final done = index + 1;
    await _db.doc('challenges/${c.code}').update({
      'players.${u.uid}.score': me.score + gain,
      'players.${u.uid}.done': done,
      'players.${u.uid}.finished': done >= c.qids.length,
    });
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
