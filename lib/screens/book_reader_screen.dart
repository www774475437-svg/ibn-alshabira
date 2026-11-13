import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/books_store.dart';
import '../theme.dart';

/// Reads a book inside the app: downloads it once (then works offline),
/// remembers the last page, and can save it to the phone.
class BookReaderScreen extends StatefulWidget {
  final Book book;
  const BookReaderScreen({super.key, required this.book});

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

  String get _pageKey => 'book_page_${widget.book.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => Repository.instance.setLastBook(widget.book.id));
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final prefs = await SharedPreferences.getInstance();
      _page = prefs.getInt(_pageKey) ?? 1;
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

  Future<void> _savePage(int page) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt(_pageKey, page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_file != null)
            IconButton(
              tooltip: 'حفظ في الجوال أو مشاركة',
              icon: const Icon(Icons.save_alt),
              onPressed: () => Share.shareXFiles(
                [XFile(_file!.path, name: '${widget.book.title}.pdf', mimeType: 'application/pdf')],
              ),
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
              : Stack(
                  children: [
                    PdfViewer.file(
                      _file!.path,
                      controller: _controller,
                      initialPageNumber: _page,
                      params: PdfViewerParams(
                        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                        onViewerReady: (document, controller) {
                          if (mounted) setState(() => _pages = document.pages.length);
                          SharedPreferences.getInstance().then(
                              (p) => p.setInt('book_pages_${widget.book.id}', document.pages.length));
                        },
                        onPageChanged: (page) {
                          if (page == null) return;
                          setState(() => _page = page);
                          _savePage(page);
                        },
                      ),
                    ),
                    if (_pages > 0)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('صفحة $_page من $_pages',
                                style: const TextStyle(color: Colors.white)),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}
