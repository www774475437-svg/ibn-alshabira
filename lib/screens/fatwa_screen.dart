import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_extra.dart';
import 'ask_screen.dart';
import 'favorites_tab.dart';
import 'share_card_screen.dart';

/// Shows one answer; swipe (or use the arrows) to move through the other
/// answers of the same chapter, like turning the pages of a book.
class FatwaScreen extends StatefulWidget {
  final Fatwa fatwa;
  const FatwaScreen({super.key, required this.fatwa});

  @override
  State<FatwaScreen> createState() => _FatwaScreenState();
}

class _FatwaScreenState extends State<FatwaScreen> {
  final repo = Repository.instance;
  late final List<Fatwa> _pages;
  late final PageController _pager;
  late int _index;

  // Pinch-to-zoom with raw pointers (a Listener), so scrolling is untouched.
  final Map<int, Offset> _pointers = {};
  double? _startDistance;
  double _startScale = 1.0;
  double _scale = Repository.instance.readingScale;

  // Search inside the answer.
  bool _finding = false;
  String _find = '';

  Fatwa get current => _pages[_index];

  @override
  void initState() {
    super.initState();
    final siblings = repo.byChapter(widget.fatwa.chapter);
    _pages = siblings.any((f) => f.id == widget.fatwa.id) ? siblings : [widget.fatwa];
    _index = _pages.indexWhere((f) => f.id == widget.fatwa.id);
    _pager = PageController(initialPage: _index);
    repo.markRead(current.id);
    Cloud.instance.addView(current.id);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  double _distance() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      setState(() {
        _startDistance = _distance();
        _startScale = _scale;
      });
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _startDistance != null && _startDistance! > 0) {
      final next = (_startScale * _distance() / _startDistance!).clamp(0.8, 2.2);
      if ((next - _scale).abs() > 0.01) setState(() => _scale = next);
    }
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _startDistance != null) {
      setState(() => _startDistance = null);
      repo.saveReadingScale(_scale);
    }
  }

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= _pages.length) return;
    _pager.animateToPage(target,
        duration: const Duration(milliseconds: 420), curve: Curves.easeInOutCubic);
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _copyOptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('نسخ الجواب كما هو (بالتشكيل)'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: current.shareText));
                _toast('تم النسخ');
              },
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('نسخ الجواب دون تشكيل'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: stripTashkeel(current.shareText)));
                _toast('تم النسخ دون تشكيل');
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('نسخ رابط الجواب'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: AppConfig.fatwaLink(current.id)));
                _toast('تم نسخ الرابط');
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Copies a short report to the clipboard and opens the developer's
  /// Telegram to paste it (until reports go to the online database).
  void _reportError() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الإبلاغ عن خطأ'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'اكتب الخطأ الذي وجدته (اختياري)…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final note = controller.text.trim();
              if (Cloud.instance.ready) {
                Cloud.instance.report(current, note).then((ok) {
                  if (mounted) _toast(ok ? 'وصل البلاغ، جزاك الله خيراً' : 'تعذّر إرسال البلاغ');
                });
                return;
              }
              final report = '⚠️ بلاغ عن خطأ في تطبيق «ابن الشابرة»\n'
                  'الجواب: ${current.title}\n'
                  'الرابط: ${AppConfig.fatwaLink(current.id)}\n'
                  'الملاحظة: ${note.isEmpty ? '—' : note}';
              Clipboard.setData(ClipboardData(text: report));
              _toast('نُسخ البلاغ، الصقه في رسالة المطوّر');
              openUrl(context, repo.developerUrl);
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  /// Title, chapter and sub-chapter of an answer that came with the app.
  void _editTitle() {
    final f = current;
    final c = TextEditingController(text: f.title);
    var chapter = f.chapter;
    var sub = f.sub;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('تعديل الجواب'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: c,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: repo.chapters.any((x) => x.id == chapter) ? chapter : repo.chapters.last.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الباب', border: OutlineInputBorder()),
                  items: [for (final x in repo.chapters) DropdownMenuItem(value: x.id, child: Text(x.name))],
                  onChanged: (v) => setS(() {
                    chapter = v ?? chapter;
                    sub = '';
                  }),
                ),
                SubPicker(chapterId: chapter, value: sub, onChanged: (v) => setS(() => sub = v)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final err = await Cloud.instance.editBundled(f.id, title: c.text, chapter: chapter, sub: sub);
                if (mounted) _toast(err ?? 'تم الحفظ ✅');
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final fav = repo.isFavorite(current.id);
        final later = repo.isReadLater(current.id);
        return Scaffold(
          appBar: AppBar(
            title: _finding
                ? TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'ابحث داخل الجواب',
                      hintStyle: const TextStyle(color: Colors.white60),
                      border: InputBorder.none,
                      suffixText: _find.trim().length < 2
                          ? null
                          : '${countMatches('${current.title}\n${current.question}\n${current.answer}', _find)} موضع',
                      suffixStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    onChanged: (v) => setState(() => _find = v),
                  )
                : Text(current.typeLabel),
            actions: [
              IconButton(
                tooltip: _finding ? 'إغلاق البحث' : 'بحث داخل الجواب',
                icon: Icon(_finding ? Icons.close : Icons.manage_search),
                onPressed: () => setState(() {
                  _finding = !_finding;
                  _find = '';
                }),
              ),
              if (!_finding)
              ListenableBuilder(
                listenable: Cloud.instance,
                builder: (context, _) => Cloud.instance.isAdmin
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (Cloud.instance.isFullAdmin)
                            IconButton(
                              tooltip: 'تثبيت في الرئيسية',
                              icon: Icon(Cloud.instance.pinned.contains(current.id)
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined),
                              onPressed: () async {
                                final was = Cloud.instance.pinned.contains(current.id);
                                final err = await Cloud.instance.togglePin(current.id);
                                if (mounted) _toast(err ?? (was ? 'أُزيل التثبيت' : 'ثُبّت في الرئيسية ✅'));
                              },
                            ),
                          IconButton(
                            tooltip: 'إضافة إلى سلسلة',
                            icon: const Icon(Icons.playlist_add),
                            onPressed: () => showSeriesSheet(context, current),
                          ),
                          IconButton(
                            tooltip: 'تعديل',
                            icon: const Icon(Icons.edit),
                            onPressed: () => Cloud.instance.isRemote(current.id)
                                ? Navigator.of(context).push(MaterialPageRoute(
                                    builder: (_) => EditAnswerScreen(fatwa: current)))
                                : _editTitle(),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              if (!_finding)
              IconButton(
                tooltip: later ? 'إزالة من «اقرأ لاحقاً»' : 'اقرأ لاحقاً',
                icon: Icon(later ? Icons.watch_later : Icons.watch_later_outlined),
                onPressed: () {
                  repo.toggleReadLater(current.id);
                  _toast(later ? 'أُزيل من «اقرأ لاحقاً»' : 'أُضيف إلى «اقرأ لاحقاً»');
                },
              ),
              if (!_finding)
              IconButton(
                tooltip: fav ? 'إزالة من المحفوظات' : 'حفظ',
                icon: Icon(fav ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => repo.toggleFavorite(current.id),
              ),
            ],
          ),
          body: Listener(
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: PageView.builder(
              controller: _pager,
              // While two fingers are zooming, don't turn the page.
              physics: _startDistance != null
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: _pages.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                repo.markRead(_pages[i].id);
                Cloud.instance.addView(_pages[i].id);
              },
              itemBuilder: (context, i) => _AnswerBody(
                fatwa: _pages[i],
                scale: _scale,
                find: _finding ? _find : '',
                onCopy: _copyOptions,
                onReport: _reportError,
              ),
            ),
          ),
          bottomNavigationBar: _pages.length > 1
              ? _PagerBar(
                  index: _index,
                  count: _pages.length,
                  onPrev: () => _go(-1),
                  onNext: () => _go(1),
                )
              : null,
        );
      },
    );
  }
}

/// Elegant previous / next bar. In Arabic (right-to-left) "previous" sits
/// on the right and "next" on the left, like a book.
class _PagerBar extends StatelessWidget {
  final int index;
  final int count;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _PagerBar({required this.index, required this.count, required this.onPrev, required this.onNext});

  Widget _arrow(BuildContext context,
      {required bool enabled,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      required bool iconFirst}) {
    final scheme = Theme.of(context).colorScheme;
    final color = enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.25);
    final parts = <Widget>[
      Icon(icon, size: 20, color: color),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15)),
    ];
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: enabled ? kGold.withValues(alpha: 0.13) : Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: iconFirst ? parts : parts.reversed.toList(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          border: Border(top: BorderSide(color: kGold.withValues(alpha: 0.25))),
        ),
        child: Row(
          children: [
            _arrow(context,
                enabled: index > 0,
                icon: Icons.arrow_forward_ios_rounded,
                label: 'السابق',
                onTap: onPrev,
                iconFirst: true),
            const Spacer(),
            Text('${index + 1} من $count',
                style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
            const Spacer(),
            _arrow(context,
                enabled: index < count - 1,
                icon: Icons.arrow_back_ios_new_rounded,
                label: 'التالي',
                onTap: onNext,
                iconFirst: false),
          ],
        ),
      ),
    );
  }
}

class _AnswerBody extends StatelessWidget {
  final Fatwa fatwa;
  final double scale;
  final String find;
  final VoidCallback onCopy;
  final VoidCallback onReport;
  const _AnswerBody(
      {required this.fatwa,
      required this.scale,
      this.find = '',
      required this.onCopy,
      required this.onReport});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final words = '${fatwa.question} ${fatwa.answer}'.split(RegExp(r'\s+')).length;
    final minutes = (words / 180).ceil().clamp(1, 999);
    final isArticle = fatwa.type == 'article';
    Widget chip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: kGoldChip),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(fontSize: 12.5, color: kGoldChip, fontWeight: FontWeight.w600)),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(Icons.folder_outlined, repo.chapterName(fatwa.chapter)),
            if (fatwa.sub.isNotEmpty) chip(Icons.subdirectory_arrow_left, fatwa.sub),
            chip(isArticle ? Icons.article_outlined : Icons.question_answer_outlined, isArticle ? 'مقال' : 'جواب'),
            chip(Icons.schedule, '$minutes د قراءة'),
            if (fatwa.date.isNotEmpty) chip(Icons.event_outlined, fatwa.date),
          ],
        ),
        const SizedBox(height: 14),
        SelectableText(fatwa.title,
            style: TextStyle(
                fontFamily: 'Tajawal', fontSize: 21 * scale, fontWeight: FontWeight.bold, height: 1.6)),
        const SizedBox(height: 16),
        if (fatwa.question.isNotEmpty) ...[
          _Block(label: 'السؤال', icon: Icons.help_outline, text: fatwa.question, highlight: true, scale: scale, find: find),
          const SizedBox(height: 18),
          const _Ornament(label: 'الجواب'),
          const SizedBox(height: 6),
        ],
        _Block(text: fatwa.answer, plain: true, scale: scale, find: find),
        if (fatwa.source.startsWith('http'))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('المصدر: قناة الشيخ على تيليجرام'),
              onPressed: () => openUrl(context, fatwa.source),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('قرّب إصبعيك أو باعدهما لتكبير الخط · واسحب يميناً أو يساراً للجواب التالي',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: Colors.grey)),
        ),
        if (fatwa.tags.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in fatwa.tags)
                ActionChip(
                  label: Text('#$t'),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => TagScreen(tag: t))),
                ),
            ],
          ),
        ],
        _CloudPanel(fatwa: fatwa),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('نسخ'),
                onPressed: onCopy,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('مشاركة'),
                onPressed: () => Share.share(fatwa.shareText),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (fatwa.audio.startsWith('http'))
              FilledButton.tonalIcon(
                icon: const Icon(Icons.headphones, size: 20),
                label: const Text('استمع للجواب'),
                onPressed: () => openUrl(context, fatwa.audio),
              ),
            TextButton.icon(
              icon: const Icon(Icons.contact_support_outlined, size: 20),
              label: const Text('اسأل عن هذا الجواب'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => AskScreen(about: fatwa))),
            ),
            TextButton.icon(
              icon: const Icon(Icons.image_outlined, size: 20),
              label: const Text('بطاقة مصوّرة'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => ShareCardScreen(fatwa: fatwa))),
            ),
            TextButton.icon(
              icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              label: const Text('أضف إلى مجلد'),
              onPressed: () => showFolderSheet(context, fatwa),
            ),
            TextButton.icon(
              icon: const Icon(Icons.flag_outlined, size: 20),
              label: const Text('الإبلاغ عن خطأ'),
              onPressed: onReport,
            ),
            if (fatwa.source.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 20),
                label: const Text('المصدر'),
                onPressed: () => openUrl(context, fatwa.source),
              ),
          ],
        ),
        ..._related(context, repo),
        const SizedBox(height: 12),
      ],
    );
  }

  List<Widget> _related(BuildContext context, Repository repo) {
    final items = repo.related(fatwa);
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      const Divider(),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('أجوبة ذات صلة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      for (final f in items)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.article_outlined, color: kGold),
            title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('باب ${repo.chapterName(f.chapter)}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => openFatwa(context, f),
          ),
        ),
    ];
  }
}

/// Views count and «هل أفادك الجواب؟» (Android app, online).
class _CloudPanel extends StatefulWidget {
  final Fatwa fatwa;
  const _CloudPanel({required this.fatwa});

  @override
  State<_CloudPanel> createState() => _CloudPanelState();
}

class _CloudPanelState extends State<_CloudPanel> {
  Map<String, int> _stats = {};
  bool _voted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // One vote per answer on this device, remembered for good.
    final prefs = await SharedPreferences.getInstance();
    if ((prefs.getStringList('votedAnswers') ?? const []).contains(widget.fatwa.id)) {
      if (mounted) setState(() => _voted = true);
    }
    await Future.delayed(const Duration(milliseconds: 600));
    final s = await Cloud.instance.stats(widget.fatwa.id);
    if (mounted) setState(() => _stats = s);
  }

  Future<void> _vote(bool yes) async {
    if (_voted) return;
    setState(() => _voted = true);
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('votedAnswers') ?? <String>[];
    if (list.contains(widget.fatwa.id)) return;
    await prefs.setStringList('votedAnswers', [...list, widget.fatwa.id]);
    await Cloud.instance.vote(widget.fatwa.id, yes);
    if (!yes && mounted) _askWhy();
  }

  /// «لم يفدني»: ask why, so the staff know what to improve.
  void _askWhy() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('ما الذي نقص في الجواب؟ (اختياري)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (final r in const [
              'الجواب غير واضح',
              'الجواب مختصر وأحتاج تفصيلاً',
              'ليس هذا ما أبحث عنه',
              'فيه خطأ في الكتابة',
            ])
              ListTile(
                leading: const Icon(Icons.chevron_left),
                title: Text(r),
                onTap: () {
                  Navigator.pop(ctx);
                  Cloud.instance.report(widget.fatwa, 'لم يفدني: $r');
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('شكراً، وصلت ملاحظتك')));
                },
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تخطٍّ')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Cloud.instance.ready) return const SizedBox.shrink();
    final views = _stats['count'];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            if (views != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.visibility_outlined, size: 18, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('$views مشاهدة', style: const TextStyle(color: Colors.grey)),
                ],
              ),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _voted
                  ? const Text('جزاك الله خيراً على رأيك 🌿', key: ValueKey('t'))
                  : Row(
                      key: const ValueKey('q'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('هل أفادك الجواب؟', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => _vote(true),
                          icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                          label: const Text('نعم'),
                        ),
                        TextButton.icon(
                          onPressed: () => _vote(false),
                          icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                          label: const Text('لا'),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Removes Arabic diacritics (tashkeel) and tatweel.
String stripTashkeel(String s) =>
    s.replaceAll(RegExp(r'[ؐ-ًؚ-ٰٟۖ-ۭـ]'), '');

/// Quran verses ﴿…﴾ in green with the Amiri font, hadith «…» in gold.
List<TextSpan> highlightSpans(String text, TextStyle base, [String find = '']) {
  final plain = _styledSpans(text);
  final re = findPattern(find);
  if (re == null) return plain;
  // Mark the searched word inside every span.
  final out = <TextSpan>[];
  for (final s in plain) {
    final t = s.text ?? '';
    var last = 0;
    for (final m in re.allMatches(t)) {
      if (m.end == m.start) continue;
      if (m.start > last) out.add(TextSpan(text: t.substring(last, m.start), style: s.style));
      out.add(TextSpan(
        text: t.substring(m.start, m.end),
        style: (s.style ?? const TextStyle())
            .copyWith(backgroundColor: const Color(0xFFFFE082), color: Colors.black),
      ));
      last = m.end;
    }
    if (last < t.length) out.add(TextSpan(text: t.substring(last), style: s.style));
  }
  return out;
}

/// A pattern that finds [query] ignoring tashkeel and hamza forms.
RegExp? findPattern(String query) {
  final q = stripTashkeel(query.trim());
  if (q.length < 2) return null;
  const marks = '[\\u064B-\\u065F\\u0670\\u0640]*';
  final parts = <String>[];
  for (final ch in q.split('')) {
    if ('اأإآ'.contains(ch)) {
      parts.add('[اأإآ]');
    } else if ('ةه'.contains(ch)) {
      parts.add('[ةه]');
    } else if ('ىي'.contains(ch)) {
      parts.add('[ىي]');
    } else {
      parts.add(RegExp.escape(ch));
    }
  }
  return RegExp(parts.join(marks));
}

int countMatches(String text, String query) => findPattern(query)?.allMatches(text).length ?? 0;

List<TextSpan> _styledSpans(String text) {
  final spans = <TextSpan>[];
  final re = RegExp(r'﴿[^﴾]*﴾|«[^»]*»');
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    final part = m.group(0)!;
    final isVerse = part.startsWith('﴿');
    spans.add(TextSpan(
      text: part,
      style: isVerse
          ? const TextStyle(color: Color(0xFF2E7D4F), fontFamily: 'Amiri', fontWeight: FontWeight.bold)
          : const TextStyle(color: kGoldChip, fontWeight: FontWeight.w600),
    ));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

/// «ـــــ ◆ الجواب ◆ ـــــ»
class _Ornament extends StatelessWidget {
  final String label;
  const _Ornament({required this.label});

  @override
  Widget build(BuildContext context) {
    Widget line() => Expanded(child: Container(height: 1, color: kGold.withValues(alpha: 0.5)));
    return Row(
      children: [
        line(),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.diamond, size: 10, color: kGold)),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16, color: kGoldChip)),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.diamond, size: 10, color: kGold)),
        line(),
      ],
    );
  }
}

class _Block extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String text;
  final bool highlight;
  final bool plain;
  final double scale;
  final String find;
  const _Block(
      {this.label,
      this.icon,
      required this.text,
      this.highlight = false,
      this.plain = false,
      this.scale = 1.0,
      this.find = ''});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(fontSize: 17.5 * scale, height: 2.0, color: scheme.onSurface);
    // Paragraphs get their own space, so long answers read easily.
    final paragraphs = text.split(RegExp(r'\n\s*\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paragraphs.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == paragraphs.length - 1 ? 0 : 14),
            child: SelectableText.rich(
              TextSpan(style: base, children: highlightSpans(paragraphs[i], base, find)),
              textAlign: TextAlign.justify,
            ),
          ),
      ],
    );
    if (plain) return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: body);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: highlight ? kGold.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(16),
        border: BorderDirectional(
          start: BorderSide(color: highlight ? kGold : scheme.outlineVariant, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: kGoldChip), const SizedBox(width: 6)],
              Text(label!,
                  style: const TextStyle(fontFamily: 'Tajawal', color: kGoldChip, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 6),
          ],
          body,
        ],
      ),
    );
  }
}
