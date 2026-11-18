import 'dart:async';

import 'package:flutter/material.dart';

import '../services/challenge.dart';
import '../services/cloud.dart';
import '../services/quiz.dart';
import '../services/tour.dart';
import '../theme.dart';
import 'account_screens.dart';
import 'challenge_screens.dart' show ChallengePlay;

void _say(BuildContext context, String text, {bool ok = true}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFB3261E),
        duration: const Duration(seconds: 3),
        content: Text(text)));
}

String _two(int n) => n.toString().padLeft(2, '0');

String _left(Duration d) {
  if (d.isNegative) return '00:00';
  if (d.inDays > 0) return '${d.inDays} يوم و${d.inHours % 24} ساعة';
  if (d.inHours > 0) return '${d.inHours}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}';
  return '${_two(d.inMinutes)}:${_two(d.inSeconds % 60)}';
}

/// The start in the reader's own time.
String _localTime(DateTime utc) {
  final l = utc.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:${_two(l.minute)} ${l.hour < 12 ? 'صباحاً' : 'مساءً'}';
}

const _green = Color(0xFF2E7D32);

// ====================================================================== home card
/// On the home page: the next tournament with a countdown, and for the
/// developer and the sheikh a reminder when its questions are missing.
class TourHomeCard extends StatefulWidget {
  const TourHomeCard({super.key});

  @override
  State<TourHomeCard> createState() => _TourHomeCardState();
}

class _TourHomeCardState extends State<TourHomeCard> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    Tour.instance.load().then((_) => Tour.instance.checkReminder());
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && Tour.instance.showCard) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Tour.instance,
        builder: (context, _) {
          final t = Tour.instance;
          final staff = Cloud.instance.canManageStaff;
          final kids = <Widget>[];
          if (staff && t.on && t.needQuestions) {
            kids.add(Card(
              color: Colors.orange.withValues(alpha: .15),
              child: ListTile(
                leading: const Icon(Icons.edit_calendar, color: Colors.orange),
                title: const Text('أضف أسئلة بطولة الجمعة', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${Tour.arabicDate(Tour.keyOf(Tour.nextStart()))} — لم تُضف أسئلتها بعد'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => TourQuestionsScreen(dayKey: Tour.keyOf(Tour.nextStart())))),
              ),
            ));
          }
          if (t.prizeNote != null) {
            kids.add(Card(
              color: kGold.withValues(alpha: .18),
              child: ListTile(
                leading: const Icon(Icons.card_giftcard, color: kGold),
                title: Text(t.prizeNote!),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => t.prizeNote = null)),
              ),
            ));
          }
          if (t.showCard) {
            final start = Tour.nextStart();
            final key = Tour.keyOf(start);
            final now = DateTime.now().toUtc();
            final open = !now.isBefore(Tour.openOf(key));
            final started = !now.isBefore(start);
            kids.add(Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TourScreen(dayKey: key))),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF0B3D2E), Color(0xFF14532D)]),
                  ),
                  child: Row(children: [
                    const Icon(Icons.emoji_events, color: kGold, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('بطولة الجمعة',
                            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 19, color: Colors.white)),
                        Text(
                            started
                                ? 'البطولة جارية الآن'
                                : open
                                    ? 'الدخول مفتوح! تبدأ بعد ${_left(start.difference(now))}'
                                    : 'تبدأ بعد ${_left(start.difference(now))} · الساعة ${_localTime(start)}',
                            style: const TextStyle(color: Colors.white70)),
                      ]),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TourScreen(dayKey: key))),
                      child: Text(open && !started ? 'ادخل' : 'التفاصيل'),
                    ),
                  ]),
                ),
              ),
            ));
          }
          if (kids.isEmpty) return const SizedBox.shrink();
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Column(children: kids));
        },
      );
}

// ====================================================================== the room
class TourScreen extends StatefulWidget {
  final String dayKey;
  const TourScreen({super.key, required this.dayKey});

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  Timer? _t;
  bool _in = false, _busy = false, _playing = false, _played = false;
  StreamSubscription? _sub;
  List<TourPlayer> _players = [];
  List<TourPlayer>? _board; // the final board, once known
  bool _boardAsked = false;

  Tour get tour => Tour.instance;
  String get key => widget.dayKey;
  DateTime get start => Tour.startOf(key);
  DateTime get open => Tour.openOf(key);
  int get _count => tour.playQs.isEmpty ? 0 : tour.playQs.length;
  DateTime get deadline => start.add(Duration(seconds: _count * Tour.secs + 45));

  @override
  void initState() {
    super.initState();
    Challenges.instance.roomOpened();
    tour.joined(key).then((v) async {
      if (!mounted) return;
      final saved = await tour.savedBoard(key);
      setState(() {
        _in = v;
        _played = tour.myResult(key)?.finished == true;
        if (saved.isNotEmpty) _board = saved;
      });
      if (v) _follow();
    });
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _t?.cancel();
    _sub?.cancel();
    Challenges.instance.roomClosed();
    super.dispose();
  }

  void _follow() {
    if (!tour.joinedRt || _sub != null) return;
    _sub = tour.livePlayers(key).listen((l) {
      if (!mounted) return;
      setState(() => _players = l);
    }, onError: (_) {});
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now().toUtc();
    if (_in && !_played && !_playing && !now.isBefore(start) && now.isBefore(deadline) && !_cancelled) {
      _play();
    }
    // The board: when everyone in the live room finished, or the time is over.
    if (_in && _board == null && !_boardAsked && _played) {
      final allDone = tour.joinedRt && _players.length > 1 && _players.every((p) => p.finished);
      if (allDone || now.isAfter(deadline)) _makeBoard();
    }
    setState(() {});
  }

  /// Fewer than two in the live room when it starts (and nobody went to
  /// Firestore, which happens only when the live room is full): cancelled.
  bool get _cancelled =>
      _in && tour.joinedRt && !DateTime.now().toUtc().isBefore(start) && _players.isNotEmpty && _players.length < 2;

  Future<void> _makeBoard() async {
    _boardAsked = true;
    var l = tour.joinedRt ? _players : await tour.liveBoardOnce(key);
    final me = tour.myResult(key);
    if (me != null && !l.any((p) => p.uid == me.uid)) l = [...l, me];
    final r = Tour.rank(l.where((p) => p.finished || DateTime.now().toUtc().isAfter(deadline)));
    await tour.saveBoard(key, r);
    if (mounted) setState(() => _board = r);
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    final err = await tour.join(key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _in = err == null;
    });
    if (err != null) {
      _say(context, err, ok: false);
      return;
    }
    _follow();
  }

  Future<void> _play() async {
    _playing = true;
    final qs = [for (var i = 0; i < tour.playQs.length; i++) tour.playQs[i].asQuiz(i)];
    final c = Challenge('t$key', '', '', 'group', [for (final q in qs) q.id], Tour.secs, 'play', const [], null,
        open.millisecondsSinceEpoch, start.millisecondsSinceEpoch, '', '');
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChallengePlay(
              c: c,
              qs: qs,
              onDone: (right, wrong, score, ms) => tour.finish(key, right: right, wrong: wrong, score: score, ms: ms),
            )));
    _playing = false;
    if (mounted) setState(() => _played = true);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final signed = Cloud.instance.user != null;
    final List<Widget> body;
    if (_board != null) {
      body = _results();
    } else if (_cancelled) {
      body = [
        const SizedBox(height: 30),
        const Icon(Icons.event_busy, size: 64, color: Colors.orange),
        const Text('أُلغيت البطولة لقلّة المشاركين', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 20)),
        const Text('موعدنا الجمعة القادمة إن شاء الله.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ];
    } else if (_in && _played) {
      body = [
        const SizedBox(height: 40),
        const Icon(Icons.hourglass_top, size: 54, color: kGold),
        const Text('أنهيتَ أسئلتك، انتظر حتى ينتهي الآخرون', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 19)),
        if (tour.joinedRt)
          Text('أنهى ${_players.where((p) => p.finished).length} من ${_players.length}',
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        Text('تظهر النتيجة بعد ${_left(deadline.difference(now))} على الأكثر',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
      ];
    } else if (_in && !now.isBefore(start)) {
      body = [
        const SizedBox(height: 30),
        Center(child: FilledButton(onPressed: _play, child: const Text('أكمل الإجابة'))),
      ];
    } else {
      body = _waiting(now, signed);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('بطولة الجمعة'), actions: [
        IconButton(
          tooltip: 'سجلّ البطولات',
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TourRecordScreen())),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(14), children: body),
    );
  }

  List<Widget> _waiting(DateTime now, bool signed) {
    final isOpen = !now.isBefore(open);
    final started = !now.isBefore(start);
    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Icon(Icons.emoji_events, color: kGold, size: 52),
            Text(Tour.arabicDate(key), style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
            Text('الساعة 9 مساءً بتوقيت مكة · ${_localTime(start)} بتوقيتك', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            Text(started ? 'بدأت البطولة' : 'تبدأ بعد', style: const TextStyle(color: Colors.grey)),
            if (!started)
              Text(_left(start.difference(now)),
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 34, fontWeight: FontWeight.bold, color: kGold)),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (_in)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _green.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
          child: Column(children: [
            const Icon(Icons.check_circle, color: _green, size: 34),
            const Text('أنت في البطولة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 20, color: _green)),
            Text(
                tour.joinedRt
                    ? 'في الغرفة ${_players.length} مشاركاً · ${tour.playQs.length} سؤالاً، 15 ثانية لكل سؤال'
                    : '${tour.playQs.length} سؤالاً، 15 ثانية لكل سؤال',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const Text('ابقَ في هذه الصفحة، وتبدأ الأسئلة وحدها في الوقت.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12.5)),
          ]),
        )
      else if (started)
        const Text('بدأت البطولة، فلا يمكن الدخول الآن. موعدنا الجمعة القادمة إن شاء الله.',
            textAlign: TextAlign.center, style: TextStyle(height: 1.8))
      else if (!signed)
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.login),
          label: const Text('سجّل الدخول لتشارك'),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountScreen()));
            if (mounted) setState(() {});
          },
        )
      else
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.bolt),
          label: Text(isOpen ? 'ادخل البطولة' : 'يُفتح الدخول قبل البطولة بعشر دقائق'),
          onPressed: !isOpen || _busy ? null : _join,
        ),
      const SizedBox(height: 14),
      const Text('• تبدأ ولو دخل اثنان فقط، وإن لم يدخل أحد غيرك تُلغى.\n'
          '• الأوائل الثلاثة يأخذ كل واحد منهم تحدّيين هدية.\n'
          '• الفائز الأول يأخذ شارة «بطل الجمعة» في ملفه.',
          style: TextStyle(height: 1.9, color: Colors.grey)),
    ];
  }

  List<Widget> _results() {
    final r = _board!;
    final uid = Cloud.instance.user?.uid;
    final mineAt = r.indexWhere((p) => p.uid == uid);
    return [
      Card(
        color: _green,
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.emoji_events, color: kGold, size: 36),
          title: Text(r.isEmpty || r.first.score <= 0 ? 'انتهت البطولة' : 'بطل الجمعة: ${r.first.name}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          subtitle: Text(mineAt >= 0 ? 'ترتيبك: ${mineAt + 1} من ${r.length}' : 'انتهت البطولة',
              style: const TextStyle(color: Colors.white70)),
        ),
      ),
      if (!tour.joinedRt)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('الترتيب الرسمي لكل المشاركين يظهر في «سجلّ البطولات» بعد قليل.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12.5)),
        ),
      const SizedBox(height: 8),
      for (var i = 0; i < r.length && i < 100; i++)
        ListTile(
          tileColor: r[i].uid == uid ? kGold.withValues(alpha: .12) : null,
          leading: CircleAvatar(
            backgroundColor: i < 3 ? kGold : Colors.grey.withValues(alpha: .25),
            child: Text('${i + 1}', style: TextStyle(color: i < 3 ? Colors.white : null)),
          ),
          title: Text(r[i].uid == uid ? '${r[i].name} (أنت)' : r[i].name),
          subtitle: Text(r[i].finished
              ? 'صحيح ${r[i].right} من ${tour.playQs.isEmpty ? r[i].right + r[i].wrong : tour.playQs.length} · ${(r[i].ms / 1000).toStringAsFixed(1)} ث'
              : 'لم يُكمل'),
          trailing: Text('${r[i].score}', style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 20)),
        ),
    ];
  }
}

// ====================================================================== the record
class TourRecordScreen extends StatelessWidget {
  const TourRecordScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('سجلّ البطولات'),
            bottom: const TabBar(tabs: [Tab(text: 'كل جمعة'), Tab(text: 'أبطال السنة')]),
          ),
          body: FutureBuilder(
            future: Tour.instance.load(),
            builder: (context, _) {
              final t = Tour.instance;
              final year = DateTime.now().year;
              final champs = t.champions(year);
              final me = Cloud.instance.user == null ? 0 : askerNo(Cloud.instance.user!.uid);
              return TabBarView(children: [
                t.history.isEmpty
                    ? const Center(child: Text('لم تُقَم بطولة بعد.', style: TextStyle(color: Colors.grey)))
                    : ListView(padding: const EdgeInsets.all(10), children: [
                        for (final h in t.history) _Day(h: h),
                      ]),
                champs.isEmpty
                    ? Center(child: Text('لا أبطال في $year بعد.', style: const TextStyle(color: Colors.grey)))
                    : ListView(padding: const EdgeInsets.all(10), children: [
                        Text('أبطال الجمعة في $year', style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                        for (var i = 0; i < champs.length; i++)
                          ListTile(
                            tileColor: champs[i].$2 == me ? kGold.withValues(alpha: .12) : null,
                            leading: CircleAvatar(
                              backgroundColor: i == 0 ? kGold : Colors.grey.withValues(alpha: .25),
                              child: Text('${i + 1}', style: TextStyle(color: i == 0 ? Colors.white : null)),
                            ),
                            title: Text(champs[i].$1),
                            subtitle: Text('رقم ${champs[i].$2}'),
                            trailing: Text('🏆 ${champs[i].$3}',
                                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
                          ),
                      ]),
              ]);
            },
          ),
        ),
      );
}

class _Day extends StatelessWidget {
  final Map<String, dynamic> h;
  const _Day({required this.h});

  @override
  Widget build(BuildContext context) {
    final top = [for (final x in (h['top'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    final n = (h['n'] as num?)?.toInt() ?? 0;
    final q = (h['q'] as num?)?.toInt() ?? 0;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.emoji_events, color: kGold),
        title: Text(Tour.arabicDate('${h['d']}')),
        subtitle: Text(top.isEmpty || ((top.first['s'] as num?) ?? 0) <= 0
            ? (n < 2 ? 'أُلغيت لقلّة المشاركين' : 'بلا فائز')
            : 'البطل: ${top.first['n']} · صحيح ${top.first['r']} من $q · $n مشاركاً'),
        children: [
          for (var i = 0; i < top.length; i++)
            ListTile(
              dense: true,
              leading: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
              title: Text('${top[i]['n']}'),
              subtitle: Text('صحيح ${top[i]['r']} من $q'),
              trailing: Text('${top[i]['s']}'),
            ),
        ],
      ),
    );
  }
}

// ====================================================================== staff
/// The developer and the sheikh: show or hide the tournament, and the
/// questions of each coming Friday.
class TourAdminScreen extends StatefulWidget {
  const TourAdminScreen({super.key});

  @override
  State<TourAdminScreen> createState() => _TourAdminScreenState();
}

class _TourAdminScreenState extends State<TourAdminScreen> {
  late Future<Map<String, int>> _f = Tour.instance.counts();

  @override
  void initState() {
    super.initState();
    Tour.instance.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Tour.instance,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('أسئلة بطولة الجمعة')),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            SwitchListTile(
              title: const Text('إظهار بطولة الجمعة', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('إذا أُخفيت لا تظهر للقرّاء، وتبقى الأسئلة محفوظة.'),
              value: Tour.instance.on,
              onChanged: (v) async {
                final err = await Tour.instance.setOn(v);
                if (context.mounted && err != null) _say(context, err, ok: false);
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('كل جمعة الساعة 9 مساءً بتوقيت مكة. أضف أسئلتها متى شئت قبلها، وتبدأ وحدها. '
                  'أضفها قبل يوم الجمعة حتى تظهر بطاقتها للقرّاء.',
                  style: TextStyle(color: Colors.grey, height: 1.7)),
            ),
            const Divider(),
            FutureBuilder<Map<String, int>>(
              future: _f,
              builder: (context, snap) {
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                return Column(children: [
                  for (final d in Tour.coming(5))
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.event,
                            color: (snap.data![Tour.keyOf(d)] ?? 0) > 0 ? _green : Colors.orange),
                        title: Text(Tour.arabicDate(Tour.keyOf(d))),
                        subtitle: Text((snap.data![Tour.keyOf(d)] ?? 0) > 0
                            ? '${snap.data![Tour.keyOf(d)]} سؤالاً جاهزة'
                            : 'لم تُضف أسئلتها بعد'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () async {
                          await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => TourQuestionsScreen(dayKey: Tour.keyOf(d))));
                          setState(() => _f = Tour.instance.counts());
                        },
                      ),
                    ),
                ]);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('سجلّ البطولات وأبطال السنة'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TourRecordScreen())),
            ),
          ]),
        ),
      );
}

class TourQuestionsScreen extends StatefulWidget {
  final String dayKey;
  const TourQuestionsScreen({super.key, required this.dayKey});

  @override
  State<TourQuestionsScreen> createState() => _TourQuestionsScreenState();
}

class _TourQuestionsScreenState extends State<TourQuestionsScreen> {
  List<TourQ> _qs = [];
  bool _loading = true, _busy = false, _dirty = false;

  @override
  void initState() {
    super.initState();
    Tour.instance.questions(widget.dayKey).then((l) {
      if (mounted) {
        setState(() {
          _qs = l;
          _loading = false;
        });
      }
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final err = await Tour.instance.save(widget.dayKey, _qs);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (err == null) _dirty = false;
    });
    _say(context, err ?? 'حُفظت ${_qs.length} أسئلة لهذه الجمعة', ok: err == null);
  }

  Future<void> _edit([int? i]) async {
    final q = i == null ? TourQ('', ['', '', '', ''], 0) : TourQ(_qs[i].text, [..._qs[i].choices], _qs[i].correct, _qs[i].explain);
    while (q.choices.length < 4) {
      q.choices.add('');
    }
    final text = TextEditingController(text: q.text);
    final ex = TextEditingController(text: q.explain);
    final cs = [for (final c in q.choices) TextEditingController(text: c)];
    var right = q.correct;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(i == null ? 'سؤال جديد' : 'تعديل السؤال'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: text, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'السؤال')),
              const SizedBox(height: 6),
              const Text('اضغط الدائرة أمام الجواب الصحيح. اترك الاختيار فارغاً إن لم تحتجه.',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              for (var k = 0; k < cs.length; k++)
                Row(children: [
                  Radio<int>(value: k, groupValue: right, onChanged: (v) => set(() => right = v ?? right)),
                  Expanded(child: TextField(controller: cs[k], decoration: InputDecoration(hintText: 'اختيار ${k + 1}'))),
                ]),
              TextField(controller: ex, maxLines: 3, decoration: const InputDecoration(labelText: 'الشرح (اختياري)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تم')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    // Keep the filled choices only, and the right one with them.
    final choices = <String>[];
    var correct = 0;
    for (var k = 0; k < cs.length; k++) {
      final c = cs[k].text.trim();
      if (c.isEmpty) continue;
      if (k == right) correct = choices.length;
      choices.add(c);
    }
    if (text.text.trim().isEmpty || choices.length < 2 || cs[right].text.trim().isEmpty) {
      if (mounted) _say(context, 'اكتب السؤال واختيارين على الأقل، واختر الجواب الصحيح.', ok: false);
      return;
    }
    final nq = TourQ(text.text.trim(), choices, correct, ex.text.trim());
    setState(() {
      if (i == null) {
        _qs.add(nq);
      } else {
        _qs[i] = nq;
      }
      _dirty = true;
    });
  }

  Future<void> _paste() async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('لصق أسئلة كثيرة'),
        content: SizedBox(
          width: 500,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('كل سؤال: «س:» ثم الاختيارات، الصحيح يبدأ بنجمة * والبقية بشرطة -، وبين كل سؤالين سطر فارغ.',
                style: TextStyle(color: Colors.grey, height: 1.6, fontSize: 12.5)),
            const SizedBox(height: 6),
            TextField(controller: t, minLines: 8, maxLines: 16, decoration: const InputDecoration(border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('أضف')),
        ],
      ),
    );
    if (ok != true) return;
    final parsed = Quiz.parseBulk(t.text, '', 1)
        .where((q) => q.text.trim().isNotEmpty && q.choices.length >= 2 && q.type == QuizType.choice && !q.multi)
        .map((q) => TourQ(q.text.trim(), [for (final c in q.choices) c.trim()], q.correct, q.explain.trim()))
        .toList();
    if (!mounted) return;
    if (parsed.isEmpty) {
      _say(context, 'لم أفهم أي سؤال، راجع الشكل.', ok: false);
      return;
    }
    setState(() {
      _qs.addAll(parsed);
      _dirty = true;
    });
    _say(context, 'أُضيفت ${parsed.length} أسئلة، اضغط «حفظ».');
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final leave = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('لم تحفظ التعديلات'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('خروج بلا حفظ')),
                FilledButton(onPressed: () => Navigator.pop(d, false), child: const Text('رجوع')),
              ],
            ),
          );
          if (leave == true && context.mounted) {
            setState(() => _dirty = false);
            Navigator.pop(context);
          }
        },
        child: Scaffold(
          appBar: AppBar(title: Text(Tour.arabicDate(widget.dayKey)), actions: [
            IconButton(tooltip: 'لصق أسئلة كثيرة', icon: const Icon(Icons.content_paste), onPressed: _paste),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('سؤال'),
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(10, 10, 10, 90), children: [
                  Card(
                    color: kGold.withValues(alpha: .12),
                    child: ListTile(
                      title: Text('${_qs.length} سؤالاً لهذه الجمعة'),
                      subtitle: const Text('مخفية عن الجميع حتى يُفتح الدخول إلى البطولة.'),
                      trailing: FilledButton(onPressed: _busy || !_dirty ? null : _save, child: const Text('حفظ')),
                    ),
                  ),
                  for (var i = 0; i < _qs.length; i++)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(_qs[i].text, maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text('✔ ${_qs[i].choices[_qs[i].correct.clamp(0, _qs[i].choices.length - 1)]}',
                            style: const TextStyle(color: _green)),
                        onTap: () => _edit(i),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() {
                            _qs.removeAt(i);
                            _dirty = true;
                          }),
                        ),
                      ),
                    ),
                ]),
        ),
      );
}
