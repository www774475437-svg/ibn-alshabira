import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
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
                      child: const Icon(Icons.person_outline, color: kGoldChip),
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
  int _at = -1; // which scholar the results are from
  List<_Hit> _hits = [];
  int _count = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial.trim().length > 2) WidgetsBinding.instance.addPostFrameCallback((_) => _search(0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<(int, List<_Hit>)> _ask(int author, String q) async {
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
    return (((j['count'] ?? hits.length) as num).toInt(), hits);
  }

  /// Searches the scholars in order, starting from [from], and stops at the
  /// first one who has something on the question.
  Future<void> _search(int from) async {
    final q = _c.text.trim();
    if (q.length < 3 || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
      _hits = [];
      _at = -1;
    });
    try {
      for (var i = from; i < _order.length; i++) {
        setState(() => _status = 'جارٍ البحث في كتب الشيخ ${_order[i].$2}…');
        final (count, hits) = await _ask(_order[i].$1, q);
        if (hits.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _at = i;
            _hits = hits;
            _count = count;
            _busy = false;
          });
          return;
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'لم أجد كلاماً بهذه الألفاظ في كتب المشايخ. اكتب المسألة بكلمات أقل، مثل: «قتل النمل».';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = kIsWeb
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
            maxLines: 4,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(0),
            decoration: InputDecoration(
              hintText: 'اكتب المسألة باختصار، مثل: حكم قتل النمل',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white, minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.search),
            label: const Text('ابحث في كتب المشايخ', style: TextStyle(fontSize: 16)),
            onPressed: _busy ? null : () => _search(0),
          ),
          const SizedBox(height: 6),
          Text(
            'الترتيب: ${_order.map((e) => e.$2).join('، ثم ')}.\n'
            'يُعرض كلام الشيخ بنصّه من كتبه في «تراث» مع اسم الكتاب والصفحة، دون أي كلام مؤلَّف.',
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
          if (_at >= 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'من كتب الشيخ ${_order[_at].$2} · ${_ar(_count)} موضعاً',
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(height: 8),
            for (final h in _hits)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (h.headings.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(h.headings.last,
                              style: const TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
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
                              Clipboard.setData(ClipboardData(
                                  text: '${_plain(h.text)}\n\n[${_order[_at].$2}: ${h.source}]\n${h.url}'));
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text('نُسخ النص مع المصدر')));
                            },
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.article_outlined, size: 18),
                            label: const Text('الصفحة كاملة'),
                            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => _TurathPage(hit: h, scholar: _order[_at].$2, mark: mark))),
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
              ),
            if (_at + 1 < _order.length)
              OutlinedButton.icon(
                icon: const Icon(Icons.skip_next),
                label: Text('ابحث عند الشيخ التالي: ${_order[_at + 1].$2}'),
                onPressed: () => _search(_at + 1),
              ),
          ],
        ],
      ),
    );
  }
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
