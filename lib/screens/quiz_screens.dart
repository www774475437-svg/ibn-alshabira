import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/cloud.dart';
import '../services/quiz.dart';
import '../theme.dart';
import '../widgets/common.dart';

void _toast(BuildContext context, String text, {bool ok = true}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFB3261E),
        content: Text(text)));
}

Future<void> openQuiz(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizHomeScreen()));

Future<void> openQuestion(BuildContext context, QuizQ q, {List<QuizQ> next = const [], bool preview = false}) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => QuestionScreen(q: q, queue: next, preview: preview)));

/// Shares a widget (inside a RepaintBoundary) as a picture.
Future<void> shareBoundary(BuildContext context, GlobalKey key, String text) async {
  try {
    final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Share.shareXFiles(
        [XFile.fromData(data!.buffer.asUint8List(), mimeType: 'image/png', name: 'ibn-alshabira-quiz.png')],
        text: text,
        fileNameOverrides: ['ibn-alshabira-quiz.png']);
  } catch (_) {
    await Share.share(text);
  }
}

Color _c(int v) => Color(v);

// ====================================================================== home
class QuizHomeScreen extends StatefulWidget {
  const QuizHomeScreen({super.key});

  @override
  State<QuizHomeScreen> createState() => _QuizHomeScreenState();
}

class _QuizHomeScreenState extends State<QuizHomeScreen> {
  int _level = 0;

  @override
  void initState() {
    super.initState();
    final quiz = Quiz.instance;
    // Staff opening it first time: make the starting buttons real ones.
    quiz.load(force: quiz.loaded && quiz.isStaff && quiz.cats.any((c) => c.id.length <= 3));
  }

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([quiz, Cloud.instance]),
      builder: (context, _) {
        final staff = quiz.isStaff;
        return Scaffold(
          appBar: AppBar(
            title: const Text('الأسئلة'),
            actions: [
              IconButton(
                tooltip: 'بحث في الأسئلة',
                icon: const Icon(Icons.search),
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizSearchScreen())),
              ),
              PopupMenuButton<String>(
                onSelected: (v) => _menu(context, v),
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(value: 'timer', checked: quiz.timer, child: const Text('عدّاد الوقت (30 ثانية)')),
                  CheckedPopupMenuItem(value: 'kids', checked: quiz.kidsMode, child: const Text('وضع الأطفال')),
                  const PopupMenuItem(value: 'suggest', child: Text('اقترح سؤالاً')),
                  if (staff) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'cats', child: Text('إدارة التصنيفات')),
                    const PopupMenuItem(value: 'sugs', child: Text('الأسئلة المقترحة')),
                    const PopupMenuItem(value: 'stats', child: Text('إحصاءات الأسئلة')),
                    const PopupMenuItem(value: 'thanks', child: Text('رسالة شكر للأوائل')),
                  ],
                ],
              ),
            ],
          ),
          floatingActionButton: staff
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('سؤال جديد'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => QuestionEditor(
                          q: QuizQ(id: '', cat: quiz.cats.isEmpty ? '' : quiz.cats.first.id)))),
                )
              : null,
          body: !quiz.loaded
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => quiz.load(force: true),
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      _ScoreHeader(quiz: quiz),
                      if (quiz.thanks.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                          child: Card(
                            color: kGold.withValues(alpha: .16),
                            margin: EdgeInsets.zero,
                            child: ListTile(
                              leading: const Icon(Icons.favorite, color: kGold),
                              title: const Text('من الشيخ', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(quiz.thanks, style: const TextStyle(height: 1.7)),
                            ),
                          ),
                        ),
                      if (quiz.ofTheDay != null) QuizOfDayCard(q: quiz.ofTheDay!, compact: true),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
                        child: Wrap(spacing: 8, children: [
                          for (final l in const [0, 1, 2, 3])
                            ChoiceChip(
                              label: Text(l == 0 ? 'كل المستويات' : Quiz.levelNames[l]!),
                              selected: _level == l,
                              onSelected: (_) => setState(() => _level = l),
                            ),
                        ]),
                      ),
                      if (quiz.kidsMode)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Text('وضع الأطفال: تظهر الأسئلة التي اختارها الشيخ للصغار فقط.',
                              style: TextStyle(color: Colors.grey, fontSize: 12.5)),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(builder: (context, box) {
                          final cols = box.maxWidth > 700 ? 4 : 2;
                          final w = (box.maxWidth - (cols - 1) * 10) / cols;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final c in quiz.visibleCats)
                                SizedBox(width: w, child: _CatButton(cat: c, level: _level)),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, String v) async {
    final quiz = Quiz.instance;
    switch (v) {
      case 'timer':
        await quiz.setTimer(!quiz.timer);
      case 'kids':
        await quiz.setKids(!quiz.kidsMode);
      case 'suggest':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SuggestQuestionScreen()));
      case 'cats':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizCatsManager()));
      case 'sugs':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizSuggestionsScreen()));
      case 'stats':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizStatsScreen()));
      case 'thanks':
        final ctrl = TextEditingController(text: quiz.thanks);
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('رسالة شكر للأوائل'),
            content: TextField(
              controller: ctrl,
              maxLines: 5,
              decoration: const InputDecoration(
                  hintText: 'مثلاً: بارك الله في الإخوة فلان وفلان على تصدّرهم هذا الأسبوع…',
                  border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
            ],
          ),
        );
        if (ok == true) {
          final err = await quiz.setThanks(ctrl.text);
          if (context.mounted) _toast(context, err ?? 'تم الحفظ', ok: err == null);
        }
    }
  }
}

class _ScoreHeader extends StatelessWidget {
  final Quiz quiz;
  const _ScoreHeader({required this.quiz});

  Widget _stat(String n, String label, Color c) => Expanded(
        child: Column(children: [
          Text(n, style: TextStyle(fontFamily: 'Tajawal', fontSize: 22, fontWeight: FontWeight.bold, color: c)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final brand = brandColor(context);
    Widget btn(IconData i, String t, Widget page) => Expanded(
          child: TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 6)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
            child: Column(children: [
              Icon(i, color: kGold),
              const SizedBox(height: 2),
              Text(t, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(colors: [brand, Color.lerp(brand, Colors.black, .35)!]),
        border: Border.all(color: kGold.withValues(alpha: .7)),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.quiz_outlined, color: kGold, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(quiz.levelTitle,
                  style: const TextStyle(
                      fontFamily: 'Tajawal', color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
              Text(quiz.streak > 1 ? '🔥 ${quiz.streak} أيام متتالية' : 'أجب كل يوم لتبدأ سلسلتك',
                  style: const TextStyle(color: kGold, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _stat('${quiz.right}', 'صحيح', const Color(0xFF7BE495)),
          _stat('${quiz.wrong}', 'خطأ', const Color(0xFFFF8A80)),
          _stat('${quiz.score}', 'النقاط', kGold),
        ]),
        const Divider(color: Colors.white24, height: 18),
        Row(children: [
          btn(Icons.person_outline, 'ملفي', const QuizProfileScreen()),
          btn(Icons.leaderboard_outlined, 'المتصدرون', const LeaderboardScreen()),
          btn(Icons.replay_outlined, 'أخطائي', const QuizListScreen(kind: 'wrong')),
          btn(Icons.bookmark_border, 'المحفوظة', const QuizListScreen(kind: 'saved')),
        ]),
      ]),
    );
  }
}

class _CatButton extends StatelessWidget {
  final QuizCat cat;
  final int level;
  const _CatButton({required this.cat, required this.level});

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    final total = quiz.liveIn(cat.id);
    final done = quiz.answeredIn(cat.id);
    final color = _c(cat.color);
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => QuizCategoryScreen(cat: cat, level: level))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(chapterIcon(cat.icon), color: kGold, size: 26),
                const Spacer(),
                if (cat.hidden)
                  const Icon(Icons.visibility_off_outlined, color: Colors.white70, size: 18)
                else if (quiz.hasNewIn(cat.id))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE53935), borderRadius: BorderRadius.circular(10)),
                    child: const Text('جديد', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
              ]),
              const SizedBox(height: 10),
              Text(cat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Tajawal', color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text(total == 0 ? 'لا أسئلة بعد' : '$total سؤالاً',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  color: kGold,
                ),
              ),
              const SizedBox(height: 4),
              Text('أجبت عن $done من $total', style: const TextStyle(color: Colors.white, fontSize: 11.5)),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================== category
class QuizCategoryScreen extends StatefulWidget {
  final QuizCat cat;
  final int level;
  const QuizCategoryScreen({super.key, required this.cat, this.level = 0});

  @override
  State<QuizCategoryScreen> createState() => _QuizCategoryScreenState();
}

class _QuizCategoryScreenState extends State<QuizCategoryScreen> {
  late int _level = widget.level;
  bool _arrange = false;

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    return ListenableBuilder(
      listenable: quiz,
      builder: (context, _) {
        final list = quiz.inCat(widget.cat.id, level: _level);
        final next = quiz.nextIn(widget.cat.id, level: _level);
        final total = list.where((q) => q.isLive).length;
        final done = list.where((q) => q.isLive && quiz.marks.containsKey(q.id)).length;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.cat.name),
            actions: [
              if (quiz.isStaff)
                IconButton(
                  tooltip: 'ترتيب الأسئلة',
                  icon: Icon(_arrange ? Icons.check : Icons.swap_vert),
                  onPressed: () => setState(() => _arrange = !_arrange),
                ),
            ],
          ),
          body: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Wrap(spacing: 8, children: [
                for (final l in const [0, 1, 2, 3])
                  ChoiceChip(
                    label: Text(l == 0 ? 'الكل' : Quiz.levelNames[l]!),
                    selected: _level == l,
                    onSelected: (_) => setState(() => _level = l),
                  ),
              ]),
            ),
            if (total > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: next == null
                    ? Card(
                        margin: EdgeInsets.zero,
                        color: const Color(0xFF2E7D32),
                        child: ListTile(
                          leading: const Icon(Icons.workspace_premium, color: kGold, size: 32),
                          title: Text('أتممت أسئلة «${widget.cat.name}»',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'أصبت ${list.where((q) => quiz.marks[q.id]?.ok == true).length} من $total',
                              style: const TextStyle(color: Colors.white70)),
                          trailing: TextButton(
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => QuizCertificateScreen(cat: widget.cat))),
                            child: const Text('الشهادة', style: TextStyle(color: kGold)),
                          ),
                        ),
                      )
                    : FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(done == 0 ? 'ابدأ الأسئلة' : 'أكمل ($done من $total)'),
                        onPressed: () {
                          final rest = [
                            for (final q in list)
                              if (q.isLive && !quiz.marks.containsKey(q.id) && q.id != next.id) q
                          ]..sort((a, b) => a.level != b.level ? a.level.compareTo(b.level) : a.order.compareTo(b.order));
                          openQuestion(context, next, next: rest);
                        },
                      ),
              ),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(
                      icon: Icons.quiz_outlined,
                      text: quiz.isStaff ? 'لا أسئلة هنا بعد. أضف سؤالاً من الزر في الصفحة السابقة.' : 'لا أسئلة هنا بعد، قريباً إن شاء الله.')
                  : _arrange
                      ? ReorderableListView.builder(
                          itemCount: list.length,
                          onReorder: (a, b) {
                            if (b > a) b--;
                            final l = [...list];
                            l.insert(b, l.removeAt(a));
                            quiz.reorderQs(l);
                          },
                          itemBuilder: (context, i) => ListTile(
                            key: ValueKey(list[i].id),
                            leading: const Icon(Icons.drag_handle),
                            title: Text(list[i].text, maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 30),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) => _QTile(q: list[i]),
                        ),
            ),
          ]),
        );
      },
    );
  }
}

class _QTile extends StatelessWidget {
  final QuizQ q;
  const _QTile({required this.q});

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    final m = quiz.marks[q.id];
    final tags = <String>[
      Quiz.levelNames[q.level] ?? '',
      if (q.draft) 'مسودة',
      if (q.hidden) 'مخفي',
      if (q.releaseAt != null && q.releaseAt!.isAfter(DateTime.now())) 'مجدول',
      if (q.kids) 'للأطفال',
    ];
    return ListTile(
      leading: Icon(
        m == null ? Icons.radio_button_unchecked : (m.ok ? Icons.check_circle : Icons.cancel),
        color: m == null ? Colors.grey : (m.ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828)),
      ),
      title: Text(q.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
      subtitle: Text(tags.join(' · '), style: const TextStyle(fontSize: 12)),
      trailing: quiz.isStaff
          ? IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuestionEditor(q: q))),
            )
          : null,
      onTap: () => openQuestion(context, q, preview: quiz.isStaff && !q.isLive),
    );
  }
}

// ====================================================================== question
class QuestionScreen extends StatefulWidget {
  final QuizQ q;
  final List<QuizQ> queue;
  final bool preview;
  const QuestionScreen({super.key, required this.q, this.queue = const [], this.preview = false});

  @override
  State<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends State<QuestionScreen> {
  int? _picked;
  late List<int> _orderNow; // indices into choices, as the reader arranged them
  bool _showHint = false;
  Timer? _t;
  int _left = 30;
  final _cardKey = GlobalKey();
  bool _previewDone = false;

  QuizQ get q => widget.q;
  QuizMark? get _mark => Quiz.instance.marks[q.id];
  bool get _done => widget.preview ? _previewDone : _mark != null;

  @override
  void initState() {
    super.initState();
    _orderNow = List.generate(q.choices.length, (i) => i)..shuffle(math.Random(q.id.hashCode));
    if (_orderNow.length > 1 && _isRightOrder()) _orderNow = _orderNow.reversed.toList();
    if (Quiz.instance.timer && !_done && !widget.preview) {
      _t = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => _left--);
        if (_left <= 0) {
          t.cancel();
          _submit(-1, timeout: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  bool _isRightOrder() {
    for (var i = 0; i < _orderNow.length; i++) {
      if (_orderNow[i] != i) return false;
    }
    return true;
  }

  List<String> get _options => q.type == QuizType.trueFalse ? const ['صح', 'خطأ'] : q.choices;

  Future<void> _submit(int choice, {bool timeout = false}) async {
    if (_done) return;
    _t?.cancel();
    final ok = !timeout && (q.type == QuizType.order ? _isRightOrder() : choice == q.correct);
    HapticFeedback.mediumImpact();
    if (widget.preview) {
      setState(() {
        _picked = choice;
        _previewDone = true;
      });
      return;
    }
    setState(() => _picked = choice);
    await Quiz.instance.answer(q, ok: ok, choice: choice);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    final mark = _mark;
    final ok = widget.preview ? (q.type == QuizType.order ? _isRightOrder() : _picked == q.correct) : mark?.ok == true;
    final chosen = widget.preview ? _picked : mark?.choice;
    final pct = quiz.percentRight(q.id);
    final cat = quiz.cats.where((c) => c.id == q.cat).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.preview ? 'معاينة السؤال' : (cat?.name ?? 'سؤال')),
        actions: [
          if (!widget.preview)
            IconButton(
              tooltip: 'حفظ السؤال',
              icon: Icon(quiz.saved.contains(q.id) ? Icons.bookmark : Icons.bookmark_border),
              onPressed: () => quiz.toggleSaved(q.id).then((_) => setState(() {})),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'report') await _report(context);
              if (v == 'edit' && context.mounted) {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuestionEditor(q: q)));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'report', child: Text('الإبلاغ عن خطأ في السؤال')),
              if (quiz.isStaff) const PopupMenuItem(value: 'edit', child: Text('تعديل السؤال')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
        children: [
          if (widget.preview)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('معاينة: لا تُحسب هذه الإجابة، وهكذا يظهر السؤال للناس.',
                  style: TextStyle(color: Colors.orange, fontSize: 12.5)),
            ),
          Row(children: [
            Chip(label: Text(Quiz.levelNames[q.level] ?? ''), visualDensity: VisualDensity.compact),
            const Spacer(),
            if (_t != null && _t!.isActive)
              Chip(
                avatar: const Icon(Icons.timer_outlined, size: 18),
                label: Text('$_left ث'),
                backgroundColor: _left <= 10 ? Colors.red.withValues(alpha: .15) : null,
              ),
          ]),
          const SizedBox(height: 6),
          Text(q.text,
              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold, height: 1.7)),
          if (q.quote.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kGold.withValues(alpha: .5)),
              ),
              child: Text(q.quote,
                  textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Amiri', fontSize: 19, height: 1.9)),
            ),
          if (q.image.startsWith('http'))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(q.image, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          if (q.showHint && q.hint.isNotEmpty && !_done)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                icon: const Icon(Icons.lightbulb_outline, color: kGold),
                label: Text(_showHint ? q.hint : 'تلميح'),
                onPressed: () => setState(() => _showHint = true),
              ),
            ),
          const SizedBox(height: 12),
          if (q.type == QuizType.order) ..._orderUi(mark) else ..._choiceUi(chosen),
          if (_done) ...[
            const SizedBox(height: 16),
            RepaintBoundary(
              key: _cardKey,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828), width: 2),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(ok ? Icons.check_circle : Icons.cancel,
                        color: ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828), size: 30),
                    const SizedBox(width: 8),
                    Text(ok ? 'أحسنت، جوابك صحيح' : (chosen == -1 && q.type != QuizType.order ? 'انتهى الوقت' : 'جوابك خطأ'),
                        style: TextStyle(
                            fontFamily: 'Tajawal',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828))),
                  ]),
                  if (pct != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('أجاب عنه صحيحاً $pct٪ من الناس', style: const TextStyle(color: Colors.grey)),
                    ),
                  if (q.explain.isNotEmpty) ...[
                    const Divider(height: 22),
                    const Text('الشرح', style: TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
                    const SizedBox(height: 4),
                    SelectableText(q.explain, style: const TextStyle(fontSize: 16, height: 1.9)),
                  ],
                  if (q.suggestedBy.isNotEmpty && q.showSuggester)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('اقترحه: ${q.suggestedBy}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  const SizedBox(height: 6),
                  Row(children: [
                    Image.asset(logoAssets[appLogo.value], width: 22, height: 22),
                    const SizedBox(width: 6),
                    const Text('الأسئلة — تطبيق ابن الشابرة', style: TextStyle(color: Colors.grey, fontSize: 11.5)),
                  ]),
                ]),
              ),
            ),
            if (q.linkUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.link),
                  label: Text(q.linkTitle.isEmpty ? 'للاستزادة' : q.linkTitle),
                  onPressed: () => openUrl(context, q.linkUrl),
                ),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('شارك النتيجة'),
                  onPressed: () => shareBoundary(context, _cardKey,
                      '${q.text}\n\n${ok ? 'أجبت صحيحاً ✅' : 'أخطأت ❌'} في قسم الأسئلة من تطبيق «ابن الشابرة»\nhttps://ibnalshabira.com'),
                ),
              ),
              if (widget.queue.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('التالي'),
                    onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => QuestionScreen(q: widget.queue.first, queue: widget.queue.sublist(1)))),
                  ),
                ),
              ],
            ]),
          ],
        ],
      ),
    );
  }

  List<Widget> _choiceUi(int? chosen) {
    final opts = _options;
    return [
      for (var i = 0; i < opts.length; i++)
        if (opts[i].trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ChoiceTile(
              text: opts[i],
              letter: q.type == QuizType.trueFalse ? null : 'أبجدهوزحطي'[i % 10],
              state: !_done
                  ? 0
                  : i == q.correct
                      ? 1
                      : i == chosen
                          ? 2
                          : 0,
              onTap: _done ? null : () => _confirm(i, opts[i]),
            ),
          ),
    ];
  }

  Future<void> _confirm(int i, String text) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تأكيد الجواب'),
        content: Text('اخترت: «$text»\n\nلا يمكن تغيير الجواب بعد التأكيد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (sure == true) await _submit(i);
  }

  List<Widget> _orderUi(QuizMark? mark) {
    if (_done) {
      return [
        const Text('الترتيب الصحيح:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        for (var i = 0; i < q.choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _ChoiceTile(text: q.choices[i], letter: '${i + 1}', state: 1),
          ),
      ];
    }
    return [
      const Text('رتّب العناصر بالسحب، ثم اضغط «تأكيد الترتيب»:', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 6),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (a, b) => setState(() {
          if (b > a) b--;
          _orderNow.insert(b, _orderNow.removeAt(a));
        }),
        children: [
          for (var i = 0; i < _orderNow.length; i++)
            Card(
              key: ValueKey(_orderNow[i]),
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                title: Text(q.choices[_orderNow[i]]),
                trailing: const Icon(Icons.drag_handle),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: () async {
          final sure = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('تأكيد الترتيب'),
              content: const Text('لا يمكن تغيير الجواب بعد التأكيد.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('رجوع')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
              ],
            ),
          );
          if (sure == true) await _submit(-1);
        },
        child: const Text('تأكيد الترتيب'),
      ),
    ];
  }

  Future<void> _report(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('الإبلاغ عن خطأ'),
        content: TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: const InputDecoration(hintText: 'ما الخطأ الذي رأيته؟', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final sent = await Quiz.instance.report(q, ctrl.text);
      if (context.mounted) _toast(context, sent ? 'وصل البلاغ، جزاك الله خيراً' : 'تعذّر الإرسال', ok: sent);
    }
  }
}

class _ChoiceTile extends StatelessWidget {
  final String text;
  final String? letter;
  final int state; // 0 normal, 1 right, 2 wrong pick
  final VoidCallback? onTap;
  const _ChoiceTile({required this.text, this.letter, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = state == 1
        ? const Color(0xFF2E7D32)
        : state == 2
            ? const Color(0xFFC62828)
            : Theme.of(context).colorScheme.outline.withValues(alpha: .5);
    return Material(
      color: state == 0 ? Theme.of(context).colorScheme.surface : color.withValues(alpha: .10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: color, width: state == 0 ? 1 : 2)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            if (letter != null)
              CircleAvatar(
                radius: 15,
                backgroundColor: state == 0 ? kGold.withValues(alpha: .2) : color,
                child: Text(letter!,
                    style: TextStyle(color: state == 0 ? kGoldChip : Colors.white, fontWeight: FontWeight.bold)),
              ),
            if (letter != null) const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 16, height: 1.6))),
            if (state == 1) const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
            if (state == 2) const Icon(Icons.cancel, color: Color(0xFFC62828)),
          ]),
        ),
      ),
    );
  }
}

// ====================================================================== home card
/// «سؤال اليوم» for the home page (and atop «الأسئلة»).
class QuizOfDayCard extends StatelessWidget {
  final QuizQ q;
  final bool compact;
  const QuizOfDayCard({super.key, required this.q, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final m = Quiz.instance.marks[q.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18), side: BorderSide(color: kGold.withValues(alpha: .6))),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openQuestion(context, q),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.help_outline, color: kGold),
                const SizedBox(width: 6),
                const Text('سؤال اليوم',
                    style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16, color: kGoldChip)),
                const Spacer(),
                if (m != null)
                  Icon(m.ok ? Icons.check_circle : Icons.cancel,
                      color: m.ok ? const Color(0xFF2E7D32) : const Color(0xFFC62828), size: 20),
              ]),
              const SizedBox(height: 6),
              Text(q.text,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, height: 1.6, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(m == null ? 'اضغط لتجيب ←' : 'اضغط لترى الشرح ←',
                  style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// For the home page: «سؤال اليوم» and a small button to «الأسئلة».
class QuizHomeStrip extends StatefulWidget {
  const QuizHomeStrip({super.key});

  @override
  State<QuizHomeStrip> createState() => _QuizHomeStripState();
}

class _QuizHomeStripState extends State<QuizHomeStrip> {
  @override
  void initState() {
    super.initState();
    Quiz.instance.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Quiz.instance,
        builder: (context, _) {
          final q = Quiz.instance.ofTheDay;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (q != null) QuizOfDayCard(q: q),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    icon: const Icon(Icons.quiz_outlined),
                    label: const Text('الأسئلة'),
                    onPressed: () => openQuiz(context),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46), side: const BorderSide(color: kGold)),
                    icon: const Icon(Icons.leaderboard_outlined, color: kGold),
                    label: const Text('المتصدرون'),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen())),
                  ),
                ),
              ]),
            ),
          ]);
        },
      );
}

// ====================================================================== lists
class QuizListScreen extends StatelessWidget {
  final String kind; // wrong | saved
  const QuizListScreen({super.key, required this.kind});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Quiz.instance,
        builder: (context, _) {
          final list = kind == 'wrong' ? Quiz.instance.wrongOnes : Quiz.instance.savedOnes;
          return Scaffold(
            appBar: AppBar(title: Text(kind == 'wrong' ? 'مراجعة أخطائي' : 'الأسئلة المحفوظة')),
            body: list.isEmpty
                ? EmptyState(
                    icon: kind == 'wrong' ? Icons.task_alt : Icons.bookmark_border,
                    text: kind == 'wrong' ? 'لا أخطاء عندك، بارك الله فيك.' : 'لم تحفظ أسئلة بعد.')
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _QTile(q: list[i]),
                  ),
          );
        },
      );
}

class QuizSearchScreen extends StatefulWidget {
  const QuizSearchScreen({super.key});

  @override
  State<QuizSearchScreen> createState() => _QuizSearchScreenState();
}

class _QuizSearchScreenState extends State<QuizSearchScreen> {
  String _t = '';

  @override
  Widget build(BuildContext context) {
    final res = Quiz.instance.search(_t);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'ابحث في الأسئلة وشروحها', border: InputBorder.none),
          onChanged: (v) => setState(() => _t = v),
        ),
      ),
      body: _t.trim().isEmpty
          ? const EmptyState(icon: Icons.search, text: 'اكتب كلمة للبحث.')
          : res.isEmpty
              ? const EmptyState(icon: Icons.search_off, text: 'لا نتائج.')
              : ListView.separated(
                  itemCount: res.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _QTile(q: res[i]),
                ),
    );
  }
}

// ====================================================================== profile & boards
class QuizProfileScreen extends StatefulWidget {
  const QuizProfileScreen({super.key});

  @override
  State<QuizProfileScreen> createState() => _QuizProfileScreenState();
}

class _QuizProfileScreenState extends State<QuizProfileScreen> {
  final _key = GlobalKey();
  int? _rank;

  @override
  void initState() {
    super.initState();
    if (Cloud.instance.user != null) {
      Quiz.instance.leaders('all').then((l) {
        final i = l.indexWhere((r) => r.me);
        if (mounted && i >= 0) setState(() => _rank = i + 1);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    return ListenableBuilder(
      listenable: quiz,
      builder: (context, _) {
        final total = quiz.right + quiz.wrong;
        return Scaffold(
          appBar: AppBar(title: const Text('ملفي في الأسئلة')),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            RepaintBoundary(
              key: _key,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: LinearGradient(
                      colors: [brandColor(context), Color.lerp(brandColor(context), Colors.black, .4)!]),
                  border: Border.all(color: kGold),
                ),
                child: Column(children: [
                  Image.asset(logoAssets[appLogo.value], width: 56, height: 56),
                  const SizedBox(height: 8),
                  Text(quiz.nick.isEmpty ? 'طالب علم' : quiz.nick,
                      style: const TextStyle(
                          fontFamily: 'Tajawal', color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(quiz.levelTitle, style: const TextStyle(color: kGold, fontSize: 15)),
                  const SizedBox(height: 12),
                  Row(children: [
                    for (final s in [
                      ('${quiz.right}', 'صحيح'),
                      ('${quiz.wrong}', 'خطأ'),
                      (total == 0 ? '—' : '${(quiz.right * 100 / total).round()}٪', 'الدقة'),
                      (_rank == null ? '—' : '#$_rank', 'الترتيب'),
                    ])
                      Expanded(
                        child: Column(children: [
                          Text(s.$1,
                              style: const TextStyle(
                                  fontFamily: 'Tajawal', color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(s.$2, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  const Text('الأسئلة — تطبيق ابن الشابرة', style: TextStyle(color: Colors.white54, fontSize: 11)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined),
              label: const Text('شارك نتيجتي صورةً'),
              onPressed: () => shareBoundary(context, _key,
                  'نتيجتي في قسم الأسئلة من تطبيق «ابن الشابرة»: ${quiz.right} جواباً صحيحاً\nhttps://ibnalshabira.com'),
            ),
            const SizedBox(height: 16),
            const Text('الشارات', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 6),
            if (quiz.badges.isEmpty)
              const Text('أجب عن الأسئلة لتنال الشارات.', style: TextStyle(color: Colors.grey))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final b in quiz.badges) Chip(avatar: Icon(b.$2, color: kGold, size: 18), label: Text(b.$1)),
              ]),
            const Divider(height: 30),
            _NickEditor(),
          ]),
        );
      },
    );
  }
}

class _NickEditor extends StatefulWidget {
  @override
  State<_NickEditor> createState() => _NickEditorState();
}

class _NickEditorState extends State<_NickEditor> {
  late final _ctrl = TextEditingController(text: Quiz.instance.nick);

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    final signed = Cloud.instance.user != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('اسمك في المتصدرين', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            maxLength: 30,
            decoration: const InputDecoration(
                hintText: 'اسم مستعار، مثل: أبو عبد الله', border: OutlineInputBorder(), isDense: true, counterText: ''),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
          onPressed: () async {
            await quiz.setProfile(nick: _ctrl.text);
            if (context.mounted) _toast(context, 'تم الحفظ');
          },
          child: const Text('حفظ'),
        ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('أظهر اسمي في المتصدرين'),
        subtitle: const Text('إن أطفأته يظهر «مشارك» بدل اسمك'),
        value: quiz.showName,
        onChanged: (v) => quiz.setProfile(showName: v),
      ),
      if (!signed)
        const Text('سجّل الدخول ليظهر اسمك في المتصدرين وتُحفظ إجاباتك في حسابك. وإجاباتك محفوظة على جوالك في كل حال.',
            style: TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.6)),
    ]);
  }
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المتصدرون'),
            bottom: const TabBar(tabs: [Tab(text: 'هذا الأسبوع'), Tab(text: 'هذا الشهر'), Tab(text: 'كل الأوقات')]),
          ),
          body: const TabBarView(children: [_Board('week'), _Board('month'), _Board('all')]),
        ),
      );
}

class _Board extends StatelessWidget {
  final String period;
  const _Board(this.period);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LeaderRow>>(
        future: Quiz.instance.leaders(period),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final l = snap.data ?? const [];
          if (snap.hasError || l.isEmpty) {
            return const EmptyState(icon: Icons.leaderboard_outlined, text: 'لا متصدرين بعد. كن أولهم!');
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: l.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final medal = i < 3 ? [const Color(0xFFD4AF37), const Color(0xFFB0B0B0), const Color(0xFFB87333)][i] : null;
              return ListTile(
                tileColor: l[i].me ? kGold.withValues(alpha: .12) : null,
                leading: CircleAvatar(
                  backgroundColor: medal ?? Colors.grey.withValues(alpha: .2),
                  child: Text('${i + 1}', style: TextStyle(color: medal != null ? Colors.white : null)),
                ),
                title: Text(l[i].me ? '${l[i].name} (أنت)' : l[i].name),
                trailing: Text('${l[i].score}',
                    style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
              );
            },
          );
        },
      );
}

class QuizCertificateScreen extends StatelessWidget {
  final QuizCat cat;
  const QuizCertificateScreen({super.key, required this.cat});

  @override
  Widget build(BuildContext context) {
    final key = GlobalKey();
    final quiz = Quiz.instance;
    final list = quiz.live.where((q) => q.cat == cat.id).toList();
    final right = list.where((q) => quiz.marks[q.id]?.ok == true).length;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('شهادة إتمام')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        RepaintBoundary(
          key: key,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kGold, width: 4),
            ),
            child: Column(children: [
              Image.asset(logoAssets[appLogo.value], width: 70, height: 70),
              const SizedBox(height: 10),
              const Text('شهادة إتمام',
                  style: TextStyle(fontFamily: 'Amiri', fontSize: 30, fontWeight: FontWeight.bold, color: kGoldChip)),
              const SizedBox(height: 10),
              Text(quiz.nick.isEmpty ? 'طالب العلم' : quiz.nick,
                  style: const TextStyle(fontFamily: 'Tajawal', fontSize: 22, fontWeight: FontWeight.bold, color: kInk)),
              const SizedBox(height: 8),
              Text('أتمّ أسئلة باب «${cat.name}»\nوأصاب $right من ${list.length}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, height: 1.8, color: kInk)),
              const SizedBox(height: 12),
              Text('${now.year}/${now.month}/${now.day}', style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 4),
              const Text('قسم الأسئلة — تطبيق ابن الشابرة', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.share_outlined),
          label: const Text('شارك الشهادة'),
          onPressed: () => shareBoundary(context, key, 'أتممت أسئلة باب «${cat.name}» في تطبيق «ابن الشابرة»'),
        ),
      ]),
    );
  }
}

// ====================================================================== suggest
class SuggestQuestionScreen extends StatefulWidget {
  const SuggestQuestionScreen({super.key});

  @override
  State<SuggestQuestionScreen> createState() => _SuggestQuestionScreenState();
}

class _SuggestQuestionScreenState extends State<SuggestQuestionScreen> {
  final _text = TextEditingController();
  final _explain = TextEditingController();
  final _choices = [TextEditingController(), TextEditingController(), TextEditingController()];
  int _correct = 0;
  String _cat = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final cats = Quiz.instance.visibleCats;
    if (_cat.isEmpty && cats.isNotEmpty) _cat = cats.first.id;
    return Scaffold(
      appBar: AppBar(title: const Text('اقترح سؤالاً')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('يصل اقتراحك إلى الشيخ، فإن قبله نُشر. تستطيع اقتراح 3 أسئلة في اليوم.',
            style: TextStyle(color: Colors.grey, height: 1.6)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _cat.isEmpty ? null : _cat,
          decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
          items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
          onChanged: (v) => setState(() => _cat = v ?? _cat),
        ),
        const SizedBox(height: 10),
        TextField(
            controller: _text,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'السؤال', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        for (var i = 0; i < _choices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Radio<int>(value: i, groupValue: _correct, onChanged: (v) => setState(() => _correct = v ?? 0)),
              Expanded(
                child: TextField(
                  controller: _choices[i],
                  decoration: InputDecoration(
                      labelText: 'الخيار ${i + 1}${i == _correct ? ' (الصحيح)' : ''}',
                      border: const OutlineInputBorder(),
                      isDense: true),
                ),
              ),
            ]),
          ),
        TextField(
            controller: _explain,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'الشرح أو الدليل (اختياري)', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  final choices = [for (final c in _choices) c.text.trim()];
                  if (_text.text.trim().isEmpty || choices.where((c) => c.isNotEmpty).length < 2) {
                    _toast(context, 'اكتب السؤال وخيارين على الأقل', ok: false);
                    return;
                  }
                  setState(() => _busy = true);
                  final err = await Quiz.instance.suggest(_cat, _text.text, choices, _correct, _explain.text);
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  _toast(context, err ?? 'وصل اقتراحك، جزاك الله خيراً', ok: err == null);
                  if (err == null) Navigator.pop(context);
                },
          child: const Text('إرسال الاقتراح'),
        ),
      ]),
    );
  }
}

// ====================================================================== staff
class QuestionEditor extends StatefulWidget {
  final QuizQ q;
  const QuestionEditor({super.key, required this.q});

  @override
  State<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<QuestionEditor> {
  late final QuizQ _q = widget.q.id.isEmpty ? widget.q : widget.q.copy();
  late final _text = TextEditingController(text: _q.text);
  late final _quote = TextEditingController(text: _q.quote);
  late final _image = TextEditingController(text: _q.image);
  late final _explain = TextEditingController(text: _q.explain);
  late final _hint = TextEditingController(text: _q.hint);
  late final _linkTitle = TextEditingController(text: _q.linkTitle);
  late final _linkUrl = TextEditingController(text: _q.linkUrl);
  late final List<TextEditingController> _choices = [
    for (final c in (_q.choices.isEmpty ? ['', ''] : _q.choices)) TextEditingController(text: c)
  ];
  bool _busy = false;
  bool _dirty = false;

  QuizQ _collect() => _q
    ..text = _text.text.trim()
    ..quote = _quote.text.trim()
    ..image = _image.text.trim()
    ..explain = _explain.text.trim()
    ..hint = _hint.text.trim()
    ..linkTitle = _linkTitle.text.trim()
    ..linkUrl = _linkUrl.text.trim()
    ..choices = _q.type == QuizType.trueFalse ? ['صح', 'خطأ'] : [for (final c in _choices) c.text.trim()];

  Future<void> _save({bool asDraft = false}) async {
    final q = _collect();
    if (asDraft) q.draft = true;
    if (q.text.isEmpty || (q.type != QuizType.trueFalse && q.choices.where((c) => c.isNotEmpty).length < 2)) {
      _toast(context, 'اكتب السؤال وخيارين على الأقل', ok: false);
      return;
    }
    if (q.cat.isEmpty) {
      _toast(context, 'اختر التصنيف', ok: false);
      return;
    }
    q.choices = q.type == QuizType.trueFalse ? q.choices : [for (final c in q.choices) if (c.isNotEmpty) c];
    if (q.correct >= q.choices.length) q.correct = 0;
    setState(() => _busy = true);
    final err = await Quiz.instance.saveQ(q);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(context, err ?? (q.draft ? 'حُفظ مسودةً' : 'تم الحفظ والنشر'), ok: err == null);
    if (err == null) {
      _dirty = false;
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    final cats = quiz.cats;
    final isNew = widget.q.id.isEmpty;
    InputDecoration dec(String l, [String? h]) =>
        InputDecoration(labelText: l, hintText: h, border: const OutlineInputBorder(), isDense: true);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (did, _) async {
        if (did) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('لم تحفظ التغييرات'),
            content: const Text('هل تخرج دون حفظ؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('البقاء')),
              TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('خروج')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? 'سؤال جديد' : 'تعديل السؤال'),
          actions: [
            IconButton(
              tooltip: 'معاينة',
              icon: const Icon(Icons.visibility_outlined),
              onPressed: () => openQuestion(context, _collect().copy(), preview: true),
            ),
            if (!isNew)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'copy') {
                    final to = await showDialog<String>(
                      context: context,
                      builder: (c) => SimpleDialog(title: const Text('انسخ إلى تصنيف'), children: [
                        for (final cat in cats)
                          if (cat.id != _q.cat)
                            SimpleDialogOption(onPressed: () => Navigator.pop(c, cat.id), child: Text(cat.name)),
                      ]),
                    );
                    if (to != null) {
                      final err = await quiz.copyTo(_collect(), to);
                      if (context.mounted) _toast(context, err ?? 'نُسخ السؤال', ok: err == null);
                    }
                  }
                  if (v == 'delete' && context.mounted) {
                    final sure = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('حذف السؤال؟'),
                        content: const Text('يُحذف السؤال نهائياً. إن أردت إخفاءه فقط فاستعمل «إخفاء».'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (sure == true) {
                      final err = await quiz.deleteQ(widget.q);
                      if (context.mounted) {
                        _toast(context, err ?? 'حُذف', ok: err == null);
                        if (err == null) Navigator.pop(context);
                      }
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'copy', child: Text('نسخ إلى تصنيف آخر')),
                  PopupMenuItem(value: 'delete', child: Text('حذف السؤال')),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            DropdownButtonFormField<String>(
              value: cats.any((c) => c.id == _q.cat) ? _q.cat : null,
              decoration: dec('التصنيف'),
              items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() {
                _q.cat = v ?? _q.cat;
                _dirty = true;
              }),
            ),
            const SizedBox(height: 10),
            SegmentedButton<QuizType>(
              segments: const [
                ButtonSegment(value: QuizType.choice, label: Text('اختيار')),
                ButtonSegment(value: QuizType.trueFalse, label: Text('صح/خطأ')),
                ButtonSegment(value: QuizType.order, label: Text('ترتيب')),
              ],
              selected: {_q.type},
              onSelectionChanged: (s) => setState(() {
                _q.type = s.first;
                _q.correct = 0;
                _dirty = true;
              }),
            ),
            const SizedBox(height: 10),
            TextField(
                controller: _text, maxLines: 3, onChanged: (_) => _dirty = true, decoration: dec('نص السؤال')),
            const SizedBox(height: 10),
            TextField(
                controller: _quote,
                maxLines: 3,
                onChanged: (_) => _dirty = true,
                decoration: dec('آية أو حديث داخل السؤال (اختياري)')),
            const SizedBox(height: 10),
            TextField(
                controller: _image, onChanged: (_) => _dirty = true, decoration: dec('رابط صورة (اختياري)', 'https://…')),
            const SizedBox(height: 14),
            if (_q.type == QuizType.trueFalse)
              Row(children: [
                const Text('الجواب الصحيح:  '),
                ChoiceChip(label: const Text('صح'), selected: _q.correct == 0, onSelected: (_) => setState(() => _q.correct = 0)),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('خطأ'), selected: _q.correct == 1, onSelected: (_) => setState(() => _q.correct = 1)),
              ])
            else ...[
              Text(_q.type == QuizType.order ? 'العناصر بترتيبها الصحيح (تظهر للناس مخلوطة):' : 'الخيارات (اضغط الدائرة على الصحيح):',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (var i = 0; i < _choices.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    if (_q.type == QuizType.choice)
                      Radio<int>(value: i, groupValue: _q.correct, onChanged: (v) => setState(() => _q.correct = v ?? 0))
                    else
                      SizedBox(width: 40, child: Center(child: Text('${i + 1}'))),
                    Expanded(
                      child: TextField(
                        controller: _choices[i],
                        onChanged: (_) => _dirty = true,
                        decoration: dec(_q.type == QuizType.choice && i == _q.correct ? 'الخيار ${i + 1} (الصحيح)' : 'الخيار ${i + 1}'),
                      ),
                    ),
                    if (_choices.length > 2)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => setState(() {
                          _choices.removeAt(i);
                          if (_q.correct >= _choices.length) _q.correct = 0;
                        }),
                      ),
                  ]),
                ),
              if (_choices.length < 8)
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة خيار'),
                  onPressed: () => setState(() => _choices.add(TextEditingController())),
                ),
            ],
            const SizedBox(height: 10),
            TextField(
                controller: _explain,
                maxLines: 6,
                onChanged: (_) => _dirty = true,
                decoration: dec('الشرح بالتفصيل (يظهر بعد الجواب، صحيحاً أو خطأً)')),
            const SizedBox(height: 10),
            TextField(controller: _hint, onChanged: (_) => _dirty = true, decoration: dec('تلميح (اختياري)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إظهار التلميح للناس'),
              value: _q.showHint,
              onChanged: (v) => setState(() => _q.showHint = v),
            ),
            const Text('رابط تحت الشرح: جواب، أو درس، أو كتاب، أو أي رابط', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(controller: _linkTitle, onChanged: (_) => _dirty = true, decoration: dec('عنوان الرابط', 'مثلاً: اسمع الدرس')),
            const SizedBox(height: 8),
            TextField(controller: _linkUrl, onChanged: (_) => _dirty = true, decoration: dec('الرابط', 'https://…')),
            const SizedBox(height: 12),
            Row(children: [
              const Text('المستوى:  '),
              for (final l in const [1, 2, 3])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(Quiz.levelNames[l]!),
                    selected: _q.level == l,
                    onSelected: (_) => setState(() => _q.level = l),
                  ),
                ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('يصلح للأطفال'),
              value: _q.kids,
              onChanged: (v) => setState(() => _q.kids = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إخفاء السؤال'),
              value: _q.hidden,
              onChanged: (v) => setState(() => _q.hidden = v),
            ),
            if (_q.suggestedBy.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('إظهار «اقترحه ${_q.suggestedBy}»'),
                value: _q.showSuggester,
                onChanged: (v) => setState(() => _q.showSuggester = v),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(_q.releaseAt == null
                  ? 'ينزل فوراً'
                  : 'ينزل يوم ${_q.releaseAt!.year}/${_q.releaseAt!.month}/${_q.releaseAt!.day}'),
              subtitle: const Text('اضغط لجدولة نزوله في يوم تختاره'),
              trailing: _q.releaseAt == null
                  ? null
                  : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _q.releaseAt = null)),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 400)),
                  initialDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (d != null) setState(() => _q.releaseAt = DateTime(d.year, d.month, d.day, 5));
              },
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _save(asDraft: true),
                  child: const Text('حفظ مسودة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32), minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy
                      ? null
                      : () {
                          _q.draft = false;
                          _save();
                        },
                  child: Text(_q.releaseAt != null ? 'حفظ وجدولة' : 'حفظ ونشر'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class QuizCatsManager extends StatelessWidget {
  const QuizCatsManager({super.key});

  static const palette = [
    0xFF1F5E3B, 0xFF145A32, 0xFF2E6B73, 0xFF3B4A8C, 0xFF5B3A7A,
    0xFF9C3D3D, 0xFFB0602A, 0xFF8E6B1E, 0xFF7A4A1E, 0xFF37474F,
  ];

  Future<void> _edit(BuildContext context, QuizCat? c) async {
    final quiz = Quiz.instance;
    final cat = c ?? QuizCat(id: '', name: '', order: quiz.cats.length);
    final ctrl = TextEditingController(text: cat.name);
    var icon = cat.icon, color = cat.color, hidden = cat.hidden;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, set) => AlertDialog(
          title: Text(c == null ? 'تصنيف جديد' : 'تعديل التصنيف'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(labelText: 'الاسم (قصير، مثل: عقيدة)', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: Icon(chapterIcon(icon), color: kGold),
                label: const Text('اختر الأيقونة'),
                onPressed: () async {
                  final k = await pickChapterIcon(dc);
                  if (k != null) set(() => icon = k);
                },
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in palette)
                  GestureDetector(
                    onTap: () => set(() => color = p),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(p),
                      child: color == p ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ]),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إخفاء التصنيف'),
                value: hidden,
                onChanged: (v) => set(() => hidden = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dc, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    cat
      ..name = ctrl.text.trim()
      ..icon = icon
      ..color = color
      ..hidden = hidden;
    final String? err;
    if (cat.id.isEmpty) {
      err = await quiz.saveCat(QuizCat(id: 'd', name: cat.name, icon: icon, color: color, order: cat.order, hidden: hidden));
    } else {
      err = await quiz.saveCat(cat);
    }
    if (context.mounted) _toast(context, err ?? 'تم الحفظ', ok: err == null);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Quiz.instance,
        builder: (context, _) {
          final cats = [...Quiz.instance.cats];
          return Scaffold(
            appBar: AppBar(title: const Text('إدارة التصنيفات')),
            floatingActionButton: FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('تصنيف جديد'),
              onPressed: () => _edit(context, null),
            ),
            body: Column(children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('اسحب لترتيب الأزرار، واضغط لتعديل الاسم والأيقونة واللون، أو لإخفاء التصنيف.',
                    style: TextStyle(color: Colors.grey)),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 90),
                  itemCount: cats.length,
                  onReorder: (a, b) {
                    if (b > a) b--;
                    cats.insert(b, cats.removeAt(a));
                    Quiz.instance.reorderCats(cats);
                  },
                  itemBuilder: (context, i) => ListTile(
                    key: ValueKey(cats[i].id),
                    leading: CircleAvatar(
                        backgroundColor: Color(cats[i].color), child: Icon(chapterIcon(cats[i].icon), color: kGold)),
                    title: Text(cats[i].name),
                    subtitle: Text(
                        '${Quiz.instance.inCat(cats[i].id).length} سؤالاً${cats[i].hidden ? ' · مخفي' : ''}'),
                    trailing: const Icon(Icons.drag_handle),
                    onTap: () => _edit(context, cats[i]),
                  ),
                ),
              ),
            ]),
          );
        },
      );
}

class QuizSuggestionsScreen extends StatelessWidget {
  const QuizSuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الأسئلة المقترحة')),
        body: StreamBuilder(
          stream: Quiz.instance.suggestions(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (docs.isEmpty) return const EmptyState(icon: Icons.inbox_outlined, text: 'لا اقتراحات الآن.');
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final d = docs[i];
                final m = d.data();
                final choices = [for (final c in (m['choices'] as List? ?? const [])) '$c'];
                return ListTile(
                  title: Text('${m['text'] ?? ''}', style: const TextStyle(height: 1.6)),
                  subtitle: Text('من: ${m['nick'] ?? ''}\n${choices.where((c) => c.isNotEmpty).join(' / ')}'),
                  isThreeLine: true,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'قبول وتعديل',
                      icon: const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32)),
                      onPressed: () async {
                        final q = QuizQ(
                          id: '',
                          cat: '${m['cat'] ?? ''}',
                          text: '${m['text'] ?? ''}',
                          choices: [for (final c in choices) if (c.isNotEmpty) c],
                          correct: (m['correct'] as num?)?.toInt() ?? 0,
                          explain: '${m['explain'] ?? ''}',
                          suggestedBy: '${m['nick'] ?? ''}',
                          showSuggester: true,
                        );
                        final saved = await Navigator.of(context)
                            .push<bool>(MaterialPageRoute(builder: (_) => QuestionEditor(q: q)));
                        if (saved == true) await Quiz.instance.dropSuggestion(d.id);
                      },
                    ),
                    IconButton(
                      tooltip: 'رفض',
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => Quiz.instance.dropSuggestion(d.id),
                    ),
                  ]),
                );
              },
            );
          },
        ),
      );
}

class QuizStatsScreen extends StatelessWidget {
  const QuizStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quiz = Quiz.instance;
    final l = quiz.missed;
    final answers = l.fold<int>(0, (s, e) => s + e.$2);
    return Scaffold(
      appBar: AppBar(title: const Text('إحصاءات الأسئلة')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text('${quiz.all.length} سؤالاً · $answers إجابة من الناس',
              style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('الأكثر خطأً أولاً — يدلّك على ما يحتاج شرحاً', style: TextStyle(color: Colors.grey)),
        ),
        for (final e in l)
          ListTile(
            title: Text(e.$1.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('أجاب ${e.$2} · أخطأ ${e.$3} (${(e.$3 * 100 / math.max(1, e.$2)).round()}٪)'),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => QuestionEditor(q: e.$1))),
            ),
          ),
        if (l.isEmpty) const EmptyState(icon: Icons.bar_chart, text: 'لا إجابات بعد.'),
      ]),
    );
  }
}
