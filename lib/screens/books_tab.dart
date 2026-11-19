import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/books_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'book_reader_screen.dart';
import 'reading_plan.dart';

/// The sheikh's books (from his Google Drive folder). Inside the app a book
/// is downloaded and read here, without showing any outside link.
class BooksTab extends StatefulWidget {
  const BooksTab({super.key});

  @override
  State<BooksTab> createState() => _BooksTabState();
}

class _BooksTabState extends State<BooksTab> {
  String _filter = '';

  @override
  void initState() {
    super.initState();
    // Pick up books the sheikh added to Drive after this build.
    BooksStore.refreshFromDrive().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _open(Book b) {
    if (kIsWeb) {
      openUrl(context, b.previewUrl);
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BookReaderScreen(book: b)))
        .then((_) => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final all = Repository.instance.books;
    final q = normalizeArabic(_filter);
    final books = q.isEmpty ? all : all.where((b) => normalizeArabic(b.title).contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('كتب الشيخ (${all.length})'),
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: 'دفتر ملاحظاتي',
              icon: const Icon(Icons.edit_note),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReaderNotebookScreen())),
            ),
        ],
      ),
      body: all.isEmpty
          ? const EmptyState(icon: Icons.menu_book_outlined, text: 'ستُضاف كتب الشيخ هنا قريباً بإذن الله.')
          : CustomScrollView(
              slivers: [
                if (!kIsWeb)
                  SliverToBoxAdapter(
                    child: ReadingPlanCard(onOpen: _open, onChanged: () => setState(() {})),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: TextField(
                      onChanged: (v) => setState(() => _filter = v),
                      decoration: InputDecoration(
                        hintText: 'ابحث في عناوين الكتب',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: books.length,
                    itemBuilder: (context, i) => _BookCard(book: books[i], onTap: () => _open(books[i])),
                  ),
                ),
              ],
            ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  const _BookCard({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: kIsWeb ? Future.value(null) : BooksStore.cachedFile(book),
      builder: (context, snap) {
        final saved = snap.data != null;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF1F5E3B), Color(0xFF0A2417)],
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // spine
                      PositionedDirectional(
                        top: 0,
                        bottom: 0,
                        start: 10,
                        child: Container(width: 3, color: kGold.withValues(alpha: 0.6)),
                      ),
                      Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(22, 16, 12, 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.menu_book, color: kGold, size: 28),
                            const SizedBox(height: 10),
                            Text(
                              book.title,
                              textAlign: TextAlign.center,
                              maxLines: 5,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, height: 1.5),
                            ),
                          ],
                        ),
                      ),
                      if (saved)
                        const PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: Icon(Icons.download_done, color: kGold, size: 20),
                        ),
                    ],
                  ),
                                ),
              ),
              if (!kIsWeb) _BookProgress(bookId: book.id),
            ],
          ),
        );
      },
    );
  }
}

/// «قرأت 40%» under a book, and «بقي لك 12 صفحة لتختم الكتاب» near the end.
class _BookProgress extends StatelessWidget {
  final String bookId;
  const _BookProgress({required this.bookId});

  static SharedPreferences? _p;

  @override
  Widget build(BuildContext context) => FutureBuilder<SharedPreferences>(
        future: _p != null ? Future.value(_p) : SharedPreferences.getInstance().then((p) => _p = p),
        builder: (context, snap) {
          final p = snap.data;
          if (p == null) return const SizedBox(height: 4);
          final pages = p.getInt('book_pages_$bookId') ?? 0;
          final page = p.getInt('book_page_$bookId') ?? 0;
          if (pages <= 0 || page <= 1) return const SizedBox(height: 4);
          final pct = (page / pages).clamp(0.0, 1.0);
          final left = pages - page;
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 5,
                  color: kGold,
                  backgroundColor: kGold.withValues(alpha: 0.18),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                left <= 0
                    ? 'ختمتَ الكتاب ✓'
                    : left <= 20
                        ? 'بقي لك $left صفحة لتختمه'
                        : 'قرأت ${(pct * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: left <= 20 ? kGoldChip : Colors.grey),
              ),
            ]),
          );
        },
      );
}
