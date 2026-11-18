import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  /// Runs in the live database (no reads counted), not in Firestore.
  bool rt = false;
  /// A guest's view of a Firestore room: he does not follow every join (to
  /// save reads), only the start and the final board.
  bool partial = false;
  Challenge(this.code, this.host, this.hostName, this.mode, this.qids, this.secs, this.status, this.players, this.at,
      this.lobbyUntil, this.startAt, this.rematch, this.rematchBy);

  Map<String, dynamic> toMap() => {
        'host': host,
        'hostName': hostName,
        'mode': mode,
        'qids': qids,
        'secs': secs,
        'status': status,
        'at': at?.millisecondsSinceEpoch ?? 0,
        'lobbyUntil': lobbyUntil,
        'startAt': startAt,
        'rematch': rematch,
        'rematchBy': rematchBy,
        'players': {
          for (final p in players)
            p.uid: {'name': p.name, 'score': p.score, 'right': p.right, 'wrong': p.wrong, 'ms': p.ms, 'finished': p.finished}
        },
      };

  int get max => mode == 'duel' ? 2 : 30;
  bool get allFinished => players.isNotEmpty && players.every((p) => p.finished);
  int get now => DateTime.now().millisecondsSinceEpoch;
  bool get inLobby => status == 'lobby' && now < lobbyUntil;
  /// Nobody but the host came in.
  bool get empty => players.length < 2;
  /// Cancelled: nobody joined before the waiting time ended. Not counted.
  bool get cancelled => status == 'cancelled' || (status == 'lobby' && now >= lobbyUntil && empty);
  bool get playing => !over && !cancelled && (status == 'play' || (status == 'lobby' && now >= lobbyUntil));
  int get playStart => startAt > 0 ? startAt : lobbyUntil;
  /// The last moment anyone can still be answering.
  int get deadline => playStart + qids.length * secs * 1000 + 45000;

  bool get over =>
      cancelled ||
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
      m['at'] is Timestamp
          ? (m['at'] as Timestamp).toDate()
          : (m['at'] is num && (m['at'] as num) > 0 ? DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt()) : null),
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

  DateTime? _loadedAt;

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
        _loadedAt = DateTime.now();
      } catch (_) {}
    }
    notifyListeners();
  }

  int get left => math.max(0, perDay - usedToday) + credits;

  /// Takes one challenge from today's free ones, or else from the credits.
  /// The counters were read when the challenges page opened, so nothing is
  /// waited for here; the new count is saved in the background.
  Future<bool> _spend() async {
    final u = Cloud.instance.user;
    if (u == null) return false;
    if (_loadedAt == null || DateTime.now().difference(_loadedAt!).inMinutes >= 10) {
      try {
        await load().timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    if (_loadedAt != null && _loadedAt!.day != DateTime.now().day) usedToday = 0;
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
    _lastSpend = data.containsKey('credits') ? 'credit' : 'day';
    played++;
    unawaited(_db.doc('quizUsers/${u.uid}').set(data, SetOptions(merge: true)).catchError((_) {}));
    notifyListeners();
    return true;
  }

  String _lastSpend = 'day';

  /// Nobody joined: the host's phone marks the challenge cancelled and gives
  /// the day's challenge back (or the extra one), once.
  Future<void> cancelEmpty(Challenge c) async {
    final u = Cloud.instance.user;
    if (u == null || c.host != u.uid || !c.empty || c.status == 'cancelled') return;
    final p = await SharedPreferences.getInstance();
    final key = 'chRefund_${c.code}';
    if (p.getBool(key) == true) return;
    await p.setBool(key, true);
    try {
      if (c.rt) {
        await _rt.ref('ch/${c.code}').update({'status': 'cancelled'});
        _removeLater(c.code, const Duration(seconds: 20));
      } else {
        await _db.doc('challenges/${c.code}').update({'status': 'cancelled'});
      }
      final spent = p.getString('chSpend_${c.code}') ?? 'day';
      final data = <String, dynamic>{'chPlayed': FieldValue.increment(-1)};
      if (spent == 'credit') {
        credits++;
        data['credits'] = credits;
      } else if (usedToday > 0) {
        usedToday--;
        data['chUsed'] = usedToday;
      }
      if (played > 0) played--;
      await _db.doc('quizUsers/${u.uid}').set(data, SetOptions(merge: true));
      notifyListeners();
    } catch (_) {}
  }

  String get _name {
    final n = Quiz.instance.nick.trim();
    return n.isEmpty ? ((Cloud.instance.user?.displayName ?? '').trim().isNotEmpty ? Cloud.instance.user!.displayName!.trim() : 'طالب علم') : n;
  }

  String get myName => _name;

  // ------------------------------------------------------------ live database
  // Live rooms go to the Realtime Database: it counts no reads, only the size
  // sent (very small). Its free plan takes 100 phones connected at once; when
  // it is full (or not reachable) the room goes to Firestore instead, the
  // saving way. Room numbers tell where a room is: 10000–49999 live,
  // 50000–99999 Firestore.
  static const rtUrl = 'https://ibn-alshabira-default-rtdb.firebaseio.com';
  FirebaseDatabase get _rt => FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: rtUrl);
  DateTime? _rtFailedAt;
  bool _rtOnline = false;
  int _rooms = 0;

  /// For the Friday tournament (it shares the live connection).
  Future<bool> rtOk() => _rtOk();
  FirebaseDatabase get rtDb => _rt;
  http.Client get web => _http;

  static bool isRtCode(String code) {
    final n = int.tryParse(code.trim()) ?? 0;
    return n >= 10000 && n < 50000;
  }

  /// Connects to the live database; false when it is full, not made yet, or
  /// the network is weak (then Firestore is used).
  Future<bool> _rtOk() async {
    if (_rtFailedAt != null && DateTime.now().difference(_rtFailedAt!).inSeconds < 90) return false;
    try {
      await _rt.goOnline();
      _rtOnline = true;
      final ok = await _rt
          .ref('.info/connected')
          .onValue
          .map((e) => e.snapshot.value == true)
          .firstWhere((v) => v)
          .timeout(const Duration(seconds: 6));
      return ok;
    } catch (_) {
      _rtFailedAt = DateTime.now();
      _rtIdle(now: true);
      return false;
    }
  }

  /// A room page opened / closed: the live connection is kept only while a
  /// room is open, so idle phones never hold one of the 100 places.
  void roomOpened() => _rooms++;
  void roomClosed() {
    _rooms = math.max(0, _rooms - 1);
    Future.delayed(const Duration(seconds: 20), () => _rtIdle());
  }

  void _rtIdle({bool now = false}) {
    if (!_rtOnline || (!now && _rooms > 0)) return;
    try {
      unawaited(_rt.goOffline().catchError((_) {}));
    } catch (_) {}
    _rtOnline = false;
  }

  static dynamic _plain(Object? v) {
    if (v is Map) return <String, dynamic>{for (final e in v.entries) '${e.key}': _plain(e.value)};
    if (v is List) return [for (final x in v) if (x != null) _plain(x)];
    return v;
  }

  Challenge? _fromRt(String code, Object? v) {
    if (v is! Map) return null;
    final c = Challenge.from(code, _plain(v) as Map<String, dynamic>)..rt = true;
    return c;
  }

  /// The host's phone deletes a finished live room after a while (every
  /// player keeps its result on his phone).
  void _removeLater(String code, Duration after) {
    Future.delayed(after, () async {
      try {
        await _rt.ref('ch/$code').remove();
      } catch (_) {}
    });
  }

  /// Old live rooms of this host that were left behind (the app was closed
  /// before it could delete them).
  Future<void> _cleanOld() async {
    final u = Cloud.instance.user;
    if (u == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final code in p.getStringList('myChallenges') ?? const <String>[]) {
        if (!isRtCode(code) || p.getBool('chHost_$code') != true || p.getBool('chGone_$code') == true) continue;
        final at = p.getInt('chAt_$code') ?? 0;
        if (now - at < 30 * 60000) continue;
        await _rt.ref('ch/$code').remove();
        await p.setBool('chGone_$code', true);
      }
    } catch (_) {}
  }

  // ------------------------------------------------------------ questions
  /// The questions inside the app are there at once; the newer ones from the
  /// site file keep loading in the background (nobody waits for them).
  Future<void> _questionsReady() async {
    final quiz = Quiz.instance;
    if (quiz.all.isEmpty) {
      try {
        await quiz.load().timeout(const Duration(seconds: 12));
      } catch (_) {}
    } else {
      unawaited(quiz.load());
    }
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

    final pool = quiz.liveAll
        .where((q) => q.type != QuizType.order && !q.multi && from(q) && (level == 0 || q.level == level))
        .toList()
      ..shuffle();
    bool fresh(QuizQ q) => !quiz.marks.containsKey(q.id);
    // The challenge-only questions first (nobody could practise them), new
    // ones before seen ones; practice questions only if those run out.
    final order = [
      ...pool.where((q) => q.challengeOnly && fresh(q)),
      ...pool.where((q) => !q.challengeOnly && fresh(q)),
      ...pool.where((q) => q.challengeOnly && !fresh(q)),
      ...pool.where((q) => !q.challengeOnly && !fresh(q)),
    ];
    return order.take(count).map((q) => q.id).toList();
  }

  Future<(String?, String?)> create(
      {required String mode, String cat = '', String books = '', int level = 0, int count = 5, int secs = 15}) async {
    final u = Cloud.instance.user;
    if (u == null) return (null, 'سجّل الدخول أولاً لتبدأ تحدّياً.');
    await _questionsReady();
    final qids = pick(cat: cat, books: books, level: level, count: count);
    if (qids.length < 3) return (null, 'لا توجد أسئلة كافية لهذا الاختيار بعد.');
    final live = await _rtOk();
    if (!await _spend()) return (null, 'انتهت تحدّياتك اليوم. اطلب من الشيخ تحدّيات إضافية.');
    final rnd = math.Random();
    final room = <String, dynamic>{
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
      'players': {
        u.uid: {'name': _name, 'score': 0, 'right': 0, 'wrong': 0, 'ms': 0, 'finished': false}
      },
    };
    String? code;
    if (live) {
      for (var tries = 0; tries < 6 && code == null; tries++) {
        final c = '${10000 + rnd.nextInt(40000)}';
        try {
          // The rules refuse writing over someone else's room: a used number fails and another is tried.
          await _rt.ref('ch/$c').set({...room, 'at': ServerValue.timestamp}).timeout(const Duration(seconds: 8));
          code = c;
        } catch (_) {}
      }
      if (code != null) unawaited(_cleanOld());
    }
    if (code == null) {
      for (var tries = 0; tries < 6 && code == null; tries++) {
        final c = '${50000 + rnd.nextInt(50000)}';
        final ref = _db.doc('challenges/$c');
        try {
          final ok = await _db.runTransaction<bool>((t) async {
            final snap = await t.get(ref);
            if (snap.exists) return false;
            t.set(ref, {...room, 'at': FieldValue.serverTimestamp()});
            return true;
          });
          if (ok) {
            code = c;
            // The small page the guests follow: the start and the final board only.
            unawaited(_db.doc('challenges/${c}s').set({'host': u.uid, 'status': 'lobby'}).catchError((_) {}));
          }
        } catch (e) {
          break;
        }
      }
    }
    if (code == null) {
      await _refund(u.uid);
      return (null, 'تعذّر إنشاء التحدّي، تأكد من الاتصال.');
    }
    await _remember(code, host: true);
    try {
      (await SharedPreferences.getInstance()).setString('chSpend_$code', _lastSpend);
    } catch (_) {}
    return (code, null);
  }

  /// Gives back a challenge that was spent but could not be made.
  Future<void> _refund(String uid) async {
    final data = <String, dynamic>{'chPlayed': FieldValue.increment(-1)};
    if (_lastSpend == 'credit') {
      credits++;
      data['credits'] = credits;
    } else if (usedToday > 0) {
      usedToday--;
      data['chUsed'] = usedToday;
    }
    if (played > 0) played--;
    unawaited(_db.doc('quizUsers/$uid').set(data, SetOptions(merge: true)).catchError((_) {}));
    notifyListeners();
  }

  /// Reads a room once, wherever it is.
  Future<Challenge?> _once(String code) async {
    if (isRtCode(code) && await _rtOk()) {
      try {
        final s = await _rt.ref('ch/$code').once().timeout(const Duration(seconds: 8));
        final c = _fromRt(code, s.snapshot.value);
        if (c != null) return c;
      } catch (_) {}
    }
    final snap = await _db.doc('challenges/$code').get();
    return snap.exists ? Challenge.from(snap.id, snap.data()!) : null;
  }

  Future<String?> join(String code) async {
    final u = Cloud.instance.user;
    if (u == null) return 'سجّل الدخول أولاً لتدخل التحدّي.';
    code = code.trim();
    await _questionsReady();
    Challenge? c;
    try {
      c = await _once(code);
    } catch (_) {
      return 'تعذّر الاتصال، حاول مرة أخرى.';
    }
    if (c == null) {
      return isRtCode(code) && _rtFailedAt != null
          ? 'غرف التحدّي المباشر ممتلئة الآن أو الاتصال ضعيف، حاول بعد دقيقة.'
          : 'لا يوجد تحدٍّ بهذا الرمز.';
    }
    if (c.players.any((p) => p.uid == u.uid)) return null; // already inside
    if (c.over) return 'انتهى هذا التحدّي.';
    if (!c.inLobby) return 'بدأ هذا التحدّي، فلا يمكن الدخول الآن.';
    if (c.players.length >= c.max) return 'التحدّي ممتلئ.';
    if (!await _spend()) return 'انتهت تحدّياتك اليوم. اطلب من الشيخ تحدّيات إضافية.';
    final me = {'name': _name, 'score': 0, 'right': 0, 'wrong': 0, 'ms': 0, 'finished': false};
    try {
      if (c.rt) {
        await _rt.ref('ch/$code/players/${u.uid}').set(me);
      } else {
        await _db.doc('challenges/$code').update({'players.${u.uid}': me});
        _guestBase[code] = {...c.toMap(), 'players': {...c.toMap()['players'] as Map, u.uid: me}};
      }
    } catch (_) {
      await _refund(u.uid);
      return 'تعذّر الدخول، حاول مرة أخرى.';
    }
    await _remember(code);
    return null;
  }

  // A Firestore guest's copy of the room (read once when he joined).
  final Map<String, Map<String, dynamic>> _guestBase = {};
  final Map<String, Map<String, dynamic>> _myResult = {};

  /// Follows a room. Live rooms: every change at once, no reads counted.
  /// Firestore rooms: the host follows the room; a guest follows only the
  /// small start/final page, so 30 players cost about 150 reads in all.
  Stream<Challenge?> watch(String code) async* {
    code = code.trim();
    final uid = Cloud.instance.user?.uid;
    if (isRtCode(code) && await _rtOk()) {
      Challenge? first;
      try {
        first = _fromRt(code, (await _rt.ref('ch/$code').once().timeout(const Duration(seconds: 8))).snapshot.value);
      } catch (_) {}
      if (first != null) {
        yield first;
        yield* _rt.ref('ch/$code').onValue.map((e) {
          final c = _fromRt(code, e.snapshot.value);
          if (c != null) _lastSeen[code] = c;
          return c ?? _gone(code);
        });
        return;
      }
    }
    Map<String, dynamic>? base = _guestBase[code];
    if (base == null) {
      final s = await _db.doc('challenges/$code').get();
      if (!s.exists) {
        yield await _savedRoom(code);
        return;
      }
      base = s.data()!;
    }
    final c0 = Challenge.from(code, base);
    if (uid == null || c0.host == uid || !c0.players.any((p) => p.uid == uid) || c0.over) {
      yield* _db.doc('challenges/$code').snapshots().map((s) => s.exists ? Challenge.from(s.id, s.data()!) : null);
      return;
    }
    yield* _guestStream(code, base);
  }

  Challenge? _gone(String code) => _lastSeen[code];
  final Map<String, Challenge> _lastSeen = {};

  Stream<Challenge?> _guestStream(String code, Map<String, dynamic> base) {
    late StreamController<Challenge?> ctl;
    StreamSubscription? sub;
    Timer? late_;
    var state = <String, dynamic>{};
    var finalBoard = false;
    Challenge build() {
      final m = {...base, ...state};
      final uid = Cloud.instance.user?.uid;
      final ps = Map<String, dynamic>.from((m['players'] ?? {}) as Map);
      if (uid != null && _myResult[code] != null && !finalBoard) ps[uid] = _myResult[code];
      m['players'] = ps;
      return Challenge.from(code, m)..partial = !finalBoard;
    }

    Future<void> fetchAll() async {
      if (finalBoard) return;
      try {
        final s = await _db.doc('challenges/$code').get();
        if (s.exists) {
          base = s.data()!;
          state = {};
          finalBoard = true;
          if (!ctl.isClosed) ctl.add(build());
        }
      } catch (_) {}
    }

    ctl = StreamController<Challenge?>(onListen: () {
      ctl.add(build());
      sub = _db.doc('challenges/${code}s').snapshots().listen((s) {
        final d = s.data();
        if (d == null) return;
        state = {
          if (d['status'] != null) 'status': d['status'],
          if (d['startAt'] != null) 'startAt': d['startAt'],
          if (d['rematch'] != null) 'rematch': d['rematch'],
          if (d['rematchBy'] != null) 'rematchBy': d['rematchBy'],
          if (d['players'] is Map) 'players': d['players'],
        };
        if (d['status'] == 'done' && d['players'] is Map) finalBoard = true;
        ctl.add(build());
        late_?.cancel();
        final c = build();
        // The host's phone was closed before it sent the board: read it once.
        final wait = c.deadline - DateTime.now().millisecondsSinceEpoch + 5000;
        late_ = Timer(Duration(milliseconds: math.max(1000, wait)), fetchAll);
      }, onError: (_) {});
      final c = build();
      late_ = Timer(Duration(milliseconds: math.max(1000, c.deadline - DateTime.now().millisecondsSinceEpoch + 5000)), fetchAll);
    }, onCancel: () {
      sub?.cancel();
      late_?.cancel();
    });
    return ctl.stream;
  }

  /// The host starts before the two minutes are up.
  Future<void> startNow(Challenge c) async {
    final at = DateTime.now().millisecondsSinceEpoch;
    if (c.rt) {
      await _rt.ref('ch/${c.code}').update({'status': 'play', 'startAt': at});
      return;
    }
    await _db.doc('challenges/${c.code}').update({'status': 'play', 'startAt': at});
    try {
      await _db.doc('challenges/${c.code}s').set({'host': c.host, 'status': 'play', 'startAt': at}, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Sends the reader's result once, at the end (one write for the game).
  Future<void> finish(Challenge c, {required int right, required int wrong, required int score, required int ms}) async {
    final u = Cloud.instance.user;
    if (u == null) return;
    final me = {'name': _name, 'score': score, 'right': right, 'wrong': wrong, 'ms': ms, 'finished': true};
    _myResult[c.code] = me;
    try {
      if (c.rt) {
        await _rt.ref('ch/${c.code}/players/${u.uid}').set(me);
      } else {
        await _db.doc('challenges/${c.code}').update({
          'players.${u.uid}': me,
          if (c.status == 'lobby' && c.host == u.uid) 'status': 'play',
        });
      }
    } catch (_) {}
  }

  /// The end, seen on the host's phone: Firestore guests get the whole board
  /// in their small page (one read each); a live room is deleted later.
  Future<void> ended(Challenge c) async {
    await saveRoom(c);
    final u = Cloud.instance.user;
    if (u == null || c.host != u.uid || c.cancelled) return;
    final p = await SharedPreferences.getInstance();
    final key = 'chEnded_${c.code}';
    if (p.getBool(key) == true) return;
    await p.setBool(key, true);
    if (c.rt) {
      _removeLater(c.code, const Duration(minutes: 3));
      return;
    }
    try {
      await _db.doc('challenges/${c.code}s').set({
        'host': c.host,
        'status': 'done',
        'players': c.toMap()['players'],
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// «إعادة»: a new room with the same kind of questions; the others see a
  /// button to join it (each one spends one of his challenges).
  Future<(String?, String?)> rematch(Challenge c) async {
    Map<String, dynamic> m = {};
    try {
      if (c.rt) {
        m = (_plain((await _rt.ref('ch/${c.code}').once()).snapshot.value) as Map<String, dynamic>?) ?? {};
      } else {
        m = (await _db.doc('challenges/${c.code}').get()).data() ?? {};
      }
    } catch (_) {}
    final r = await create(
        mode: c.mode, cat: '${m['cat'] ?? ''}', books: '${m['books'] ?? ''}', level: (m['level'] as num?)?.toInt() ?? 0, count: c.qids.length);
    if (r.$1 != null) {
      try {
        if (c.rt) {
          await _rt.ref('ch/${c.code}').update({'rematch': r.$1, 'rematchBy': _name});
        } else {
          await _db.doc('challenges/${c.code}').update({'rematch': r.$1, 'rematchBy': _name});
          await _db.doc('challenges/${c.code}s').set({'host': c.host, 'rematch': r.$1, 'rematchBy': _name}, SetOptions(merge: true));
        }
      } catch (_) {}
    }
    return r;
  }

  Future<void> close(Challenge c) => c.rt
      ? _rt.ref('ch/${c.code}').update({'status': 'done'})
      : _db.doc('challenges/${c.code}').update({'status': 'done'});

  /// Counts the win once, when the reader sees the final board.
  Future<void> countResult(Challenge c) async {
    final u = Cloud.instance.user;
    if (u == null || !c.over || c.players.length < 2 || c.partial) return;
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

  Future<void> _remember(String code, {bool host = false}) async {
    final p = await SharedPreferences.getInstance();
    final l = p.getStringList('myChallenges') ?? [];
    l.remove(code);
    l.insert(0, code);
    await p.setStringList('myChallenges', l.take(30).toList());
    await p.setInt('chAt_$code', DateTime.now().millisecondsSinceEpoch);
    if (host) await p.setBool('chHost_$code', true);
  }

  /// Keeps the room on the phone (the reader's record), so it opens later
  /// with no reads, even after the live room is deleted.
  Future<void> saveRoom(Challenge c) async {
    if (c.partial) return;
    _lastSeen[c.code] = c;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('chSaved_${c.code}', jsonEncode({...c.toMap(), 'rt': c.rt}));
    } catch (_) {}
  }

  Future<Challenge?> _savedRoom(String code) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('chSaved_$code');
      if (s == null) return null;
      final m = Map<String, dynamic>.from(jsonDecode(s) as Map);
      return Challenge.from(code, m)..rt = m['rt'] == true;
    } catch (_) {
      return null;
    }
  }

  /// «تحدّياتي»: the finished ones from the phone; only unfinished ones are read.
  Future<List<Challenge>> mine() async {
    final p = await SharedPreferences.getInstance();
    final out = <Challenge>[];
    for (final code in p.getStringList('myChallenges') ?? const <String>[]) {
      final saved = await _savedRoom(code);
      if (saved != null && saved.over) {
        out.add(saved);
        continue;
      }
      try {
        Challenge? c;
        if (isRtCode(code) && _rtOnline) {
          c = _fromRt(code, (await _rt.ref('ch/$code').once().timeout(const Duration(seconds: 5))).snapshot.value);
        } else if (!isRtCode(code) || p.getString('chSaved_$code') == null) {
          final s = await _db.doc('challenges/$code').get();
          if (s.exists) c = Challenge.from(s.id, s.data()!);
        }
        c ??= saved;
        if (c != null) {
          out.add(c);
          if (c.over) await saveRoom(c);
        }
      } catch (_) {
        if (saved != null) out.add(saved);
      }
    }
    return out;
  }

  // ------------------------------------------------------------ invites
  /// Invites a reader by his six-digit number: a small note in the live
  /// database that his app picks up (with a notification on Android).
  Future<String?> invite(String no, Challenge c) async {
    final u = Cloud.instance.user;
    no = no.trim();
    if (u == null) return 'سجّل الدخول أولاً.';
    if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(no)) return 'اكتب رقمه (6 أرقام).';
    try {
      final token = await u.getIdToken();
      final r = await _http
          .put(Uri.parse('$rtUrl/inv/$no/${c.code}.json?auth=$token'),
              body: jsonEncode({'by': _name, 'mode': c.mode, 'at': {'.sv': 'timestamp'}}))
          .timeout(const Duration(seconds: 10));
      return r.statusCode == 200 ? null : 'تعذّر إرسال الدعوة.';
    } catch (_) {
      return 'تعذّر إرسال الدعوة، تأكد من الاتصال.';
    }
  }

  final _http = http.Client();
  Timer? _invTimer;
  final Set<String> _seenInv = {};

  /// Called with each new invite (the app shows it and a notification).
  void Function(String code, String by, String mode)? onInvite;

  /// Looks for invites every 30 seconds while the app is open. A plain small
  /// request (no lasting connection), so idle phones take no live place.
  void startInvites() {
    _invTimer?.cancel();
    _invTimer = Timer.periodic(const Duration(seconds: 30), (_) => checkInvites());
    checkInvites();
  }

  void stopInvites() => _invTimer?.cancel();

  bool _checking = false;
  Future<void> checkInvites() async {
    final u = Cloud.instance.user;
    if (u == null || _checking) return;
    _checking = true;
    try {
      final no = askerNo(u.uid);
      final token = await u.getIdToken();
      final r = await _http.get(Uri.parse('$rtUrl/inv/$no.json?auth=$token')).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final m = jsonDecode(r.body);
      if (m is! Map) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in m.entries) {
        final code = '${e.key}';
        final v = e.value is Map ? e.value as Map : const {};
        final at = (v['at'] as num?)?.toInt() ?? 0;
        unawaited(_http.delete(Uri.parse('$rtUrl/inv/$no/$code.json?auth=$token')).catchError((_) => http.Response('', 0)));
        if (now - at > 150000 || !_seenInv.add(code)) continue; // older than the waiting time
        onInvite?.call(code, '${v['by'] ?? 'أحد القرّاء'}', '${v['mode'] ?? 'duel'}');
      }
    } catch (_) {
    } finally {
      _checking = false;
    }
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
