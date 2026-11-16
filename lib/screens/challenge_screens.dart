import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/challenge.dart';
import '../services/cloud.dart';
import '../services/quiz.dart';
import '../theme.dart';
import '../widgets/common.dart';

void _say(BuildContext context, String text, {bool ok = true}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFB3261E),
        duration: const Duration(seconds: 3),
        content: Text(text)));
}

Future<void> openChallenges(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChallengeHome()));

// ====================================================================== home
class ChallengeHome extends StatefulWidget {
  const ChallengeHome({super.key});

  @override
  State<ChallengeHome> createState() => _ChallengeHomeState();
}

class _ChallengeHomeState extends State<ChallengeHome> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Quiz.instance.load();
    Challenges.instance.load();
  }

  Future<void> _create(String mode) async {
    final quiz = Quiz.instance;
    var cat = '', level = 0, count = 5, secs = 30;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(mode == 'duel' ? 'تحدٍّ فردي (أنت وصديق)' : 'تحدٍّ جماعي (أنت وأصحابك)',
                  style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              const Text('الأسئلة من:', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ChoiceChip(label: const Text('كل الأبواب (عشوائي)'), selected: cat.isEmpty, onSelected: (_) => set(() => cat = '')),
                for (final k in quiz.visibleCats.where((k) => !k.hidden))
                  ChoiceChip(label: Text(k.name), selected: cat == k.id, onSelected: (_) => set(() => cat = k.id)),
              ]),
              const SizedBox(height: 10),
              const Text('الصعوبة:', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, children: [
                for (final l in const [0, 1, 2, 3])
                  ChoiceChip(
                      label: Text(l == 0 ? 'مخلوط' : Quiz.levelNames[l]!),
                      selected: level == l,
                      onSelected: (_) => set(() => level = l)),
              ]),
              const SizedBox(height: 10),
              const Text('عدد الأسئلة:', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, children: [
                for (final n in const [5, 10, 15, 20])
                  ChoiceChip(label: Text('$n'), selected: count == n, onSelected: (_) => set(() => count = n)),
              ]),
              const SizedBox(height: 10),
              const Text('الوقت لكل سؤال:', style: TextStyle(fontWeight: FontWeight.bold)),
              Wrap(spacing: 6, children: [
                for (final s in const [15, 30, 60, 0])
                  ChoiceChip(
                      label: Text(s == 0 ? 'بلا وقت' : '$s ثانية'),
                      selected: secs == s,
                      onSelected: (_) => set(() => secs = s)),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                icon: const Icon(Icons.bolt),
                label: const Text('أنشئ التحدّي'),
                onPressed: () => Navigator.pop(c, true),
              ),
            ]),
          ),
        ),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _busy = true);
    final (code, err) = await Challenges.instance.create(mode: mode, cat: cat, level: level, count: count, secs: secs);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _say(context, err, ok: false);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeRoom(code: code!)));
    if (mounted) setState(() {});
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.length < 5) {
      _say(context, 'اكتب رمز التحدّي (5 أرقام)', ok: false);
      return;
    }
    setState(() => _busy = true);
    final err = await Challenges.instance.join(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _say(context, err, ok: false);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeRoom(code: code)));
  }

  Future<void> _askMore() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('اطلب تحدّيات أكثر'),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'رسالة قصيرة للشيخ (اختياري)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await Challenges.instance.requestMore(note.text);
    if (mounted) _say(context, err ?? 'وصل طلبك إلى الشيخ، جزاك الله خيراً', ok: err == null);
  }

  @override
  Widget build(BuildContext context) {
    final ch = Challenges.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([ch, Cloud.instance]),
      builder: (context, _) {
        final staff = Cloud.instance.isAdmin;
        final signed = Cloud.instance.user != null;
        return Scaffold(
          appBar: AppBar(
            title: const Text('التحدّيات'),
            actions: [
              if (staff)
                PopupMenuButton<String>(
                  onSelected: (v) => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => v == 'req'
                          ? const CreditRequestsScreen()
                          : v == 'set'
                              ? const ChallengeSettingsScreen()
                              : const ChallengeStatsScreen())),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'req', child: Text('طلبات التحدّيات الإضافية')),
                    PopupMenuItem(value: 'set', child: Text('إعدادات التحدّيات')),
                    PopupMenuItem(value: 'stats', child: Text('إحصاءات التحدّيات')),
                  ],
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [Color(0xFF7A1F1F), Color(0xFFB0602A)]),
                border: Border.all(color: kGold),
              ),
              child: Column(children: [
                const Icon(Icons.bolt, color: kGold, size: 44),
                const Text('تحدَّ أصحابك في الأسئلة',
                    style: TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontSize: 21, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('نفس الأسئلة للجميع، والنتيجة تظهر مباشرة',
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Row(children: [
                  for (final s in [
                    ('${ch.left}', 'متبقٍّ اليوم'),
                    ('${ch.wins}', 'فوز'),
                    ('${ch.played}', 'تحدٍّ'),
                  ])
                    Expanded(
                      child: Column(children: [
                        Text(s.$1,
                            style: const TextStyle(
                                fontFamily: 'Tajawal', color: kGold, fontSize: 22, fontWeight: FontWeight.bold)),
                        Text(s.$2, style: const TextStyle(color: Colors.white, fontSize: 12)),
                      ]),
                    ),
                ]),
                if (ch.wins > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('منها ${ch.winsDuel} فردية و${ch.winsGroup} جماعية',
                        style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            if (!signed)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('سجّل الدخول من «المزيد» لتبدأ التحدّيات، فهي تحتاج حساباً.',
                      textAlign: TextAlign.center, style: TextStyle(height: 1.7)),
                ),
              ),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: const Color(0xFF7A1F1F)),
                  icon: const Icon(Icons.person),
                  label: const Text('تحدٍّ فردي'),
                  onPressed: _busy || !signed ? null : () => _create('duel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: const Color(0xFFB0602A)),
                  icon: const Icon(Icons.groups),
                  label: const Text('تحدٍّ جماعي'),
                  onPressed: _busy || !signed ? null : () => _create('group'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 5,
                  decoration: const InputDecoration(
                      counterText: '', hintText: 'رمز التحدّي من صديقك', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(onPressed: _busy || !signed ? null : _join, child: const Text('ادخل')),
            ]),
            if (signed && ch.left == 0)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.mail_outline),
                  label: Text('انتهت تحدّياتك اليوم (${ch.perDay} في اليوم) — اطلب من الشيخ المزيد'),
                  onPressed: _askMore,
                ),
              ),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.emoji_events_outlined, color: kGold),
              title: const Text('لوحة الشرف للتحدّيات'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChallengeBoardScreen())),
            ),
            const Divider(),
            const Text('تحدّياتي', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
            FutureBuilder<List<Challenge>>(
              future: ch.mine(),
              builder: (context, snap) {
                final l = snap.data ?? const [];
                if (l.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('لم تدخل تحدّياً بعد.', style: TextStyle(color: Colors.grey)),
                  );
                }
                final me = Cloud.instance.user?.uid;
                return Column(children: [
                  for (final c in l)
                    ListTile(
                      leading: Icon(c.mode == 'duel' ? Icons.person : Icons.groups),
                      title: Text('رمز ${c.code} — ${c.players.length} مشاركين'),
                      subtitle: Text(c.over
                          ? (c.ranked.first.uid == me ? 'انتهى — فزت 🏆' : 'انتهى — الفائز: ${c.ranked.first.name}')
                          : 'جارٍ'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => ChallengeRoom(code: c.code))),
                    ),
                ]);
              },
            ),
          ]),
        );
      },
    );
  }
}

// ====================================================================== room
class ChallengeRoom extends StatefulWidget {
  final String code;
  const ChallengeRoom({super.key, required this.code});

  @override
  State<ChallengeRoom> createState() => _ChallengeRoomState();
}

class _ChallengeRoomState extends State<ChallengeRoom> {
  bool _counted = false;

  @override
  Widget build(BuildContext context) => StreamBuilder<Challenge?>(
        stream: Challenges.instance.watch(widget.code),
        builder: (context, snap) {
          final c = snap.data;
          if (c == null) {
            return Scaffold(
              appBar: AppBar(title: Text('تحدٍّ ${widget.code}')),
              body: Center(
                  child: snap.connectionState == ConnectionState.waiting
                      ? const CircularProgressIndicator()
                      : const Text('لا يوجد هذا التحدّي.')),
            );
          }
          final uid = Cloud.instance.user?.uid;
          final me = c.players.where((p) => p.uid == uid).firstOrNull;
          if (c.over && !_counted) {
            _counted = true;
            Challenges.instance.countResult(c);
          }
          final ranked = c.ranked;
          return Scaffold(
            appBar: AppBar(title: Text(c.mode == 'duel' ? 'تحدٍّ فردي' : 'تحدٍّ جماعي')),
            body: ListView(padding: const EdgeInsets.all(14), children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    const Text('رمز التحدّي', style: TextStyle(color: Colors.grey)),
                    SelectableText(c.code,
                        style: const TextStyle(fontFamily: 'Tajawal', fontSize: 38, fontWeight: FontWeight.bold, letterSpacing: 6)),
                    Text('${c.qids.length} أسئلة · ${c.secs == 0 ? 'بلا وقت' : '${c.secs} ثانية لكل سؤال'} · ${c.players.length}/${c.max}',
                        style: const TextStyle(color: Colors.grey)),
                    if (!c.over) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy),
                            label: const Text('نسخ الرمز'),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: c.code));
                              _say(context, 'تم النسخ');
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.share),
                            label: const Text('ادعُ صديقاً'),
                            onPressed: () => Share.share(
                                '${c.hostName} يتحدّاك في أسئلة تطبيق «ابن الشابرة» ⚡\n'
                                'افتح التطبيق ← الأسئلة ← التحدّيات، واكتب الرمز: ${c.code}\n'
                                'https://ibnalshabira.com'),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              if (me != null && !me.finished && !c.over)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(me.done == 0 ? 'ابدأ الإجابة' : 'أكمل (${me.done} من ${c.qids.length})'),
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengePlay(c: c, start: me.done))),
                ),
              if (c.over)
                Card(
                  color: const Color(0xFF2E7D32),
                  child: ListTile(
                    leading: const Icon(Icons.emoji_events, color: kGold, size: 36),
                    title: Text(
                        ranked.length > 1 && ranked[0].score == ranked[1].score ? 'تعادل!' : 'الفائز: ${ranked.first.name}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: const Text('انتهى التحدّي', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              const SizedBox(height: 8),
              const Text('الترتيب مباشرة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
              for (var i = 0; i < ranked.length; i++)
                ListTile(
                  tileColor: ranked[i].uid == uid ? kGold.withValues(alpha: .12) : null,
                  leading: CircleAvatar(
                    backgroundColor: i == 0 ? kGold : Colors.grey.withValues(alpha: .25),
                    child: Text('${i + 1}', style: TextStyle(color: i == 0 ? Colors.white : null)),
                  ),
                  title: Text(ranked[i].uid == uid ? '${ranked[i].name} (أنت)' : ranked[i].name),
                  subtitle: Text(ranked[i].finished ? 'أنهى' : 'أجاب ${ranked[i].done} من ${c.qids.length}'),
                  trailing: Text('${ranked[i].score}',
                      style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 20)),
                ),
              if (c.players.length < 2 && !c.over)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('أرسل الرمز لصديقك ليدخل. تستطيع أن تبدأ الآن، ويجيب هو متى دخل خلال يوم.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.7)),
                ),
              if (c.host == uid && !c.over && c.players.length >= 2)
                TextButton(
                  onPressed: () => Challenges.instance.close(c),
                  child: const Text('إنهاء التحدّي الآن'),
                ),
            ]),
          );
        },
      );
}

// ====================================================================== play
class ChallengePlay extends StatefulWidget {
  final Challenge c;
  final int start;
  const ChallengePlay({super.key, required this.c, this.start = 0});

  @override
  State<ChallengePlay> createState() => _ChallengePlayState();
}

class _ChallengePlayState extends State<ChallengePlay> {
  late int _i = widget.start;
  int? _picked;
  Timer? _t;
  int _left = 0;
  bool _sending = false;
  Challenge get c => widget.c;

  QuizQ? get _q => _i < c.qids.length ? Quiz.instance.all.where((q) => q.id == c.qids[_i]).firstOrNull : null;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _t?.cancel();
    _left = c.secs;
    if (c.secs == 0) return;
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        _pick(-1);
      }
    });
  }

  Future<void> _pick(int i) async {
    final q = _q;
    if (q == null || _picked != null || _sending) return;
    _t?.cancel();
    final ok = i >= 0 && q.rightSet.contains(i) && !q.multi;
    setState(() {
      _picked = i;
      _sending = true;
    });
    HapticFeedback.mediumImpact();
    await Challenges.instance.answer(c, _i, ok, _left);
    // The first time a reader meets a question counts in his record too.
    if (!Quiz.instance.marks.containsKey(q.id)) await Quiz.instance.answer(q, ok: ok, choice: i);
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    if (!mounted) return;
    if (_i + 1 >= c.qids.length) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _i++;
      _picked = null;
      _sending = false;
    });
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    return Scaffold(
      appBar: AppBar(
        title: Text('سؤال ${_i + 1} من ${c.qids.length}'),
        actions: [
          if (c.secs > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text('$_left ث',
                    style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _left <= 5 ? Colors.red : null)),
              ),
            ),
        ],
      ),
      body: q == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('هذا السؤال لم يعد متاحاً.'),
                TextButton(onPressed: () => _pick(-1), child: const Text('التالي')),
              ]),
            )
          : ListView(padding: const EdgeInsets.all(14), children: [
              LinearProgressIndicator(value: (_i + 1) / c.qids.length, color: kGold),
              const SizedBox(height: 14),
              Text(q.text,
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold, height: 1.7)),
              if (q.quote.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(q.quote,
                      textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Amiri', fontSize: 18, height: 1.9)),
                ),
              const SizedBox(height: 14),
              for (var i = 0; i < (q.type == QuizType.trueFalse ? 2 : q.choices.length); i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: _picked == null
                        ? Theme.of(context).colorScheme.surface
                        : q.rightSet.contains(i)
                            ? const Color(0xFF2E7D32).withValues(alpha: .15)
                            : i == _picked
                                ? const Color(0xFFC62828).withValues(alpha: .15)
                                : Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                          color: _picked != null && q.rightSet.contains(i)
                              ? const Color(0xFF2E7D32)
                              : Colors.grey.withValues(alpha: .4)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _picked == null ? () => _pick(i) : null,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(q.type == QuizType.trueFalse ? (i == 0 ? 'صح' : 'خطأ') : q.choices[i],
                            style: const TextStyle(fontSize: 16, height: 1.6)),
                      ),
                    ),
                  ),
                ),
            ]),
    );
  }
}

// ====================================================================== boards & staff
class ChallengeBoardScreen extends StatelessWidget {
  const ChallengeBoardScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('لوحة الشرف للتحدّيات'),
            bottom: const TabBar(tabs: [Tab(text: 'هذا الأسبوع'), Tab(text: 'هذا الشهر'), Tab(text: 'كل الأوقات')]),
          ),
          body: TabBarView(children: [for (final p in const ['week', 'month', 'all']) _WinBoard(p)]),
        ),
      );
}

class _WinBoard extends StatelessWidget {
  final String period;
  const _WinBoard(this.period);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LeaderWin>>(
        future: Challenges.instance.board(period),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final l = snap.data ?? const [];
          if (l.isEmpty) return const EmptyState(icon: Icons.emoji_events_outlined, text: 'لا فائزين بعد.');
          return ListView.separated(
            itemCount: l.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) => ListTile(
              tileColor: l[i].me ? kGold.withValues(alpha: .12) : null,
              leading: CircleAvatar(
                backgroundColor: i < 3 ? [kGold, const Color(0xFFB0B0B0), const Color(0xFFB87333)][i] : null,
                child: Text('${i + 1}'),
              ),
              title: Text(l[i].name),
              trailing: Text('${l[i].wins} فوز', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          );
        },
      );
}

class CreditRequestsScreen extends StatelessWidget {
  const CreditRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('طلبات التحدّيات الإضافية')),
        body: StreamBuilder(
          stream: Challenges.instance.requests(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (docs.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, text: 'لا طلبات الآن.');
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = docs[i];
                final m = d.data();
                return ListTile(
                  title: Text('${m['name'] ?? ''}'),
                  subtitle: Text('${m['note'] ?? ''}'.isEmpty ? 'يطلب تحدّيات إضافية' : '${m['note']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final n in const [3, 10])
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: FilledButton.tonal(
                          onPressed: () async {
                            final err = await Challenges.instance.grant('${m['uid']}', n, requestId: d.id);
                            if (context.mounted) _say(context, err ?? 'أُرسلت $n تحدّيات', ok: err == null);
                          },
                          child: Text('+$n'),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => Challenges.instance.reject(d.id),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      );
}

class ChallengeSettingsScreen extends StatefulWidget {
  const ChallengeSettingsScreen({super.key});

  @override
  State<ChallengeSettingsScreen> createState() => _ChallengeSettingsScreenState();
}

class _ChallengeSettingsScreenState extends State<ChallengeSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final ch = Challenges.instance;
    return ListenableBuilder(
      listenable: ch,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('إعدادات التحدّيات')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('عدد التحدّيات المجانية لكل شخص في اليوم', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            IconButton.filledTonal(
                onPressed: ch.perDay <= 0 ? null : () => ch.setSettings(perDay: ch.perDay - 1), icon: const Icon(Icons.remove)),
            Expanded(
              child: Text('${ch.perDay}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 30, fontWeight: FontWeight.bold)),
            ),
            IconButton.filledTonal(onPressed: () => ch.setSettings(perDay: ch.perDay + 1), icon: const Icon(Icons.add)),
          ]),
          const Text('يتغيّر عند الجميع فوراً. ولتخبر الناس، انشر إعلاناً في الرئيسية بزر «التحدّيات».',
              style: TextStyle(color: Colors.grey, height: 1.7)),
          const Divider(height: 30),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('نقاط القراءة'),
            subtitle: const Text('كل 10 أجوبة يقرؤها في اليوم تعطيه تحدّياً إضافياً (حتى 3 في اليوم)'),
            value: ch.readPoints,
            onChanged: (v) => ch.setSettings(readPoints: v),
          ),
        ]),
      ),
    );
  }
}

class ChallengeStatsScreen extends StatefulWidget {
  const ChallengeStatsScreen({super.key});

  @override
  State<ChallengeStatsScreen> createState() => _ChallengeStatsScreenState();
}

class _ChallengeStatsScreenState extends State<ChallengeStatsScreen> {
  late Future<List<Map<String, dynamic>>> _f = Challenges.instance.staffStats();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('إحصاءات التحدّيات'),
          actions: [
            IconButton(
              tooltip: 'تحديث الآن',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _f = Challenges.instance.staffStats(force: true)),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            final l = snap.data ?? const [];
            if (l.isEmpty) return const EmptyState(icon: Icons.bar_chart, text: 'لا تحدّيات بعد.');
            final total = l.fold<int>(0, (s, r) => s + (r['played'] as int));
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('${l.length} مشاركاً · $total تحدّياً\nتُحدَّث مرة في اليوم حتى لا يكون ضغط على الخادم.',
                    style: const TextStyle(height: 1.7)),
              ),
              for (final r in l)
                ListTile(
                  title: Text('${r['name']}'),
                  subtitle: Text('تحدّيات: ${r['played']} · فوز: ${r['wins']} · رصيد إضافي: ${r['credits']} · أجوبة صحيحة: ${r['right']}'),
                  trailing: IconButton(
                    tooltip: 'أرسل له تحدّيات',
                    icon: const Icon(Icons.card_giftcard, color: kGold),
                    onPressed: () async {
                      final err = await Challenges.instance.grant('${r['uid']}', 3);
                      if (context.mounted) _say(context, err ?? 'أُرسلت 3 تحدّيات', ok: err == null);
                    },
                  ),
                ),
            ]);
          },
        ),
      );
}
