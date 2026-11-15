import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/books_store.dart';
import '../theme.dart';

/// A bookmark on a page: its colour has a meaning, and it can carry a note.
class BookMark {
  final String book;
  final String bookTitle;
  final int page;
  final int color; // 0 فائدة (أخضر)، 1 مسألة (أصفر)، 2 للمراجعة (أحمر)
  final String note;
  final DateTime at;
  BookMark(this.book, this.bookTitle, this.page, this.color, this.note, this.at);

  static const names = ['فائدة', 'مسألة', 'للمراجعة'];
  static const colors = [Color(0xFF2E7D32), Color(0xFFF9A825), Color(0xFFC62828)];

  Map<String, dynamic> toJson() =>
      {'b': book, 't': bookTitle, 'p': page, 'c': color, 'n': note, 'at': at.millisecondsSinceEpoch};
  factory BookMark.fromJson(Map<String, dynamic> j) => BookMark('${j['b']}', '${j['t'] ?? ''}', (j['p'] as num).toInt(),
      (j['c'] as num?)?.toInt() ?? 0, '${j['n'] ?? ''}', DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()));
}

/// Everything the reader keeps on the phone: bookmarks and notes, reading
/// time, pages read each day and when each book was last opened.
class ReaderStore {
  static Future<List<BookMark>> marks() async {
    final p = await SharedPreferences.getInstance();
    try {
      return [
        for (final m in jsonDecode(p.getString('reader_marks') ?? '[]') as List)
          BookMark.fromJson(m as Map<String, dynamic>)
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveMarks(List<BookMark> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('reader_marks', jsonEncode([for (final m in l) m.toJson()]));
  }

  static String today() {
    final d = DateTime.now();
    return '${d.year}-${d.month}-${d.day}';
  }

  static Future<void> addTime(String book, int seconds) async {
    if (seconds <= 0) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt('reader_time_$book', (p.getInt('reader_time_$book') ?? 0) + seconds);
    await p.setInt('reader_time_all', (p.getInt('reader_time_all') ?? 0) + seconds);
  }

  static Future<void> pageSeen(String book, int page) async {
    final p = await SharedPreferences.getInstance();
    final key = 'reader_day_${today()}';
    final seen = p.getStringList(key) ?? [];
    final id = '$book:$page';
    if (!seen.contains(id)) await p.setStringList(key, [...seen, id]);
  }

  static Future<void> opened(String book) async {
    final p = await SharedPreferences.getInstance();
    final m = jsonDecode(p.getString('reader_history') ?? '{}') as Map<String, dynamic>;
    m[book] = DateTime.now().millisecondsSinceEpoch;
    await p.setString('reader_history', jsonEncode(m));
  }

  static Future<Map<String, DateTime>> history() async {
    final p = await SharedPreferences.getInstance();
    final m = jsonDecode(p.getString('reader_history') ?? '{}') as Map<String, dynamic>;
    return {for (final e in m.entries) e.key: DateTime.fromMillisecondsSinceEpoch((e.value as num).toInt())};
  }

  static Future<(int, int, int)> stats() async {
    final p = await SharedPreferences.getInstance();
    final todayPages = (p.getStringList('reader_day_${ReaderStore.today()}') ?? const []).length;
    final all = p.getInt('reader_time_all') ?? 0;
    // Days in a row with at least one page read.
    var streak = 0;
    var d = DateTime.now();
    while (true) {
      final k = 'reader_day_${d.year}-${d.month}-${d.day}';
      if ((p.getStringList(k) ?? const []).isEmpty) break;
      streak++;
      d = d.subtract(const Duration(days: 1));
    }
    return (todayPages, all, streak);
  }
}

enum _Paper { white, sepia, night }

/// Reads a book inside the app: downloads it once (then works offline),
/// remembers the last page, and has the reader's tools.
class BookReaderScreen extends StatefulWidget {
  final Book book;
  final int? startPage;
  const BookReaderScreen({super.key, required this.book, this.startPage});

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  File? _file;
  double _progress = 0;
  String? _error;
  int _page = 1;
  int _pages = 0;
  final _controller = PdfViewerController();
  late final PdfTextSearcher _searcher = PdfTextSearcher(_controller)..addListener(_onSearch);
  PdfDocument? _doc;
  final _shotKey = GlobalKey();
  final _clock = Stopwatch();

  _Paper _paper = _Paper.white;
  double _dim = 0; // 0..0.7 darkening, like lowering the brightness
  bool _focus = false;
  bool _awake = true;
  bool _searching = false;
  Timer? _auto;
  int _autoSeconds = 30;
  List<BookMark> _marks = [];

  String get _pageKey => 'book_page_${widget.book.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Repository.instance.setLastBook(widget.book.id));
    ReaderStore.opened(widget.book.id);
    _clock.start();
    _load();
  }

  @override
  void dispose() {
    _auto?.cancel();
    _searcher.removeListener(_onSearch);
    _searcher.dispose();
    ReaderStore.addTime(widget.book.id, _clock.elapsed.inSeconds);
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final prefs = await SharedPreferences.getInstance();
      _page = widget.startPage ?? prefs.getInt(_pageKey) ?? 1;
      _paper = _Paper.values[(prefs.getInt('reader_paper') ?? 0).clamp(0, 2)];
      _dim = prefs.getDouble('reader_dim') ?? 0;
      _awake = prefs.getBool('reader_awake') ?? true;
      _autoSeconds = prefs.getInt('reader_auto') ?? 30;
      _marks = await ReaderStore.marks();
      if (_awake) {
        try {
          await WakelockPlus.enable();
        } catch (_) {}
      }
      final cached = await BooksStore.cachedFile(widget.book);
      final f = cached ??
          await BooksStore.download(widget.book, (p) {
            if (mounted) setState(() => _progress = p);
          });
      if (mounted) setState(() => _file = f);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر تحميل الكتاب، تأكد من الاتصال بالإنترنت');
    }
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('reader_paper', _paper.index);
    await p.setDouble('reader_dim', _dim);
    await p.setBool('reader_awake', _awake);
    await p.setInt('reader_auto', _autoSeconds);
  }

  void _go(int page) {
    if (_pages > 0) page = page.clamp(1, _pages);
    _controller.goToPage(pageNumber: page);
  }

  List<BookMark> get _mine => _marks.where((m) => m.book == widget.book.id).toList()
    ..sort((a, b) => a.page.compareTo(b.page));

  // ------------------------------------------------------------ auto turn
  void _toggleAuto() {
    if (_auto != null) {
      _auto!.cancel();
      setState(() => _auto = null);
      return;
    }
    _startAuto();
  }

  void _startAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(Duration(seconds: _autoSeconds), (_) {
      if (_pages > 0 && _page >= _pages) {
        _auto?.cancel();
        if (mounted) setState(() => _auto = null);
        return;
      }
      _go(_page + 1);
    });
    setState(() {});
  }

  void _speed(int delta) {
    setState(() => _autoSeconds = (_autoSeconds + delta).clamp(5, 180));
    _savePrefs();
    if (_auto != null) _startAuto();
  }

  // ------------------------------------------------------------ marks
  Future<void> _addMark() async {
    var color = 0;
    final note = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('علامة على صفحة $_page',
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: BookMark.colors[i], radius: 7),
                  label: Text(BookMark.names[i]),
                  selected: color == i,
                  onSelected: (_) => set(() => color = i),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'ملاحظتك على هذه الصفحة (اختياري)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () => Navigator.pop(c, true),
                child: const Text('حفظ')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    _marks.add(BookMark(widget.book.id, widget.book.title, _page, color, note.text.trim(), DateTime.now()));
    await ReaderStore.saveMarks(_marks);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF2E7D32), duration: Duration(seconds: 1), content: Text('تم الحفظ')));
    }
  }

  Future<void> _showMarks() async {
    var filter = -1;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(builder: (c, set) {
        final l = _mine.where((m) => filter == -1 || m.color == filter).toList();
        return SizedBox(
          height: MediaQuery.of(c).size.height * .7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: Row(children: [
                const Expanded(
                    child: Text('علاماتي في هذا الكتاب',
                        style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17))),
                if (_mine.isNotEmpty)
                  IconButton(
                    tooltip: 'مشاركة الملاحظات',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => Share.share(_notesText(_mine)),
                  ),
              ]),
            ),
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('الكل'), selected: filter == -1, onSelected: (_) => set(() => filter = -1)),
              for (var i = 0; i < 3; i++)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: BookMark.colors[i], radius: 6),
                  label: Text(BookMark.names[i]),
                  selected: filter == i,
                  onSelected: (_) => set(() => filter = i),
                ),
            ]),
            Expanded(
              child: l.isEmpty
                  ? const Center(child: Text('لا علامات بعد. اضغط زر العلامة لتضيف.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: l.length,
                      itemBuilder: (c2, i) => ListTile(
                        leading: CircleAvatar(
                            backgroundColor: BookMark.colors[l[i].color],
                            child: Text('${l[i].page}', style: const TextStyle(color: Colors.white, fontSize: 12))),
                        title: Text(l[i].note.isEmpty ? 'صفحة ${l[i].page}' : l[i].note,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${BookMark.names[l[i].color]} · ${l[i].at.year}/${l[i].at.month}/${l[i].at.day} ${l[i].at.hour}:${l[i].at.minute.toString().padLeft(2, '0')}'),
                        onTap: () {
                          Navigator.pop(c);
                          _go(l[i].page);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            _marks.remove(l[i]);
                            await ReaderStore.saveMarks(_marks);
                            set(() {});
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ),
            ),
          ]),
        );
      }),
    );
  }

  String _notesText(List<BookMark> l) => [
        'ملاحظاتي من كتاب «${widget.book.title}»',
        for (final m in l) '• ص ${m.page} (${BookMark.names[m.color]})${m.note.isEmpty ? '' : ': ${m.note}'}',
        '',
        'تطبيق ابن الشابرة — https://ibnalshabira.com',
      ].join('\n');

  // ------------------------------------------------------------ index & go
  Future<void> _showIndex() async {
    List<PdfOutlineNode> outline = const [];
    try {
      if (_doc != null) outline = await _doc!.loadOutline();
    } catch (_) {}
    if (!mounted) return;
    final flat = <(String, int, int)>[];
    void walk(List<PdfOutlineNode> l, int depth) {
      for (final n in l) {
        final p = n.dest?.pageNumber;
        if (p != null) flat.add((n.title, p, depth));
        walk(n.children, depth + 1);
      }
    }

    walk(outline, 0);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SizedBox(
        height: MediaQuery.of(c).size.height * .7,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('فهرس الكتاب', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          Expanded(
            child: flat.isEmpty
                ? const Center(
                    child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('هذا الكتاب ليس فيه فهرس جاهز. استعمل «اذهب إلى صفحة» أو البحث.',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  ))
                : ListView.builder(
                    itemCount: flat.length,
                    itemBuilder: (c2, i) => ListTile(
                      contentPadding: EdgeInsetsDirectional.only(start: 16.0 + flat[i].$3 * 18, end: 16),
                      title: Text(flat[i].$1),
                      trailing: Text('${flat[i].$2}', style: const TextStyle(color: kGold)),
                      onTap: () {
                        Navigator.pop(c);
                        _go(flat[i].$2);
                      },
                    ),
                  ),
          ),
        ]),
      ),
    );
  }

  Future<void> _goTo() async {
    final ctrl = TextEditingController();
    final n = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('اذهب إلى صفحة'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: _pages > 0 ? 'من 1 إلى $_pages' : 'رقم الصفحة'),
          onSubmitted: (v) => Navigator.pop(c, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, int.tryParse(ctrl.text.trim())), child: const Text('اذهب')),
        ],
      ),
    );
    if (n != null) _go(n);
  }

  // ------------------------------------------------------------ settings
  Future<void> _settings() async {
    await showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          void both(VoidCallback f) {
            set(f);
            setState(() {});
            _savePrefs();
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('إعدادات القراءة',
                    style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 12),
                SegmentedButton<_Paper>(
                  segments: const [
                    ButtonSegment(value: _Paper.white, label: Text('أبيض'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: _Paper.sepia, label: Text('ورقي'), icon: Icon(Icons.auto_stories_outlined)),
                    ButtonSegment(value: _Paper.night, label: Text('ليلي'), icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {_paper},
                  onSelectionChanged: (s) => both(() => _paper = s.first),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Icon(Icons.brightness_6_outlined),
                  const SizedBox(width: 8),
                  const Text('الإضاءة'),
                  Expanded(
                    child: Slider(
                      value: 0.7 - _dim,
                      min: 0,
                      max: 0.7,
                      onChanged: (v) => both(() => _dim = 0.7 - v),
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('منع إطفاء الشاشة أثناء القراءة'),
                  value: _awake,
                  onChanged: (v) {
                    both(() => _awake = v);
                    try {
                      v ? WakelockPlus.enable() : WakelockPlus.disable();
                    } catch (_) {}
                  },
                ),
                Row(children: [
                  const Icon(Icons.timer_outlined),
                  const SizedBox(width: 8),
                  Expanded(child: Text('التقليب التلقائي: صفحة كل $_autoSeconds ثانية')),
                  IconButton(onPressed: () => both(() => _speed(-5)), icon: const Icon(Icons.remove_circle_outline)),
                  IconButton(onPressed: () => both(() => _speed(5)), icon: const Icon(Icons.add_circle_outline)),
                ]),
                const Text('للتكبير: باعد بإصبعين على الصفحة. وأدِر الجوال بالعرض لصفحة أعرض.',
                    style: TextStyle(color: Colors.grey, fontSize: 12.5)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _sharePage() async {
    try {
      final b = _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 2.5);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      await Share.shareXFiles(
          [XFile.fromData(data!.buffer.asUint8List(), mimeType: 'image/png', name: 'page-$_page.png')],
          text: '«${widget.book.title}» — صفحة $_page\nتطبيق ابن الشابرة: https://ibnalshabira.com',
          fileNameOverrides: ['page-$_page.png']);
    } catch (_) {}
  }

  ColorFilter? get _filter => switch (_paper) {
        _Paper.white => null,
        _Paper.sepia => const ColorFilter.matrix([
            0.393, 0.769, 0.189, 0, 0, //
            0.349, 0.686, 0.168, 0, 0, //
            0.272, 0.534, 0.131, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
        _Paper.night => const ColorFilter.matrix([
            -0.85, 0, 0, 0, 230, //
            0, -0.85, 0, 0, 225, //
            0, 0, -0.85, 0, 215, //
            0, 0, 0, 1, 0,
          ]),
      };

  Color get _bg => switch (_paper) {
        _Paper.white => const Color(0xFFEDEDED),
        _Paper.sepia => const Color(0xFFE9DCC3),
        _Paper.night => const Color(0xFF151515),
      };

  // ------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    final marked = _mine.where((m) => m.page == _page).toList();
    return Scaffold(
      appBar: _focus
          ? null
          : AppBar(
              title: _searching
                  ? TextField(
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'ابحث في الكتاب', border: InputBorder.none),
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) _searcher.startTextSearch(v.trim(), caseInsensitive: true);
                      },
                    )
                  : Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: _file == null
                  ? null
                  : [
                      IconButton(
                        tooltip: _searching ? 'إغلاق البحث' : 'بحث في الكتاب',
                        icon: Icon(_searching ? Icons.close : Icons.search),
                        onPressed: () => setState(() {
                          _searching = !_searching;
                          if (!_searching) _searcher.resetTextSearch();
                        }),
                      ),
                      IconButton(tooltip: 'العلامات والملاحظات', icon: const Icon(Icons.bookmarks_outlined), onPressed: _showMarks),
                      IconButton(tooltip: 'إعدادات القراءة', icon: const Icon(Icons.tune), onPressed: _settings),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          switch (v) {
                            case 'index':
                              _showIndex();
                            case 'go':
                              _goTo();
                            case 'focus':
                              setState(() => _focus = true);
                            case 'img':
                              _sharePage();
                            case 'file':
                              Share.shareXFiles(
                                  [XFile(_file!.path, name: '${widget.book.title}.pdf', mimeType: 'application/pdf')]);
                            case 'notes':
                              Navigator.of(context)
                                  .push(MaterialPageRoute(builder: (_) => const ReaderNotebookScreen()));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'index', child: Text('فهرس الكتاب')),
                          PopupMenuItem(value: 'go', child: Text('اذهب إلى صفحة')),
                          PopupMenuItem(value: 'focus', child: Text('وضع التركيز')),
                          PopupMenuItem(value: 'img', child: Text('شارك الصفحة صورةً')),
                          PopupMenuItem(value: 'notes', child: Text('دفتر ملاحظاتي (كل الكتب)')),
                          PopupMenuItem(value: 'file', child: Text('حفظ الكتاب في الجوال')),
                        ],
                      ),
                    ],
            ),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 56, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ],
              ),
            )
          : _file == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book, size: 64, color: kGold),
                        const SizedBox(height: 16),
                        Text(widget.book.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        LinearProgressIndicator(value: _progress > 0 ? _progress : null, color: kGold),
                        const SizedBox(height: 8),
                        Text(_progress > 0
                            ? 'جارٍ تجهيز الكتاب… ${(_progress * 100).round()}٪'
                            : 'جارٍ تجهيز الكتاب…'),
                        const SizedBox(height: 6),
                        const Text('يُحمَّل مرة واحدة، ثم يُقرأ دون إنترنت',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  top: _focus,
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        key: _shotKey,
                        child: ColorFiltered(
                          colorFilter: _filter ?? const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                          child: PdfViewer.file(
                            _file!.path,
                            controller: _controller,
                            initialPageNumber: _page,
                            params: PdfViewerParams(
                              backgroundColor: _paper == _Paper.night ? const Color(0xFFEAEAEA) : _bg,
                              pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
                              onViewerReady: (document, controller) {
                                _doc = document;
                                if (mounted) setState(() => _pages = document.pages.length);
                                SharedPreferences.getInstance().then(
                                    (p) => p.setInt('book_pages_${widget.book.id}', document.pages.length));
                              },
                              onPageChanged: (page) {
                                if (page == null) return;
                                setState(() => _page = page);
                                SharedPreferences.getInstance().then((p) => p.setInt(_pageKey, page));
                                ReaderStore.pageSeen(widget.book.id, page);
                              },
                            ),
                          ),
                        ),
                      ),
                      if (_dim > 0)
                        IgnorePointer(child: Container(color: Colors.black.withValues(alpha: _dim))),
                      if (_pages > 0)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: _page / _pages,
                            minHeight: 3,
                            color: kGold,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      if (_searching && _searcher.matches.isNotEmpty)
                        Positioned(
                          top: 8,
                          left: 12,
                          right: 12,
                          child: Material(
                            color: Colors.black.withValues(alpha: .75),
                            borderRadius: BorderRadius.circular(20),
                            child: Row(children: [
                              IconButton(
                                  color: Colors.white,
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                  onPressed: () => _searcher.goToPrevMatch()),
                              Expanded(
                                child: Text(
                                    '${(_searcher.currentIndex ?? 0) + 1} من ${_searcher.matches.length}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white)),
                              ),
                              IconButton(
                                  color: Colors.white,
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                  onPressed: () => _searcher.goToNextMatch()),
                            ]),
                          ),
                        ),
                      if (_pages > 0)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: _focus
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text('$_page / $_pages', style: const TextStyle(color: Colors.white)),
                                      ),
                                      IconButton(
                                        tooltip: 'إظهار الأزرار',
                                        color: Colors.white,
                                        icon: const Icon(Icons.fullscreen_exit),
                                        onPressed: () => setState(() => _focus = false),
                                      ),
                                    ])
                                  : Row(mainAxisSize: MainAxisSize.min, children: [
                                      IconButton(
                                        tooltip: 'علامة على هذه الصفحة',
                                        color: marked.isEmpty ? Colors.white : BookMark.colors[marked.last.color],
                                        icon: Icon(marked.isEmpty ? Icons.bookmark_add_outlined : Icons.bookmark),
                                        onPressed: _addMark,
                                      ),
                                      InkWell(
                                        onTap: _goTo,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                          child: Text('صفحة $_page من $_pages',
                                              style: const TextStyle(color: Colors.white)),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: _auto == null ? 'التقليب التلقائي' : 'إيقاف التقليب',
                                        color: _auto == null ? Colors.white : kGold,
                                        icon: Icon(_auto == null ? Icons.play_circle_outline : Icons.pause_circle_outline),
                                        onPressed: _toggleAuto,
                                      ),
                                      if (_auto != null) ...[
                                        IconButton(
                                            tooltip: 'أبطأ',
                                            color: Colors.white,
                                            icon: const Icon(Icons.remove, size: 18),
                                            onPressed: () => _speed(5)),
                                        Text('$_autoSeconds ث', style: const TextStyle(color: kGold, fontSize: 12)),
                                        IconButton(
                                            tooltip: 'أسرع',
                                            color: Colors.white,
                                            icon: const Icon(Icons.add, size: 18),
                                            onPressed: () => _speed(-5)),
                                      ],
                                    ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

/// «دفتر ملاحظاتي»: every bookmark and note from all books in one place.
class ReaderNotebookScreen extends StatefulWidget {
  const ReaderNotebookScreen({super.key});

  @override
  State<ReaderNotebookScreen> createState() => _ReaderNotebookScreenState();
}

class _ReaderNotebookScreenState extends State<ReaderNotebookScreen> {
  List<BookMark> _all = [];
  int _filter = -1;
  (int, int, int)? _stats;

  @override
  void initState() {
    super.initState();
    ReaderStore.marks().then((l) {
      if (mounted) setState(() => _all = l..sort((a, b) => b.at.compareTo(a.at)));
    });
    ReaderStore.stats().then((s) {
      if (mounted) setState(() => _stats = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = _all.where((m) => _filter == -1 || m.color == _filter).toList();
    final books = Repository.instance.books;
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر ملاحظاتي'),
        actions: [
          if (l.isNotEmpty)
            IconButton(
              tooltip: 'مشاركة',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => Share.share([
                'ملاحظاتي من كتب الشيخ',
                for (final m in l)
                  '• «${m.bookTitle}» ص ${m.page} (${BookMark.names[m.color]})${m.note.isEmpty ? '' : ': ${m.note}'}',
                '',
                'تطبيق ابن الشابرة — https://ibnalshabira.com',
              ].join('\n')),
            ),
        ],
      ),
      body: ListView(children: [
        if (_stats != null)
          Card(
            margin: const EdgeInsets.all(12),
            color: brandColor(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                for (final s in [
                  ('${_stats!.$1}', 'صفحة اليوم'),
                  ('${_stats!.$2 ~/ 60}', 'دقيقة قراءة'),
                  ('${_stats!.$3}', 'أيام متتالية'),
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
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 6, children: [
            ChoiceChip(label: const Text('الكل'), selected: _filter == -1, onSelected: (_) => setState(() => _filter = -1)),
            for (var i = 0; i < 3; i++)
              ChoiceChip(
                avatar: CircleAvatar(backgroundColor: BookMark.colors[i], radius: 6),
                label: Text(BookMark.names[i]),
                selected: _filter == i,
                onSelected: (_) => setState(() => _filter = i),
              ),
          ]),
        ),
        if (l.isEmpty)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Text('لا ملاحظات بعد. ضع علامة على أي صفحة وأنت تقرأ.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ),
        for (final m in l)
          ListTile(
            leading: CircleAvatar(
                backgroundColor: BookMark.colors[m.color],
                child: Text('${m.page}', style: const TextStyle(color: Colors.white, fontSize: 12))),
            title: Text(m.note.isEmpty ? 'صفحة ${m.page}' : m.note, maxLines: 3, overflow: TextOverflow.ellipsis),
            subtitle: Text('«${m.bookTitle}» · ${BookMark.names[m.color]}'),
            onTap: () {
              final b = books.where((x) => x.id == m.book).firstOrNull;
              if (b != null) {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => BookReaderScreen(book: b, startPage: m.page)));
              }
            },
          ),
      ]),
    );
  }
}
