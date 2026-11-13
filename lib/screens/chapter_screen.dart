import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../widgets/common.dart';

class ChapterScreen extends StatefulWidget {
  final Chapter chapter;
  const ChapterScreen({super.key, required this.chapter});

  @override
  State<ChapterScreen> createState() => _ChapterScreenState();
}

class _ChapterScreenState extends State<ChapterScreen> {
  String _filter = 'all'; // all | fatwa | article | letter
  String _sort = 'new'; // new | old | alpha
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text('باب ${widget.chapter.name}'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'الترتيب',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('الأحدث أولاً')),
              PopupMenuItem(value: 'old', child: Text('الأقدم أولاً')),
              PopupMenuItem(value: 'alpha', child: Text('ترتيب أبجدي')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final all = repo.byChapter(widget.chapter.id);
          final read = repo.everRead;
          final readCount = all.where((f) => read.contains(f.id)).length;
          var items = _filter == 'all' ? all : all.where((f) => f.type == _filter).toList();
          if (_unreadOnly) items = items.where((f) => !read.contains(f.id)).toList();
          if (_sort == 'new') {
            items = items.reversed.toList();
          } else if (_sort == 'alpha') {
            items = [...items]..sort((a, b) => normalizeArabic(a.title).compareTo(normalizeArabic(b.title)));
          }
          return Column(
            children: [
              if (all.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('قرأت $readCount من ${all.length}',
                                style: const TextStyle(fontSize: 13, color: Colors.grey)),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                  value: readCount / all.length, minHeight: 7),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilterChip(
                        label: const Text('ما لم أقرأه'),
                        selected: _unreadOnly,
                        onSelected: (v) => setState(() => _unreadOnly = v),
                      ),
                    ],
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    for (final (key, label) in const [
                      ('all', 'الكل'),
                      ('fatwa', 'أجوبة'),
                      ('article', 'مقالات'),
                      ('letter', 'رسائل'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _filter == key,
                          onSelected: (_) => setState(() => _filter = key),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? EmptyState(
                        icon: _unreadOnly && all.isNotEmpty ? Icons.task_alt : Icons.hourglass_empty,
                        text: _unreadOnly && all.isNotEmpty
                            ? 'قرأت كل ما في هذا الباب، بارك الله فيك.'
                            : 'لا توجد مواد في هذا الباب بعد،\nوستُضاف قريباً بإذن الله.')
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) => FatwaTile(fatwa: items[i], showChapter: false),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
