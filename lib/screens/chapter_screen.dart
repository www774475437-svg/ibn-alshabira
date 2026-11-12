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

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: Text('باب ${widget.chapter.name}')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final all = repo.byChapter(widget.chapter.id);
          final items = _filter == 'all' ? all : all.where((f) => f.type == _filter).toList();
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    for (final (key, label) in const [
                      ('all', 'الكل'),
                      ('fatwa', 'فتاوى'),
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
                    ? const EmptyState(
                        icon: Icons.hourglass_empty,
                        text: 'لا توجد مواد في هذا الباب بعد،\nوستُضاف قريباً بإذن الله.')
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
