import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../services/ai.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'content_screens.dart';

// ---------------------------------------------------------------------------
// «المشايخ الثقات»: a fixed list chosen by the developer. Biographies and the
// lists of books come from the public data of «تراث»; the books themselves are
// never bundled: each opens in «تراث» when the reader asks.
// ---------------------------------------------------------------------------

class TrustedBook {
  final int id;
  final String name;
  final int pages;
  final bool pdf;
  TrustedBook(this.id, this.name, this.pages, this.pdf);
}

class TrustedScholar {
  final int id;
  final String name;
  final String full;
  final int? death;
  final String bio;
  final List<TrustedBook> books;
  TrustedScholar(this.id, this.name, this.full, this.death, this.bio, this.books);
}

Future<List<TrustedScholar>>? _scholars;

Future<List<TrustedScholar>> loadTrustedScholars() => _scholars ??= () async {
      final list = jsonDecode(await rootBundle.loadString('assets/data/scholars.json')) as List;
      return [
        for (final s in list)
          TrustedScholar(
            ((s as Map)['id'] as num).toInt(),
            '${s['name']}',
            '${s['full'] ?? s['name']}',
            (s['death'] as num?)?.toInt(),
            '${s['bio'] ?? ''}',
            [
              for (final b in (s['books'] ?? []) as List)
                TrustedBook(((b as Map)['id'] as num).toInt(), '${b['name']}', ((b['pages'] ?? 0) as num).toInt(),
                    b['pdf'] == true),
            ],
          ),
      ];
    }();

String _ar(int n) {
  const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  return '$n'.split('').map((c) => d[int.parse(c)]).join();
}

/// Opens a page of «تراث» in a browser sheet over the app (the phone's own
/// browser on the site).
Future<void> openTurath(BuildContext context, String url) async {
  var ok = false;
  try {
    ok = await launchUrl(Uri.parse(url), mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView);
  } catch (_) {}
  if (!ok) {
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح الرابط')));
  }
}

class TrustedScholarsScreen extends StatelessWidget {
  const TrustedScholarsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المشايخ الثقات'),
        actions: [
          IconButton(
            tooltip: 'قائمة أضافها المشرفون',
            icon: const Icon(Icons.playlist_add_check),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScholarsScreen())),
          ),
        ],
      ),
      body: FutureBuilder<List<TrustedScholar>>(
        future: loadTrustedScholars(),
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('تعذّر تحميل القائمة'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Material(
                color: const Color(0xFF2E7D32),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const TrustedFatwaScreen())),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.manage_search, color: Colors.white, size: 32),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('بحث الفتاوى من كتب الثقات',
                              style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                        ),
                        Icon(Icons.chevron_left, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              for (final s in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: kGold.withValues(alpha: 0.18),
                      child: Icon(Icons.person_outline, color: kGoldChip),
                    ),
                    title: Text(s.name,
                        style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                    subtitle: Text([
                      if (s.death != null) 'ت ${_ar(s.death!)} هـ',
                      if (s.books.isNotEmpty) '${_ar(s.books.length)} كتاباً',
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ScholarPage(scholar: s))),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('التراجم وقوائم الكتب من موقع «تراث»',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ScholarPage extends StatefulWidget {
  final TrustedScholar scholar;
  const ScholarPage({super.key, required this.scholar});

  @override
  State<ScholarPage> createState() => _ScholarPageState();
}

class _ScholarPageState extends State<ScholarPage> {
  bool _more = false;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.scholar;
    final books = _q.trim().isEmpty ? s.books : s.books.where((b) => b.name.contains(_q.trim())).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('التعريف بالشيخ',
                      style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 8),
                  if (s.bio.isEmpty)
                    const Text('الترجمة غير متوفرة الآن.', style: TextStyle(color: Colors.grey))
                  else ...[
                    Text(s.bio,
                        maxLines: _more ? null : 7,
                        overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, height: 1.9)),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: () => setState(() => _more = !_more),
                        child: Text(_more ? 'إخفاء' : 'قراءة الترجمة كاملة'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('مؤلفاته (${_ar(s.books.length)})',
                    style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
          if (s.books.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'ابحث في أسماء الكتب',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (s.books.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('قائمة الكتب غير متوفرة الآن.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ),
          for (final b in books)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined, color: kGold),
                title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${_ar(b.pages)} صفحة${b.pdf ? ' · له نسخة مصوّرة للتنزيل في «تراث»' : ''}'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => openTurath(context, 'https://app.turath.io/book/${b.id}'),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// «بحث الفتاوى من كتب الثقات»: the question is searched in the scholars' books
// on «تراث», one scholar after another in a fixed order. Only the scholar's own
// words are shown, with the book, the volume and the page. Nothing is composed.
// ---------------------------------------------------------------------------

const _order = <(int, String)>[
  (57, 'ابن عثيمين'),
  (67, 'ابن باز'),
  (62, 'صالح الفوزان'),
  (54, 'ابن تيمية'),
  (14, 'ابن القيم'),
];

class _Hit {
  final int bookId;
  final int pageId;
  final String book;
  final String vol;
  final String page;
  final List<String> headings;
  final String text;
  _Hit(this.bookId, this.pageId, this.book, this.vol, this.page, this.headings, this.text);

  String get source => [book, if (vol.isNotEmpty && vol != '0') '$vol/$page' else page].join(' — ');
  String get url => 'https://app.turath.io/book/$bookId/$pageId';
}

/// The text of «تراث» with its marks: found words in yellow, titles in bold.
List<InlineSpan> _spans(String raw, {required Color mark}) {
  final out = <InlineSpan>[];
  final tag = RegExp(r'<[^>]*>');
  var em = false;
  var title = false;
  var pos = 0;
  void add(String t) {
    if (t.isEmpty) return;
    out.add(TextSpan(
      text: t,
      style: TextStyle(
        backgroundColor: em ? mark : null,
        fontWeight: title ? FontWeight.bold : null,
      ),
    ));
  }

  for (final m in tag.allMatches(raw)) {
    add(raw.substring(pos, m.start));
    final t = m.group(0)!;
    if (t == '<em>') {
      em = true;
    } else if (t == '</em>') {
      em = false;
    } else if (t.startsWith('<span') && t.contains('title')) {
      title = true;
    } else if (t == '</span>') {
      title = false;
    }
    pos = m.end;
  }
  add(raw.substring(pos));
  return out;
}

String _plain(String raw) => raw.replaceAll(RegExp(r'<[^>]*>'), '').trim();

/// One question of the message, and what was found for it.
class _Found {
  final String title;
  final List<String> queries;
  bool busy = true;
  String status = '';
  int at = -1; // index in [_order] of the scholar the texts are from
  List<_Hit> hits = [];
  String summary = '';
  bool reported = false;
  _Found(this.title, this.queries);
}

class TrustedFatwaScreen extends StatefulWidget {
  final String initial;
  const TrustedFatwaScreen({super.key, this.initial = ''});

  @override
  State<TrustedFatwaScreen> createState() => _TrustedFatwaScreenState();
}

class _TrustedFatwaScreenState extends State<TrustedFatwaScreen> {
  late final _c = TextEditingController(text: widget.initial);
  bool _busy = false;
  String _status = '';
  String _error = '';
  String _note = '';
  List<_Found> _found = [];
  int _run = 0; // a newer search cancels an older one

  bool get _ai => Ai.supported && Cloud.instance.aiEnabled;

  @override
  void initState() {
    super.initState();
    if (widget.initial.trim().length > 2) WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<List<_Hit>> _ask(int author, String q) async {
    final res = await http
        .get(Uri.parse('https://api.turath.io/search?q=${Uri.encodeQueryComponent(q)}&author=$author&ver=3'))
        .timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) throw Exception('status ${res.statusCode}');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final hits = <_Hit>[];
    for (final e in (j['data'] ?? []) as List) {
      final m = e as Map;
      Map meta = {};
      try {
        meta = jsonDecode('${m['meta']}') as Map;
      } catch (_) {}
      hits.add(_Hit(
        ((m['book_id'] ?? 0) as num).toInt(),
        ((meta['page_id'] ?? 0) as num).toInt(),
        '${meta['book_name'] ?? ''}',
        '${meta['vol'] ?? ''}',
        '${meta['page'] ?? ''}',
        [for (final h in (meta['headings'] ?? []) as List) '$h'],
        '${m['text'] ?? m['snip'] ?? ''}',
      ));
    }
    return hits;
  }

  Future<void> _search() async {
    final q = _c.text.trim();
    if (q.length < 3 || _busy) return;
    FocusScope.of(context).unfocus();
    final run = ++_run;
    setState(() {
      _busy = true;
      _error = '';
      _note = '';
      _found = [];
      _status = _ai ? 'جارٍ قراءة السؤال وتقسيمه إلى مسائله…' : 'جارٍ البحث…';
    });
    List<AiIssue>? issues;
    if (_ai) issues = await Ai.split(q);
    if (!mounted || run != _run) return;
    final found = [
      if (issues != null)
        for (final i in issues) _Found(i.title, i.queries)
      else
        _Found(q, [q]),
    ];
    setState(() {
      _found = found;
      _busy = false;
      if (issues == null && _ai) {
        _note = 'تعذّر الوصول إلى الذكاء الاصطناعي الآن، فبُحث عن السؤال كما كتبته. اكتب المسألة باختصار لنتيجة أدق.';
      }
    });
    for (final f in found) {
      await _fill(f, 0, run, summarize: issues != null && Cloud.instance.aiSummary);
      if (!mounted || run != _run) return;
    }
  }

  /// Looks for one question at the scholars in order, starting from [from].
  /// With [summarize], a scholar is kept only when his texts do speak of the
  /// question, and a short ruling is written from those texts alone.
  Future<void> _fill(_Found f, int from, int run, {required bool summarize}) async {
    setState(() {
      f.busy = true;
      f.hits = [];
      f.summary = '';
      f.at = -1;
    });
    try {
      for (var i = from; i < _order.length; i++) {
        if (!mounted || run != _run) return;
        setState(() => f.status = 'جارٍ البحث في كتب الشيخ ${_order[i].$2}…');
        final hits = <_Hit>[];
        for (final q in f.queries) {
          for (final h in await _ask(_order[i].$1, q)) {
            if (hits.length < 6 && !hits.any((x) => x.bookId == h.bookId && x.pageId == h.pageId)) hits.add(h);
          }
          if (hits.length >= 6) break;
        }
        if (hits.isEmpty) continue;
        if (!summarize) {
          if (!mounted || run != _run) return;
          setState(() {
            f.at = i;
            f.hits = hits;
            f.busy = false;
          });
          return;
        }
        if (!mounted || run != _run) return;
        setState(() => f.status = 'جارٍ قراءة كلام الشيخ ${_order[i].$2}…');
        final sum = await Ai.summarize(_order[i].$2, f.title, [for (final h in hits) _plain(h.text)]);
        if (!mounted || run != _run) return;
        if (sum == null) {
          // The AI did not answer: show the texts alone.
          setState(() {
            f.at = i;
            f.hits = hits;
            f.busy = false;
          });
          return;
        }
        if (!sum.found) continue; // these texts are about something else
        setState(() {
          f.at = i;
          f.summary = sum.text;
          // The texts the ruling rests on come first; the rest are left out.
          f.hits = sum.used.isEmpty ? hits.take(2).toList() : [for (final u in sum.used) hits[u]];
          f.busy = false;
        });
        return;
      }
      if (!mounted || run != _run) return;
      setState(() {
        f.busy = false;
        f.status = 'لم أجد للمشايخ كلاماً في هذه المسألة بهذه الألفاظ.';
      });
    } catch (_) {
      if (!mounted || run != _run) return;
      setState(() {
        f.busy = false;
        f.status = kIsWeb
            ? 'البحث في كتب الثقات يعمل الآن من تطبيق أندرويد. موقع «تراث» لا يسمح بالبحث من داخل المواقع الأخرى.'
            : 'تعذّر الاتصال بموقع «تراث». حاول بعد قليل.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mark = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF7A6200) : const Color(0xFFFFF176);
    return Scaffold(
      appBar: AppBar(title: const Text('بحث الفتاوى من كتب الثقات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
        children: [
          TextField(
            controller: _c,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: _ai ? 'اكتب سؤالك كما تريد، ولو كان فيه أكثر من مسألة' : 'اكتب المسألة باختصار، مثل: حكم قتل النمل',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.search),
            label: const Text('ابحث في كتب المشايخ', style: TextStyle(fontSize: 16)),
            onPressed: _busy ? null : _search,
          ),
          const SizedBox(height: 6),
          Text(
            'الترتيب: ${_order.map((e) => e.$2).join('، ثم ')}.\n'
            'يُعرض كلام الشيخ بنصّه من كتبه في «تراث» مع اسم الكتاب والصفحة.',
            style: const TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.7),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 14),
                  Text(_status),
                ],
              ),
            ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error, textAlign: TextAlign.center, style: const TextStyle(height: 1.8)),
            ),
          if (_note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_note, style: const TextStyle(color: Colors.orange, fontSize: 13, height: 1.7)),
            ),
          for (final f in _found) ..._issue(f, mark),
        ],
      ),
    );
  }

  List<Widget> _issue(_Found f, Color mark) {
    return [
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(f.title,
            style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
      ),
      if (f.busy)
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
              const SizedBox(width: 12),
              Expanded(child: Text(f.status)),
            ],
          ),
        )
      else if (f.at < 0)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(f.status, style: const TextStyle(height: 1.8)),
        )
      else ...[
        if (f.summary.isNotEmpty)
          Card(
            margin: const EdgeInsets.only(top: 8),
            color: kGold.withValues(alpha: 0.14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('خلاصة كلام الشيخ ${_order[f.at].$2}',
                      style: TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  SelectableText(f.summary, style: const TextStyle(fontSize: 17, height: 1.9)),
                  const SizedBox(height: 6),
                  const Text('هذا تلخيص آلي لكلام الشيخ قد يخطئ، والمرجع نصّه المنقول أدناه.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      icon: Icon(f.reported ? Icons.check : Icons.flag_outlined, size: 18),
                      label: Text(f.reported ? 'وصل البلاغ' : 'إبلاغ عن خطأ في التلخيص'),
                      onPressed: f.reported
                          ? null
                          : () async {
                              final err = await Cloud.instance.reportAi('${_c.text.trim()}\nالمسألة: ${f.title}', f.summary);
                              if (!mounted) return;
                              setState(() => f.reported = err == null);
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text(err ?? 'وصل بلاغك، جزاك الله خيراً')));
                            },
                    ),
                  ),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6, right: 4),
          child: Text('نص كلام الشيخ ${_order[f.at].$2} من كتبه:',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (final h in f.hits) _hitCard(h, f.at, mark),
        if (f.at + 1 < _order.length)
          OutlinedButton.icon(
            icon: const Icon(Icons.skip_next),
            label: Text('ابحث عند الشيخ التالي: ${_order[f.at + 1].$2}'),
            onPressed: () => _fill(f, f.at + 1, _run, summarize: f.summary.isNotEmpty),
          ),
      ],
    ];
  }

  Widget _hitCard(_Hit h, int at, Color mark) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (h.headings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(h.headings.last, style: TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
                ),
              SelectableText.rich(
                TextSpan(children: _spans(h.text, mark: mark)),
                style: const TextStyle(fontSize: 17, height: 1.95),
              ),
              const SizedBox(height: 8),
              Text('📓 ${h.source}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('نسخ'),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: '${_plain(h.text)}\n\n[${_order[at].$2}: ${h.source}]\n${h.url}'));
                      ScaffoldMessenger.of(context)
                          .showSnackBar(const SnackBar(content: Text('نُسخ النص مع المصدر')));
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('الصفحة كاملة'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => _TurathPage(hit: h, scholar: _order[at].$2, mark: mark))),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('فتح في «تراث»'),
                    onPressed: () => openTurath(context, h.url),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

/// A whole page of the book, read inside the app, with next and previous.
class _TurathPage extends StatefulWidget {
  final _Hit hit;
  final String scholar;
  final Color mark;
  const _TurathPage({required this.hit, required this.scholar, required this.mark});

  @override
  State<_TurathPage> createState() => _TurathPageState();
}

class _TurathPageState extends State<_TurathPage> {
  late int _pg = widget.hit.pageId;
  String? _text;
  String _where = '';
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _text = null;
      _failed = false;
    });
    try {
      final res = await http
          .get(Uri.parse('https://api.turath.io/page?book_id=${widget.hit.bookId}&pg=$_pg&ver=3'))
          .timeout(const Duration(seconds: 25));
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      Map meta = {};
      try {
        meta = jsonDecode('${j['meta']}') as Map;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _text = '${j['text'] ?? ''}';
        final vol = '${meta['vol'] ?? ''}';
        _where = [if (vol.isNotEmpty && vol != '0') 'ج $vol', 'ص ${meta['page'] ?? ''}'].join(' · ');
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.hit;
    // On the page the search opened, the found passage is shown with its marks.
    final first = _pg == h.pageId;
    return Scaffold(
      appBar: AppBar(
        title: Text(h.book, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'فتح في «تراث»',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => openTurath(context, 'https://app.turath.io/book/${h.bookId}/$_pg'),
          ),
        ],
      ),
      body: _failed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تعذّر تحميل الصفحة'),
                  TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ],
              ),
            )
          : _text == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                  children: [
                    Text('${widget.scholar} · $_where', style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 10),
                    if (first) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: widget.mark.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText.rich(
                          TextSpan(children: _spans(h.text, mark: widget.mark)),
                          style: const TextStyle(fontSize: 17, height: 1.95),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text('نص الصفحة كاملاً:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                    SelectableText.rich(
                      TextSpan(children: _spans(_text!, mark: widget.mark)),
                      style: const TextStyle(fontSize: 17, height: 1.95),
                    ),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.chevron_right),
                label: const Text('الصفحة السابقة'),
                onPressed: _pg <= 1
                    ? null
                    : () {
                        _pg--;
                        _load();
                      },
              ),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.chevron_left),
                label: const Text('الصفحة التالية'),
                iconAlignment: IconAlignment.end,
                onPressed: () {
                  _pg++;
                  _load();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
