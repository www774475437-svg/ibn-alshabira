import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';

/// A simple reading plan for one of the sheikh's books: so many pages a
/// day. Kept on the phone only.
class ReadingPlanCard extends StatelessWidget {
  final void Function(Book) onOpen;
  final VoidCallback onChanged;
  const ReadingPlanCard({super.key, required this.onOpen, required this.onChanged});

  Future<Map<String, dynamic>?> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('readingPlan');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final id = '${m['bookId']}';
      m['page'] = prefs.getInt('book_page_$id') ?? 1;
      m['pages'] = prefs.getInt('book_pages_$id') ?? 0;
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<void> _start(BuildContext context) async {
    final books = Repository.instance.books;
    if (books.isEmpty) return;
    var book = books.first;
    var perDay = 10;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('خطة قراءة جديدة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: book.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الكتاب', border: OutlineInputBorder()),
                items: [
                  for (final b in books)
                    DropdownMenuItem(
                        value: b.id, child: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setS(() => book = books.firstWhere((b) => b.id == v, orElse: () => book)),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                value: perDay,
                decoration:
                    const InputDecoration(labelText: 'عدد الصفحات كل يوم', border: OutlineInputBorder()),
                items: [
                  for (final n in const [3, 5, 10, 15, 20, 30])
                    DropdownMenuItem(value: n, child: Text('$n صفحة')),
                ],
                onChanged: (v) => setS(() => perDay = v ?? perDay),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ابدأ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setString(
        'readingPlan',
        jsonEncode({
          'bookId': book.id,
          'perDay': perDay,
          'start': DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
          'startPage': prefs.getInt('book_page_${book.id}') ?? 1,
        }));
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _load(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final plan = snap.data;
        Book? book;
        if (plan != null) {
          for (final b in Repository.instance.books) {
            if (b.id == '${plan['bookId']}') book = b;
          }
        }
        if (plan == null || book == null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              icon: const Icon(Icons.event_note),
              label: const Text('ابدأ خطة قراءة لكتاب'),
              onPressed: () => _start(context),
            ),
          );
        }
        final b = book;
        final perDay = (plan['perDay'] as num).toInt();
        final startPage = (plan['startPage'] as num).toInt();
        final start = DateTime.fromMillisecondsSinceEpoch((plan['start'] as num).toInt());
        final days = DateTime.now().difference(start).inDays;
        final page = plan['page'] as int;
        final pages = plan['pages'] as int;
        var target = startPage + perDay * (days + 1) - 1;
        if (pages > 0 && target > pages) target = pages;
        final finished = pages > 0 && page >= pages;
        final doneToday = page >= target;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_note, color: kGold),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('خطة القراءة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      TextButton(
                        onPressed: () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('readingPlan');
                          onChanged();
                        },
                        child: const Text('إنهاء الخطة'),
                      ),
                    ],
                  ),
                  Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  if (pages > 0) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: (page / pages).clamp(0.0, 1.0), minHeight: 7),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    finished
                        ? 'أتممت الكتاب، بارك الله فيك.'
                        : doneToday
                            ? 'أتممت وِرد اليوم ✅ (أنت في صفحة $page${pages > 0 ? ' من $pages' : ''})'
                            : 'وِرد اليوم: إلى صفحة $target · أنت في صفحة $page${pages > 0 ? ' من $pages' : ''}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.menu_book),
                    label: const Text('متابعة القراءة'),
                    onPressed: () => onOpen(b),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
