import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Posts from the sheikh's Telegram channel, word for word, with search.
class ChannelScreen extends StatefulWidget {
  const ChannelScreen({super.key});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final items = _q.trim().isEmpty ? repo.channel : repo.searchChannel(_q);
    return Scaffold(
      appBar: AppBar(title: Text('من قناة الشيخ (${repo.channel.length})')),
      body: repo.channel.isEmpty
          ? const EmptyState(
              icon: Icons.campaign_outlined,
              text: 'تظهر هنا منشورات قناة الشيخ على تيليجرام بعد التحديث القادم بإذن الله.')
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      hintText: 'ابحث في منشورات القناة',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      isDense: true,
                    ),
                  ),
                ),
                if (_q.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${items.length} نتيجة', style: const TextStyle(color: Colors.grey)),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _PostCard(post: items[i]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final ChannelPost post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ChannelPostScreen(post: post))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_outlined, color: kGold, size: 18),
                  const SizedBox(width: 6),
                  Text(post.date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              Text(post.text, maxLines: 6, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.8)),
              const SizedBox(height: 4),
              const Text('اقرأ المزيد', style: TextStyle(color: kGoldChip, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class ChannelPostScreen extends StatelessWidget {
  final ChannelPost post;
  const ChannelPostScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(post.date),
        actions: [
          IconButton(
            tooltip: 'نسخ',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: post.text));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخ النص')));
            },
          ),
          IconButton(
            tooltip: 'مشاركة',
            icon: const Icon(Icons.share),
            onPressed: () => Share.share('${post.text}\n\n${post.link}'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SelectableText(post.text, style: const TextStyle(fontSize: 18, height: 2)),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: const Text('فتح المنشور في تيليجرام'),
            onPressed: () => openUrl(context, post.link),
          ),
          if (cloud.ready && cloud.isAdmin) ...[
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.drafts_outlined),
              label: const Text('حوّله إلى مسودة جواب'),
              onPressed: () async {
                final repo = Repository.instance;
                final err = await cloud.saveDraft(
                  null,
                  chapter: repo.chapters.last.id,
                  title: post.firstLine,
                  question: '',
                  answer: post.text,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(err ?? 'حُفظ في المسودات ✅ اختر بابه وراجعه ثم انشره من «الإدارة ← نشر»')));
              },
            ),
          ],
        ],
      ),
    );
  }
}
