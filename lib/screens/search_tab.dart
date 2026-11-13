import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chapter_screen.dart';

/// Common topics shown in «الفهرس» (tap to search).
const kIndexTopics = [
  'التوحيد', 'البدعة', 'الوضوء', 'الصلاة', 'الجمعة', 'الزكاة', 'الصيام', 'الحج',
  'الربا', 'البيع', 'الزواج', 'الطلاق', 'الحجاب', 'النمص', 'اللحية', 'الأغاني',
  'بر الوالدين', 'الغيبة',
];

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    setState(() => _query = q);
    Repository.instance.addRecentSearch(q);
  }

  void _openIndex() {
    final repo = Repository.instance;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const Text('الفهرس',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('الأبواب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final c in repo.chapters)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(chapterIcon(c.icon), color: kGold),
                title: Text(c.name),
                trailing: Text('${repo.countInChapter(c.id)}'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ChapterScreen(chapter: c)),
                  );
                },
              ),
            const SizedBox(height: 16),
            const Text('مسائل يكثر السؤال عنها',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in kIndexTopics)
                  ActionChip(
                    label: Text(t),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _search(t);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final results = repo.search(_query);
    return Scaffold(
      appBar: AppBar(
        title: const Text('البحث'),
        actions: [
          TextButton.icon(
            onPressed: _openIndex,
            icon: const Icon(Icons.list_alt, color: kGold),
            label: const Text('الفهرس', style: TextStyle(color: kGold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: repo.addRecentSearch,
              decoration: InputDecoration(
                hintText: 'اكتب المسألة… مثل: النمص، الوضوء، الربا',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _controller.clear();
                          _query = '';
                        }),
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          if (_query.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('عدد النتائج: ${results.length}',
                    style: const TextStyle(color: Colors.grey)),
              ),
            ),
          Expanded(
            child: _query.trim().isEmpty
                ? _EmptySearch(onPick: _search, onIndex: _openIndex)
                : results.isEmpty
                    ? const EmptyState(icon: Icons.search_off, text: 'لا توجد نتائج لهذه الكلمة')
                    : ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, i) => GestureDetector(
                          onTapDown: (_) => repo.addRecentSearch(_query),
                          child: FatwaTile(fatwa: results[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  final ValueChanged<String> onPick;
  final VoidCallback onIndex;
  const _EmptySearch({required this.onPick, required this.onIndex});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (repo.recentSearches.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.history, size: 20, color: Colors.grey),
                const SizedBox(width: 6),
                const Text('آخر عمليات البحث', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(onPressed: repo.clearRecentSearches, child: const Text('مسح')),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in repo.recentSearches)
                  InputChip(label: Text(q), onPressed: () => onPick(q)),
              ],
            ),
            const SizedBox(height: 24),
          ],
          OutlinedButton.icon(
            onPressed: onIndex,
            icon: const Icon(Icons.list_alt),
            label: const Text('افتح الفهرس: الأبواب والمسائل الشائعة'),
          ),
          const SizedBox(height: 24),
          const EmptyState(
            icon: Icons.manage_search,
            text: 'ابحث في جميع أجوبة الشيخ ومقالاته.\nالبحث لا يتأثر بالتشكيل ولا بالهمزات.',
          ),
        ],
      ),
    );
  }
}
