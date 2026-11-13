import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';
import '../widgets/common.dart';

/// The Quran text (Uthmani script, Hafs), bundled with the app and loaded
/// only when the mushaf is first opened. Pages follow the Madinah mushaf.
class QuranData {
  QuranData._();
  static QuranData? _instance;
  static Future<QuranData>? _loading;

  late final List<String> names; // surah names
  late final List<int> counts; // verses in each surah
  late final List<int> surahPage; // first page of each surah
  late final List<int> surahStart; // global index of each surah's first verse
  late final List<int> pageStart; // global index of each page's first verse
  late final List<int> juzPage; // first page of each juz
  late final List<String> verses;

  static const pages = 604;

  static Future<QuranData> load() => _loading ??= () async {
        final j = jsonDecode(await rootBundle.loadString('assets/data/quran.json')) as Map<String, dynamic>;
        final d = QuranData._();
        final s = j['s'] as List;
        d.names = [for (final e in s) '${(e as List)[0]}'];
        d.counts = [for (final e in s) ((e as List)[1] as num).toInt()];
        d.surahPage = [for (final e in s) ((e as List)[2] as num).toInt()];
        var acc = 0;
        d.surahStart = [
          for (final c in d.counts) (() {
            final v = acc;
            acc += c;
            return v;
          })(),
        ];
        d.pageStart = [for (final e in j['p'] as List) (e as num).toInt()];
        d.juzPage = [for (final e in j['j'] as List) (e as num).toInt()];
        d.verses = [for (final e in j['v'] as List) '$e'];
        _instance = d;
        return d;
      }();

  /// (surah 1-based, verse 1-based) of a global verse index.
  (int, int) at(int index) {
    var lo = 0, hi = surahStart.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (surahStart[mid] <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (lo + 1, index - surahStart[lo] + 1);
  }

  int indexOf(int surah, int verse) => surahStart[surah - 1] + verse - 1;

  /// Page (1-based) that holds a global verse index.
  int pageOf(int index) {
    var lo = 0, hi = pageStart.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (pageStart[mid] <= index) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  int juzOfPage(int page) {
    var j = 1;
    for (var i = 0; i < juzPage.length; i++) {
      if (juzPage[i] <= page) j = i + 1;
    }
    return j;
  }

  static String digits(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return '$n'.split('').map((c) => d[int.parse(c)]).join();
  }

  /// Plain letters only, for searching.
  static String plain(String s) => s
      .replaceAll(RegExp('[\\u064B-\\u065F\\u0670\\u06D6-\\u06ED\\u0640]'), '')
      .replaceAll(RegExp('[ٱأإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه');
}

const _markColors = <String, Color>{
  'yellow': Color(0xFFFFD54F),
  'red': Color(0xFFE57373),
  'green': Color(0xFF81C784),
  'blue': Color(0xFF64B5F6),
};
const _markNames = <String, String>{'yellow': 'أصفر', 'red': 'أحمر', 'green': 'أخضر', 'blue': 'أزرق'};

/// Coloured bookmarks: verse index → colour and the time it was saved.
class QuranMarks extends ChangeNotifier {
  QuranMarks._();
  static final QuranMarks instance = QuranMarks._();
  Map<int, (String, int)> marks = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final p = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(p.getString('quranMarks') ?? '{}') as Map<String, dynamic>;
      marks = {
        for (final e in raw.entries)
          int.parse(e.key): ('${(e.value as List)[0]}', ((e.value as List)[1] as num).toInt()),
      };
    } catch (_) {}
    notifyListeners();
  }

  Future<void> put(int index, String? color) async {
    if (color == null) {
      marks.remove(index);
    } else {
      marks[index] = (color, DateTime.now().millisecondsSinceEpoch);
    }
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString('quranMarks', jsonEncode({for (final e in marks.entries) '${e.key}': [e.value.$1, e.value.$2]}));
  }
}

/// The mushaf: one page per screen, turned like paper.
class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> {
  QuranData? _q;
  PageController? _pages;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final q = await QuranData.load();
    await QuranMarks.instance.load();
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _q = q;
      _page = (p.getInt('quranPage') ?? 1).clamp(1, QuranData.pages);
      _pages = PageController(initialPage: _page - 1);
    });
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    final p = page.clamp(1, QuranData.pages);
    _pages?.jumpToPage(p - 1);
  }

  Future<void> _openIndex() async {
    final q = _q!;
    final page = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => _IndexScreen(q: q)));
    if (page != null) _goTo(page);
  }

  Future<void> _openSearch() async {
    final q = _q!;
    final index = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => _SearchScreen(q: q)));
    if (index != null) _goTo(q.pageOf(index));
  }

  Future<void> _openMarks() async {
    final q = _q!;
    final index = await Navigator.of(context).push<int>(MaterialPageRoute(builder: (_) => _MarksScreen(q: q)));
    if (index != null) _goTo(q.pageOf(index));
  }

  Future<void> _askPage() async {
    final c = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('انتقل إلى صفحة'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'من 1 إلى 604', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('انتقال')),
        ],
      ),
    );
    if (n != null) _goTo(n);
  }

  @override
  Widget build(BuildContext context) {
    final q = _q;
    if (q == null) {
      return Scaffold(appBar: AppBar(title: const Text('المصحف')), body: const Center(child: CircularProgressIndicator()));
    }
    final (surah, _) = q.at(q.pageStart[_page - 1]);
    return Scaffold(
      appBar: AppBar(
        title: Text('سورة ${q.names[surah - 1]}', style: const TextStyle(fontFamily: 'Amiri', fontSize: 20)),
        actions: [
          IconButton(tooltip: 'بحث في المصحف', icon: const Icon(Icons.search), onPressed: _openSearch),
          IconButton(tooltip: 'العلامات', icon: const Icon(Icons.bookmarks_outlined), onPressed: _openMarks),
          IconButton(tooltip: 'الفهرس', icon: const Icon(Icons.format_list_bulleted), onPressed: _openIndex),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: QuranData.pages,
              onPageChanged: (i) async {
                setState(() => _page = i + 1);
                final p = await SharedPreferences.getInstance();
                p.setInt('quranPage', i + 1);
              },
              itemBuilder: (context, i) => _MushafPage(key: ValueKey(i), q: q, page: i + 1),
            ),
          ),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              onTap: _askPage,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                child: Row(
                  children: [
                    Text('الجزء ${QuranData.digits(q.juzOfPage(_page))}', style: const TextStyle(fontSize: 13)),
                    const Spacer(),
                    Text('صفحة ${QuranData.digits(_page)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    const Text('اضغط مطولاً على الآية', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MushafPage extends StatefulWidget {
  final QuranData q;
  final int page;
  const _MushafPage({super.key, required this.q, required this.page});

  @override
  State<_MushafPage> createState() => _MushafPageState();
}

class _MushafPageState extends State<_MushafPage> {
  final _recognizers = <LongPressGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _menu(int index) {
    final q = widget.q;
    final (s, v) = q.at(index);
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('سورة ${q.names[s - 1]} · الآية ${QuranData.digits(v)}',
                  textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 10),
              Text(q.verses[index],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 22, height: 2.0)),
              const SizedBox(height: 12),
              _Tafsir(surah: s, verse: v),
              const SizedBox(height: 12),
              const Text('علامة ملوّنة', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final e in _markColors.entries)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          QuranMarks.instance.put(index, e.key);
                          Navigator.pop(ctx);
                        },
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: e.value,
                          child: QuranMarks.instance.marks[index]?.$1 == e.key
                              ? const Icon(Icons.check, size: 18, color: Colors.black87)
                              : null,
                        ),
                      ),
                    ),
                  if (QuranMarks.instance.marks.containsKey(index))
                    TextButton(
                      onPressed: () {
                        QuranMarks.instance.put(index, null);
                        Navigator.pop(ctx);
                      },
                      child: const Text('إزالة العلامة'),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'نسخ الآية',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(
                          text: '﴿${q.verses[index]}﴾ [${q.names[s - 1]}: ${QuranData.digits(v)}]'));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخت الآية')));
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final start = q.pageStart[widget.page - 1];
    final end = widget.page < QuranData.pages ? q.pageStart[widget.page] : q.verses.length;
    final ink = Theme.of(context).colorScheme.onSurface;
    return ListenableBuilder(
      listenable: QuranMarks.instance,
      builder: (context, _) {
        // Split the page into parts: a new part begins with each new surah.
        final blocks = <Widget>[];
        var spans = <InlineSpan>[];
        void flush() {
          if (spans.isEmpty) return;
          blocks.add(Text.rich(
            TextSpan(children: spans),
            textAlign: TextAlign.justify,
            textDirection: TextDirection.rtl,
            style: TextStyle(fontFamily: 'AmiriQuran', fontSize: 23, height: 2.15, color: ink),
          ));
          spans = <InlineSpan>[];
        }

        for (var i = start; i < end; i++) {
          final (s, v) = q.at(i);
          if (v == 1) {
            flush();
            blocks.add(_SurahHeader(name: q.names[s - 1], basmala: s != 1 && s != 9));
          }
          final r = LongPressGestureRecognizer()..onLongPress = () => _menu(i);
          _recognizers.add(r);
          final mark = QuranMarks.instance.marks[i];
          spans.add(TextSpan(
            text: q.verses[i],
            recognizer: r,
            style: mark == null
                ? null
                : TextStyle(backgroundColor: _markColors[mark.$1]!.withValues(alpha: 0.45)),
          ));
          spans.add(TextSpan(
            text: ' ۝${QuranData.digits(v)} ',
            style: const TextStyle(color: kGold, fontFamily: 'AmiriQuran'),
          ));
        }
        flush();
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              border: Border.all(color: kGold.withValues(alpha: 0.7), width: 1.4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks),
          ),
        );
      },
    );
  }
}

class _SurahHeader extends StatelessWidget {
  final String name;
  final bool basmala;
  const _SurahHeader({required this.name, required this.basmala});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: kGold.withValues(alpha: 0.14),
            border: Border.all(color: kGold),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('سورة $name',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Amiri', fontSize: 20, fontWeight: FontWeight.bold)),
        ),
        if (basmala)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
                textAlign: TextAlign.center, style: TextStyle(fontFamily: 'AmiriQuran', fontSize: 22, height: 2.0)),
          ),
      ],
    );
  }
}

/// التفسير الميسر for one verse, fetched when asked (needs internet).
class _Tafsir extends StatefulWidget {
  final int surah, verse;
  const _Tafsir({required this.surah, required this.verse});

  @override
  State<_Tafsir> createState() => _TafsirState();
}

class _TafsirState extends State<_Tafsir> {
  static final _cache = <String, String>{};
  String? _text;
  bool _loading = false;
  String? _error;

  String get _key => '${widget.surah}:${widget.verse}';

  Future<void> _load() async {
    if (_cache[_key] != null) {
      setState(() => _text = _cache[_key]);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse(
              'https://cdn.jsdelivr.net/gh/fawazahmed0/quran-api@1/editions/ara-kingfahadquranc/${widget.surah}/${widget.verse}.json'))
          .timeout(const Duration(seconds: 12));
      final t = '${(jsonDecode(utf8.decode(res.bodyBytes)) as Map)['text'] ?? ''}';
      if (res.statusCode != 200 || t.isEmpty) throw Exception();
      _cache[_key] = t;
      if (mounted) setState(() => _text = t);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر جلب التفسير، تأكد من الاتصال بالإنترنت');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_text != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: kGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('التفسير الميسر', style: TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
            const SizedBox(height: 4),
            SelectableText(_text!, style: const TextStyle(height: 1.9, fontSize: 16)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.menu_book_outlined),
          label: const Text('التفسير الميسر'),
          onPressed: _loading ? null : _load,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }
}

class _IndexScreen extends StatelessWidget {
  final QuranData q;
  const _IndexScreen({required this.q});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('فهرس المصحف'),
          bottom: const TabBar(
            labelColor: Color(0xFFC9A54C),
            unselectedLabelColor: Colors.white70,
            indicatorColor: Color(0xFFC9A54C),
            tabs: [Tab(text: 'السور'), Tab(text: 'الأجزاء')],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              itemCount: 114,
              itemBuilder: (context, i) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: kGold.withValues(alpha: 0.18),
                  child: Text(QuranData.digits(i + 1), style: const TextStyle(color: kGoldChip, fontSize: 13)),
                ),
                title: Text('سورة ${q.names[i]}', style: const TextStyle(fontFamily: 'Amiri', fontSize: 19)),
                subtitle: Text('آياتها ${QuranData.digits(q.counts[i])}'),
                trailing: Text('ص ${QuranData.digits(q.surahPage[i])}', style: const TextStyle(color: Colors.grey)),
                onTap: () => Navigator.pop(context, q.surahPage[i]),
              ),
            ),
            ListView.builder(
              itemCount: 30,
              itemBuilder: (context, i) => ListTile(
                leading: const Icon(Icons.bookmark_outline, color: kGold),
                title: Text('الجزء ${QuranData.digits(i + 1)}'),
                trailing: Text('ص ${QuranData.digits(q.juzPage[i])}', style: const TextStyle(color: Colors.grey)),
                onTap: () => Navigator.pop(context, q.juzPage[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchScreen extends StatefulWidget {
  final QuranData q;
  const _SearchScreen({required this.q});

  @override
  State<_SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<_SearchScreen> {
  static List<String>? _plain;
  List<int> _hits = [];
  String _query = '';

  void _run(String text) {
    final q = widget.q;
    _plain ??= [for (final v in q.verses) QuranData.plain(v)];
    final words = QuranData.plain(text).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    setState(() {
      _query = text;
      _hits = words.isEmpty || QuranData.plain(text).trim().length < 2
          ? []
          : [
              for (var i = 0; i < _plain!.length; i++)
                if (words.every(_plain![i].contains)) i,
            ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.q;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
              hintText: 'ابحث في المصحف', hintStyle: TextStyle(color: Colors.white60), border: InputBorder.none),
          onChanged: _run,
        ),
      ),
      body: _query.trim().length < 2
          ? const EmptyState(icon: Icons.search, text: 'اكتب كلمة أو أكثر من الآية')
          : _hits.isEmpty
              ? const EmptyState(icon: Icons.search_off, text: 'لا توجد آيات بهذه الكلمات')
              : ListView.builder(
                  itemCount: _hits.length + 1,
                  itemBuilder: (context, n) {
                    if (n == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text('عدد الآيات: ${_hits.length}', style: const TextStyle(color: Colors.grey)),
                      );
                    }
                    final i = _hits[n - 1];
                    final (s, v) = q.at(i);
                    return ListTile(
                      title: Text(q.verses[i],
                          style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 19, height: 2.0)),
                      subtitle: Text('${q.names[s - 1]}: ${QuranData.digits(v)}',
                          style: const TextStyle(color: kGoldChip)),
                      onTap: () => Navigator.pop(context, i),
                    );
                  },
                ),
    );
  }
}

class _MarksScreen extends StatelessWidget {
  final QuranData q;
  const _MarksScreen({required this.q});

  static String _when(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.day}/${t.month}/${t.year} · $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('علاماتي في المصحف')),
      body: ListenableBuilder(
        listenable: QuranMarks.instance,
        builder: (context, _) {
          final items = QuranMarks.instance.marks.entries.toList()..sort((a, b) => b.value.$2.compareTo(a.value.$2));
          if (items.isEmpty) {
            return const EmptyState(
                icon: Icons.bookmarks_outlined, text: 'لا علامات بعد.\nاضغط مطولاً على أي آية واختر لوناً.');
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, n) {
              final e = items[n];
              final (s, v) = q.at(e.key);
              return ListTile(
                leading: CircleAvatar(radius: 12, backgroundColor: _markColors[e.value.$1] ?? kGold),
                title: Text('سورة ${q.names[s - 1]} · الآية ${QuranData.digits(v)}'),
                subtitle: Text('${_markNames[e.value.$1] ?? ''} · حُفظت ${_when(e.value.$2)}'),
                trailing: IconButton(
                  tooltip: 'حذف العلامة',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => QuranMarks.instance.put(e.key, null),
                ),
                onTap: () => Navigator.pop(context, e.key),
              );
            },
          );
        },
      ),
    );
  }
}
