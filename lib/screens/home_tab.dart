import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'ask_screen.dart';
import 'chapter_screen.dart';

class HomeTab extends StatelessWidget {
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenMore;

  const HomeTab({super.key, required this.onOpenSearch, required this.onOpenMore});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final latest = repo.fatwas.reversed.take(5).toList();
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header(onOpenSearch: onOpenSearch)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.forum_outlined, color: kGold),
                  title: const Text('اسأل الشيخ', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('أرسل سؤالك ويصلك الجواب'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AskScreen())),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: _SectionTitle('الأبواب')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.95,
              ),
              itemCount: repo.chapters.length,
              itemBuilder: (context, i) {
                final c = repo.chapters[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ChapterScreen(chapter: c)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(chapterIcon(c.icon), size: 32, color: kGold),
                        const SizedBox(height: 8),
                        Text(c.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text('${repo.countInChapter(c.id)}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: _SectionTitle('أحدث ما نُشر')),
          SliverList.builder(
            itemCount: latest.length,
            itemBuilder: (context, i) => FatwaTile(fatwa: latest[i]),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onOpenSearch;
  const _Header({required this.onOpenSearch});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 24),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0E0E0E) : kGreen,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const Text('ابن الشابرة',
              style: TextStyle(color: kGold, fontSize: 30, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('فتاوى ومقالات وكتب الشيخ قائد بن غانم الشابرة',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 18),
          InkWell(
            onTap: onOpenSearch,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kGold.withValues(alpha: 0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.search, color: kGold),
                  SizedBox(width: 10),
                  Text('ابحث عن مسألة… مثل: النمص', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
}
