import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/challenge.dart';
import '../services/cloud.dart';
import '../services/progress.dart';
import '../services/quiz.dart';
import '../services/site_files.dart';
import '../theme.dart';
import 'challenge_screens.dart' show ChallengePlay;

/// «تحدّي اليوم»: the same five questions for every reader each day (by
/// Mecca's date), once a day. The result goes with the reader's profile; the
/// day's board comes from the server file (no extra reads).
class DailyChallenge {
  /// Today in Mecca (so everyone shares the same day).
  static String get today {
    final d = DateTime.now().toUtc().add(const Duration(hours: 3));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// The day's five questions: chosen the same way on every phone, from the
  /// questions built into the app.
  static List<QuizQ> questions([String? day]) {
    final key = day ?? today;
    final pool = Quiz.instance.liveAll
        .where((q) => q.id.startsWith('b_') && q.type == QuizType.choice && !q.multi && q.choices.length >= 2)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (pool.length < 5) return pool;
    final r = math.Random(int.parse(key.replaceAll('-', '')));
    final picked = <QuizQ>[];
    final used = <int>{};
    while (picked.length < 5) {
      final i = r.nextInt(pool.length);
      if (used.add(i)) picked.add(pool[i]);
    }
    return picked;
  }

  static bool get playedToday => Progress.daily?['d'] == today;

  static Future<void> save(int right, int score, int ms) async {
    final m = {'d': today, 'r': right, 's': score, 'ms': ms};
    Progress.daily = m;
    final p = await SharedPreferences.getInstance();
    await p.setString('dailyChallenge', jsonEncode(m));
    Quiz.instance.profileChanged(); // goes with the next profile send
  }
}

class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  List<Map<String, dynamic>> _board = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Progress.load();
    if (Quiz.instance.all.isEmpty) {
      try {
        await Quiz.instance.load().timeout(const Duration(seconds: 12));
      } catch (_) {}
    }
    try {
      final m = await SiteFiles.get('daily.json');
      final days = (m?['days'] as Map?) ?? const {};
      _board = [for (final x in (days[DailyChallenge.today] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _play() async {
    final qs = DailyChallenge.questions();
    if (qs.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الأسئلة لم تجهز بعد، حاول بعد قليل.')));
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final c = Challenge('d${DailyChallenge.today}', '', '', 'duel', [for (final q in qs) q.id], 15, 'play', const [], null,
        now, now, '', '');
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChallengePlay(
              c: c,
              qs: qs,
              onDone: (right, wrong, score, ms) => DailyChallenge.save(right, score, ms),
            )));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mine = Progress.daily;
    final played = DailyChallenge.playedToday;
    final myNo = Cloud.instance.user == null ? 0 : askerNo(Cloud.instance.user!.uid);
    return Scaffold(
      appBar: AppBar(title: const Text('تحدّي اليوم')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(14), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(colors: [Color(0xFF0B1230), Color(0xFF1B2A5C), Color(0xFF3A2E6B)]),
                ),
                child: Column(children: [
                  const Icon(Icons.today, color: kGold, size: 42),
                  const Text('خمسة أسئلة، هي نفسها لكل القرّاء اليوم',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 4),
                  const Text('مرة واحدة في اليوم، 15 ثانية لكل سؤال',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  if (played)
                    Text('نتيجتك اليوم: ${mine?['r'] ?? 0} من 5 · ${mine?['s'] ?? 0} نقطة',
                        style: const TextStyle(fontFamily: 'Tajawal', color: kGold, fontSize: 18, fontWeight: FontWeight.bold))
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('ابدأ تحدّي اليوم'),
                      onPressed: _play,
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              const Text('ترتيب اليوم', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
              const Text('يتحدّث الترتيب كل بضع ساعات.', style: TextStyle(color: Colors.grey, fontSize: 12.5)),
              const SizedBox(height: 6),
              if (_board.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لم يظهر أحد في ترتيب اليوم بعد.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                )
              else
                for (var i = 0; i < _board.length; i++)
                  Card(
                    color: (_board[i]['no'] as num?)?.toInt() == myNo ? kGold.withValues(alpha: .14) : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: i < 3 ? kGold : Colors.grey.withValues(alpha: .25),
                        child: Text('${i + 1}', style: TextStyle(color: i < 3 ? Colors.white : null)),
                      ),
                      title: Text('${_board[i]['n']}'.trim().isEmpty ? 'رقم ${_board[i]['no']}' : '${_board[i]['n']}'),
                      subtitle: Text('صحيح ${_board[i]['r']} من 5'),
                      trailing: Text('${_board[i]['s']}',
                          style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
                    ),
                  ),
            ]),
    );
  }
}
