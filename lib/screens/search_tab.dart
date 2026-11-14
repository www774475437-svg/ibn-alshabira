import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/voice.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chapter_screen.dart';
import 'trusted_screens.dart';

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
  bool _listening = false;
  bool _byMeaning = false;
  String _type = '';

  Future<void> _voice() async {
    if (_listening) {
      await Listener1.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    final ok = await Listener1.start(
      onText: (t) {
        if (!mounted || t.isEmpty) return;
        _controller.text = t;
        setState(() => _query = t);
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok && mounted) {
      setState(() => _listening = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('البحث الصوتي غير متاح على هذا الجهاز، أو لم يُسمح بالميكروفون')));
    }
  }

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
    // Exact search first. Search by meaning only when the reader asks for it.
    final ranked = repo.searchRanked(_query, type: _type);
    var results = ranked.strong;
    var weak = ranked.weak;
    if (results.isEmpty && weak.isEmpty && _type.isEmpty) {
      results = repo.search(_query); // words the staff linked (e.g. الحواجب → النمص)
    }
    final have = {for (final f in results) f.id, for (final f in weak) f.id};
    final near = !_byMeaning || _query.trim().length < 3
        ? const <Fatwa>[]
        : repo
            .smartSearch(_query)
            .where((f) => !have.contains(f.id) && (_type.isEmpty || f.type == _type))
            .toList();
    // One list: results, then (labelled) passing mentions, then by-meaning.
    final rows = <Object>[
      ...results,
      if (weak.isNotEmpty) 'ذُكرت الكلمة عرضاً في (${weak.length})',
      ...weak,
      if (near.isNotEmpty) 'أقرب كلام الشيخ إلى سؤالك بالمعنى (${near.length})',
      ...near,
    ];
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
              onSubmitted: (v) {
                repo.addRecentSearch(v);
                if (v.trim().length > 1 && repo.search(v).isEmpty) {
                  Cloud.instance.logMiss(v);
                }
              },
              decoration: InputDecoration(
                hintText: 'اكتب سؤالك أو المسألة… مثل: هل يجوز النمص',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _controller.clear();
                          _query = '';
                        }),
                      ),
                    IconButton(
                      tooltip: 'بحث صوتي',
                      icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Colors.red : null),
                      onPressed: _voice,
                    ),
                  ],
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32), foregroundColor: Colors.white),
                icon: const Icon(Icons.manage_search),
                label: const Text('بحث الفتاوى من كتب الثقات بالذكاء الاصطناعي'),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => TrustedFatwaScreen(initial: _query.trim()))),
              ),
            ),
          ),
          if (_query.trim().isNotEmpty) ...[
            _Suggestions(query: _query, onPick: _search),
          ],
          if (_query.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('عدد النتائج: ${results.length}', style: const TextStyle(color: Colors.grey)),
              ),
            ),
          if (_query.trim().isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  for (final (id, label) in const [('', 'الكل'), ('fatwa', 'أجوبة'), ('article', 'مقالات')])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _type == id,
                        onSelected: (_) => setState(() => _type = id),
                      ),
                    ),
                  FilterChip(
                    avatar: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('بحث بالمعنى'),
                    selected: _byMeaning,
                    onSelected: (v) => setState(() => _byMeaning = v),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _query.trim().isEmpty
                ? _EmptySearch(onPick: _search, onIndex: _openIndex)
                : rows.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off,
                        text: 'لا توجد نتائج. جرّب كلمة أخرى، أو فعّل «بحث بالمعنى»، أو أرسل سؤالك من «اسأل الشيخ».')
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          if (row is String) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(row,
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
                            );
                          }
                          return GestureDetector(
                            onTapDown: (_) {
                              repo.addRecentSearch(_query);
                              Cloud.instance.countSearchOpen((row as Fatwa).id);
                            },
                            child: FatwaTile(fatwa: row as Fatwa),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Word suggestions while typing: «النم» → «النمص».
class _Suggestions extends StatelessWidget {
  final String query;
  final ValueChanged<String> onPick;
  const _Suggestions({required this.query, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final words = Repository.instance.suggestions(query, kIndexTopics);
    if (words.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final w in words)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: ActionChip(
                avatar: const Icon(Icons.north_west, size: 16),
                label: Text(w),
                onPressed: () => onPick(w),
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
