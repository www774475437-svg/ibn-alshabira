import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// One series of answers (e.g. «أحكام رمضان»).
class SeriesScreen extends StatelessWidget {
  final String seriesId;
  const SeriesScreen({super.key, required this.seriesId});

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([cloud, repo]),
      builder: (context, _) {
        Series? s;
        for (final x in cloud.series) {
          if (x.id == seriesId) s = x;
        }
        if (s == null) {
          return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.info_outline, text: 'السلسلة غير موجودة'));
        }
        final series = s;
        final items = <Fatwa>[
          for (final id in series.ids)
            if (repo.findById(id) case final f?) f,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(series.title),
            actions: [
              if (cloud.isAdmin)
                IconButton(
                  tooltip: 'حذف السلسلة',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await cloud.deleteSeries(series.id);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                ),
            ],
          ),
          body: items.isEmpty
              ? const EmptyState(icon: Icons.collections_bookmark_outlined, text: 'لا توجد أجوبة في هذه السلسلة بعد')
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => Stack(
                    children: [
                      FatwaTile(fatwa: items[i]),
                      if (cloud.isAdmin)
                        PositionedDirectional(
                          end: 16,
                          bottom: 8,
                          child: IconButton(
                            tooltip: 'إزالة من السلسلة',
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                            onPressed: () => cloud.removeFromSeries(series.id, items[i].id),
                          ),
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// The sheikh's latest YouTube videos.
class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final videos = Repository.instance.videos;
    return Scaffold(
      appBar: AppBar(title: const Text('المرئيات')),
      body: videos.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_outline, size: 64, color: kGold),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('فتح قناة الشيخ في يوتيوب'),
                    onPressed: () => openUrl(context, 'https://youtube.com/@qaidghsh'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: videos.length + 1,
              itemBuilder: (context, i) {
                if (i == videos.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('كل المقاطع في قناة الشيخ'),
                      onPressed: () => openUrl(context, 'https://youtube.com/@qaidghsh'),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: VideoCard(video: videos[i]),
                );
              },
            ),
    );
  }
}

class VideoCard extends StatelessWidget {
  final Video video;
  final double? width;
  const VideoCard({super.key, required this.video, this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openUrl(context, video.url),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      video.thumbnail,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: brandColor(context)),
                    ),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// «المشايخ الثقات المعتمدون»: a list the admins fill from inside the app.
class ScholarsScreen extends StatelessWidget {
  const ScholarsScreen({super.key});

  void _add(BuildContext context) {
    final name = TextEditingController();
    final note = TextEditingController();
    final url = TextEditingController();
    InputDecoration deco(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة شيخ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: deco('الاسم')),
              const SizedBox(height: 10),
              TextField(controller: note, maxLines: 2, decoration: deco('نبذة قصيرة (اختياري)')),
              const SizedBox(height: 10),
              TextField(
                  controller: url,
                  textDirection: TextDirection.ltr,
                  decoration: deco('رابط قناته أو موقعه (اختياري)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final err = await Cloud.instance.addScholar(name.text, note.text, url.text);
              if (!ctx.mounted) return;
              if (err == null) {
                Navigator.pop(ctx);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('المشايخ الثقات المعتمدون')),
        floatingActionButton: cloud.isAdmin
            ? FloatingActionButton.extended(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة شيخ'),
              )
            : null,
        body: !cloud.ready
            ? const EmptyState(
                icon: Icons.groups_outlined, text: 'تظهر هذه القائمة عند الاتصال بالإنترنت.')
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: cloud.scholarsStream(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const EmptyState(icon: Icons.error_outline, text: 'تعذّر تحميل القائمة');
                  }
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) {
                    return const EmptyState(
                        icon: Icons.groups_outlined, text: 'ستُضاف القائمة هنا قريباً بإذن الله.');
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final url = '${d['url'] ?? ''}';
                      final note = '${d['note'] ?? ''}';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: kGold.withValues(alpha: 0.2),
                            child: Text('${i + 1}',
                                style: const TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
                          ),
                          title: Text('${d['name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: note.isEmpty ? null : Text(note),
                          trailing: cloud.isAdmin
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () => cloud.deleteScholar(docs[i].id),
                                )
                              : (url.isEmpty ? null : const Icon(Icons.open_in_new)),
                          onTap: url.isEmpty ? null : () => openUrl(context, url),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}
