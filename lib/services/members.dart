import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
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
    final checked = p.getInt('membersChecked') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // The server renews the list every six hours: read it again only then.
    if (!force && at != null && DateTime.now().difference(at!) < _every) return;
    if (!force && now - checked < const Duration(hours: 1).inMilliseconds) return;
    await p.setInt('membersChecked', now);
    final u = Cloud.instance.user;
    if (u == null || !Cloud.instance.isAdmin) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      // The server puts everyone in one or two documents four times a day.
      final db = FirebaseFirestore.instance;
      final meta = (await db.doc('adminData/members_meta').get()).data();
      if (meta == null) throw 'لم تُجهَّز القائمة بعد، تظهر بعد أول تحديث للخادم';
      final n = (meta['chunks'] as num?)?.toInt() ?? 0;
      final all = <Member>[];
      for (var i = 0; i < n; i++) {
        final c = (await db.doc('adminData/members_$i').get()).data();
        final m = jsonDecode('${c?['l'] ?? '{}'}') as Map<String, dynamic>;
        for (final e in m.entries) {
          final r = Map<String, dynamic>.from(e.value as Map);
          DateTime? t(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
          all.add(Member(e.key, (r['s'] as num?)?.toInt() ?? 0, t(r['j']), t(r['v']),
              Map<String, dynamic>.from(r['c'] as Map? ?? const {})));
        }
      }
      all.sort((a, b) => a.seq.compareTo(b.seq));
      list = all;
      at = DateTime.tryParse('${meta['at'] ?? ''}')?.toLocal() ?? DateTime.now();
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
}
