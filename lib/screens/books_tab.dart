import 'dart:io' show File;
import 'dart:math' as math;

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
import 'recommended_books.dart';

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
                const SliverToBoxAdapter(child: _RecommendedBanner()),
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


/// The banner at the top of the books tab that opens «كتب ينصح بها الشيخ»:
/// a deep night-teal panel with a gold frame, a starry pattern, a lamp glow
/// and a shelf of book spines.
class _RecommendedBanner extends StatelessWidget {
  const _RecommendedBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const RecommendedBooksScreen())),
          child: Ink(
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF0B3A40), Color(0xFF0F4E55), Color(0xFF082A2F)],
                stops: [0, .55, 1],
              ),
              border: Border.all(color: const Color(0xFFC9A253), width: 1.2),
              boxShadow: const [BoxShadow(color: Color(0x40082A2F), blurRadius: 16, offset: Offset(0, 6))],
            ),
            child: Stack(children: [
              const Positioned.fill(child: CustomPaint(painter: _BannerArt())),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x33C9A253),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0x99C9A253)),
                      ),
                      child: const Text('لطالب العلم',
                          style: TextStyle(color: Color(0xFFF1D592), fontSize: 11.5, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 10),
                    const Text('كتب ينصح بها الشيخ',
                        style: TextStyle(
                          color: Color(0xFFF7E7BE),
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          shadows: [Shadow(color: Color(0x88000000), blurRadius: 6, offset: Offset(0, 2))],
                        )),
                    const SizedBox(height: 4),
                    const Text('مختارات يوصي بقراءتها مع نبذة عن كل كتاب',
                        style: TextStyle(color: Color(0xCCE6F0EE), fontSize: 12.5)),
                    const Spacer(),
                    Row(children: const [
                      Text('تصفّح القائمة',
                          style: TextStyle(color: Color(0xFFF1D592), fontSize: 13, fontWeight: FontWeight.w700)),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_back_rounded, size: 18, color: Color(0xFFF1D592)),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BannerArt extends CustomPainter {
  const _BannerArt();

  @override
  void paint(Canvas canvas, Size size) {
    // The art sits on the left (the end in Arabic), the text on the right.
    final h = size.height;
    double x(double v) => v - 10;

    // Lamp glow.
    final glow = Paint()
      ..shader = RadialGradient(colors: const [Color(0x55F1D592), Color(0x00F1D592)])
          .createShader(Rect.fromCircle(center: Offset(x(70), h * .38), radius: 110));
    canvas.drawCircle(Offset(x(70), h * .38), 110, glow);

    // Eight-point stars scattered lightly.
    final star = Paint()..color = const Color(0x2EF1D592);
    void drawStar(Offset c, double r) {
      final p = Path();
      for (var i = 0; i < 16; i++) {
        final a = i * 3.14159265 / 8;
        final rr = i.isEven ? r : r * .45;
        final o = c + Offset(rr * _cos(a), rr * _sin(a));
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(p..close(), star);
    }

    for (final s in const [(30.0, 22.0, 6.0), (120.0, 18.0, 4.0), (150.0, 40.0, 4.0), (60.0, 30.0, 3.5), (95.0, 60.0, 3.0)]) {
      drawStar(Offset(x(s.$1), s.$2), s.$3);
    }

    // Shelf.
    final shelfY = h - 26;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(x(18), shelfY, x(170), shelfY + 5),
            const Radius.circular(2)),
        Paint()..color = const Color(0xFFB8863B));

    // Book spines standing on the shelf.
    const books = [
      (24.0, 16.0, 62.0, Color(0xFF8C2F2B)),
      (42.0, 14.0, 74.0, Color(0xFFE9DDBF)),
      (58.0, 18.0, 56.0, Color(0xFF1F6A60)),
      (78.0, 13.0, 80.0, Color(0xFFC9A253)),
      (93.0, 17.0, 66.0, Color(0xFF3E4F86)),
      (112.0, 15.0, 72.0, Color(0xFF6B3E26)),
    ];
    for (final b in books) {
      final rect = Rect.fromLTRB(x(b.$1), shelfY - b.$3, x(b.$1 + b.$2), shelfY);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2.5)), Paint()..color = b.$4);
      final band = Paint()..color = const Color(0xAAF1D592);
      canvas.drawRect(Rect.fromLTWH(rect.left + 2, rect.top + 8, rect.width - 4, 2), band);
      canvas.drawRect(Rect.fromLTWH(rect.left + 2, rect.bottom - 12, rect.width - 4, 2), band);
    }
    // One book leaning on the last.
    canvas.save();
    canvas.translate(x(142), shelfY);
    canvas.rotate(-.32);
    final lean = Rect.fromLTWH(-2, -64, 16, 64);
    canvas.drawRRect(RRect.fromRectAndRadius(lean, const Radius.circular(2.5)), Paint()..color = const Color(0xFF2B5D8A));
    canvas.drawRect(Rect.fromLTWH(lean.left + 2, lean.top + 8, lean.width - 4, 2), Paint()..color = const Color(0xAAF1D592));
    canvas.restore();
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
