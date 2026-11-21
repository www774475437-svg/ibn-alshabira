import 'package:flutter/material.dart';

import '../data/hijri.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'audio_library.dart';

/// «آخر ما نُشر» on one page: the newest at the top, then the one before it,
/// answers, articles and recordings together.
class LatestScreen extends StatelessWidget {
  final List<Recording> recordings;
  const LatestScreen({super.key, required this.recordings});

  /// yyyy-MM-dd (or any text that starts with it) for sorting; '' when unknown.
  static String _key(String d) {
    final m = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(d);
    return m?.group(0) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final items = <(String, Object)>[
      for (final f in repo.latest(limit: 300)) (_key(f.date), f),
      for (final r in recordings) (_key(r.date), r),
    ];
    // Newest first; an item without a date keeps its place after the dated ones.
    items.sort((a, b) => b.$1.compareTo(a.$1));
    return Scaffold(
      appBar: AppBar(title: const Text('آخر ما نُشر')),
      body: items.isEmpty
          ? const EmptyState(icon: Icons.campaign_outlined, text: 'لا جديد الآن')
          : ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 24),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final it = items[i].$2;
                if (it is Fatwa) return FatwaTile(fatwa: it);
                final r = it as Recording;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: Pal.soft(context),
                      child: Icon(Icons.graphic_eq_rounded, color: Pal.accent(context)),
                    ),
                    title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      'تسجيل صوتي',
                      if (r.dur.isNotEmpty) r.dur,
                      if (r.date.isNotEmpty) Hijri.parse(r.date) ?? r.date,
                    ].join('  ·  ')),
                    onTap: () => openRecording(context, r, list: recordings),
                  ),
                );
              },
            ),
    );
  }
}
