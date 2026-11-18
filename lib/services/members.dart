import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart';
import 'challenge.dart';
import 'cloud.dart';
import 'progress.dart';
import 'quiz.dart';

/// One registered reader, as the staff see him in «المسجّلون».
class Member {
  final String uid;
  final int seq; // 1 = the first who registered
  final DateTime? joined, seen;
  final Map<String, dynamic> card;
  Member(this.uid, this.seq, this.joined, this.seen, this.card);

  String get name {
    final n = '${card['name'] ?? ''}'.trim();
    final k = '${card['nick'] ?? ''}'.trim();
    if (n.isNotEmpty) return n;
    if (k.isNotEmpty && k != 'طالب علم') return k;
    return '';
  }

  int n(String k) => (card[k] as num?)?.toInt() ?? 0;
  List<String> get badges => [for (final b in (card['badges'] as List? ?? const [])) '$b'];
  bool get hasCard => card.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'u': uid,
        's': seq,
        'j': joined?.millisecondsSinceEpoch,
        'v': seen?.millisecondsSinceEpoch,
        'c': card,
      };

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        '${j['u']}',
        (j['s'] as num).toInt(),
        j['j'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['j'] as num).toInt()),
        j['v'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['v'] as num).toInt()),
        Map<String, dynamic>.from(j['c'] as Map? ?? const {}),
      );
}

/// Everyone who registered, for the staff. Each reader's phone sends his
/// own summary («بطاقته») at most once every six hours, inside his own
/// document; the staff phone reads the list at most once every six hours
/// and keeps it, so opening the page again costs nothing.
class Members extends ChangeNotifier {
  Members._();
  static final Members instance = Members._();

  static const _every = Duration(hours: 6);
  List<Member> list = [];
  DateTime? at;
  bool loading = false;
  String? error;

  // ------------------------------------------------------------ the reader
  /// The reader's own summary, sent with nothing else, once in six hours.
  static Future<void> pushCard() async {
    final u = Cloud.instance.user;
    if (u == null || !Cloud.instance.ready) return;
    try {
      final p = await SharedPreferences.getInstance();
      final last = p.getInt('cardAt') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _every.inMilliseconds) return;
      await p.setInt('cardAt', now);
      final quiz = Quiz.instance;
      final ch = Challenges.instance;
      final repo = Repository.instance;
      await FirebaseFirestore.instance.doc('users/${u.uid}').set({
        'card': {
          'name': (u.displayName ?? '').trim(),
          'nick': quiz.nick.trim(),
          'joined': u.metadata.creationTime?.millisecondsSinceEpoch,
          'seen': now,
          'no': askerNo(u.uid),
          'days': repo.streak,
          'reads': Progress.reads,
          'month': repo.readThisMonth,
          'listens': Progress.listens,
          'hifz': Progress.hifzPages,
          'pts': Progress.points,
          'badges': [for (final b in Progress.badges) if (b.$4) b.$2],
          'right': quiz.right,
          'wrong': quiz.wrong,
          'chPlayed': ch.played,
          'chWins': ch.wins,
          'web': kIsWeb,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('card: $e');
    }
  }

  // ------------------------------------------------------------- the staff
  Future<void> load({bool force = false}) async {
    if (loading) return;
    final p = await SharedPreferences.getInstance();
    if (list.isEmpty) {
      try {
        final raw = p.getString('membersCache');
        if (raw != null) {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          at = DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt());
          list = [for (final x in (m['l'] as List)) Member.fromJson(Map<String, dynamic>.from(x as Map))];
          notifyListeners();
        }
      } catch (_) {}
    }
    if (!force && at != null && DateTime.now().difference(at!) < _every) return;
    final u = Cloud.instance.user;
    if (u == null || !Cloud.instance.isAdmin) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final token = await u.getIdToken();
      final rows = <(String, DateTime?, Map<String, dynamic>)>[];
      String? page;
      do {
        final url = Uri.parse('https://firestore.googleapis.com/v1/projects/ibn-alshabira/databases/(default)/documents/users'
            '?pageSize=300&mask.fieldPaths=card${page == null ? '' : '&pageToken=${Uri.encodeQueryComponent(page)}'}');
        final r = await http.get(url, headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 40));
        if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
        final m = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
        for (final d in (m['documents'] as List? ?? const [])) {
          final doc = Map<String, dynamic>.from(d as Map);
          final uid = '${doc['name']}'.split('/').last;
          final fields = Map<String, dynamic>.from(doc['fields'] as Map? ?? const {});
          final card = fields['card'] == null ? <String, dynamic>{} : Map<String, dynamic>.from(_val(fields['card']) as Map);
          rows.add((uid, DateTime.tryParse('${doc['createTime']}'), card));
        }
        page = m['nextPageToken'] as String?;
      } while (page != null);
      // The order of registering: the account's own date when the reader
      // sent it, otherwise the day his record was first made.
      DateTime? joinOf((String, DateTime?, Map<String, dynamic>) r) {
        final j = r.$3['joined'];
        if (j is num) return DateTime.fromMillisecondsSinceEpoch(j.toInt());
        return r.$2;
      }

      rows.sort((a, b) {
        final x = joinOf(a), y = joinOf(b);
        if (x == null && y == null) return a.$1.compareTo(b.$1);
        if (x == null) return 1;
        if (y == null) return -1;
        return x.compareTo(y);
      });
      list = [
        for (var i = 0; i < rows.length; i++)
          Member(rows[i].$1, i + 1, joinOf(rows[i]),
              rows[i].$3['seen'] is num ? DateTime.fromMillisecondsSinceEpoch((rows[i].$3['seen'] as num).toInt()) : null,
              rows[i].$3)
      ];
      at = DateTime.now();
      await p.setString(
          'membersCache', jsonEncode({'at': at!.millisecondsSinceEpoch, 'l': [for (final m in list) m.toJson()]}));
    } catch (e) {
      error = 'تعذّر التحديث: $e';
    }
    loading = false;
    notifyListeners();
  }

  Member? byUid(String uid) => list.where((m) => m.uid == uid).firstOrNull;

  int joinedSince(DateTime from) => list.where((m) => m.joined != null && !m.joined!.isBefore(from)).length;

  /// A Firestore REST value as plain Dart.
  static Object? _val(Object? v) {
    if (v is! Map) return v;
    if (v.containsKey('stringValue')) return v['stringValue'];
    if (v.containsKey('integerValue')) return int.tryParse('${v['integerValue']}') ?? 0;
    if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
    if (v.containsKey('booleanValue')) return v['booleanValue'] == true;
    if (v.containsKey('nullValue')) return null;
    if (v.containsKey('timestampValue')) return DateTime.tryParse('${v['timestampValue']}')?.millisecondsSinceEpoch;
    if (v.containsKey('arrayValue')) {
      return [for (final x in ((v['arrayValue'] as Map)['values'] as List? ?? const [])) _val(x)];
    }
    if (v.containsKey('mapValue')) {
      final f = Map<String, dynamic>.from((v['mapValue'] as Map)['fields'] as Map? ?? const {});
      return {for (final e in f.entries) e.key: _val(e.value)};
    }
    return null;
  }
}
