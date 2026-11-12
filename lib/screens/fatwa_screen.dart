import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

class FatwaScreen extends StatelessWidget {
  final Fatwa fatwa;
  const FatwaScreen({super.key, required this.fatwa});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final fav = repo.isFavorite(fatwa.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(fatwa.typeLabel),
            actions: [
              IconButton(
                tooltip: fav ? 'إزالة من المحفوظات' : 'حفظ',
                icon: Icon(fav ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => repo.toggleFavorite(fatwa.id),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text('باب ${repo.chapterName(fatwa.chapter)}',
                  style: const TextStyle(color: kGoldChip, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SelectableText(fatwa.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.5)),
              const SizedBox(height: 16),
              if (fatwa.question.isNotEmpty) ...[
                _Block(label: 'السؤال', text: fatwa.question, highlight: true),
                const SizedBox(height: 14),
              ],
              _Block(
                label: fatwa.question.isNotEmpty ? 'الجواب' : null,
                text: fatwa.answer,
              ),
              if (fatwa.tags.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final t in fatwa.tags) Chip(label: Text('#$t'))],
                ),
              ],
              if (fatwa.date.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('تاريخ النشر: ${fatwa.date}', style: const TextStyle(color: Colors.grey)),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fatwa.shareText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم النسخ')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة'),
                      onPressed: () => Share.share(fatwa.shareText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('نسخ رابط الفتوى'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: AppConfig.fatwaLink(fatwa.id)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الرابط')),
                  );
                },
              ),
              if (fatwa.source.isNotEmpty) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('عرض المصدر في تليجرام'),
                  onPressed: () => openUrl(context, fatwa.source),
                ),
              ],
              ..._related(context, repo),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _related(BuildContext context, Repository repo) {
    final items = repo.related(fatwa);
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      const Divider(),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('فتاوى ذات صلة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      for (final f in items)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.article_outlined, color: kGold),
            title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('باب ${repo.chapterName(f.chapter)}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => openFatwa(context, f),
          ),
        ),
    ];
  }
}

class _Block extends StatelessWidget {
  final String? label;
  final String text;
  final bool highlight;
  const _Block({this.label, required this.text, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? kGold.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(14),
        border: highlight ? null : Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
          ],
          SelectableText(text, style: const TextStyle(fontSize: 17, height: 1.9)),
        ],
      ),
    );
  }
}
