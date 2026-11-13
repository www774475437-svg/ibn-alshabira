import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

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
        final read = repo.everRead;
        final done = items.where((f) => read.contains(f.id)).length;
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
              ? const EmptyState(icon: Icons.collections_bookmark_outlined, text: 'لا توجد أجوبة هنا بعد')
              : ListView.builder(
                  itemCount: items.length + (series.track ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (series.track && index == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                                done == items.length
                                    ? 'أتممت المسار، بارك الله فيك 🎉'
                                    : 'أنجزت $done من ${items.length} خطوة',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(value: done / items.length, minHeight: 8),
                            ),
                          ],
                        ),
                      );
                    }
                    final i = series.track ? index - 1 : index;
                    return Stack(
                    children: [
                      if (series.track)
                        Row(
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(start: 14),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: read.contains(items[i].id) ? Colors.green : kGold,
                                child: read.contains(items[i].id)
                                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                                    : Text('${i + 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 13)),
                              ),
                            ),
                            Expanded(child: FatwaTile(fatwa: items[i])),
                          ],
                        )
                      else
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
                  );
                  },
                ),
        );
      },
    );
  }
}

/// The sheikh's YouTube videos, played inside the app.
class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  static String? videoIdFrom(String text) {
    final t = text.trim();
    final m = RegExp(r'(?:v=|youtu\.be/|shorts/|embed/|live/)([\w-]{11})').firstMatch(t);
    if (m != null) return m.group(1);
    return RegExp(r'^[\w-]{11}$').hasMatch(t) ? t : null;
  }

  Future<void> _add(BuildContext context) async {
    final link = TextEditingController();
    final title = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مقطع'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: link,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'رابط المقطع في يوتيوب')),
            TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final id = videoIdFrom(link.text);
    if (id == null || title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تأكد من الرابط والعنوان')));
      return;
    }
    final now = DateTime.now();
    final v = Video(
        id: id,
        title: title.text.trim(),
        published: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    final err = await Cloud.instance.setVideos([v, ...Cloud.instance.extraVideos], 'إضافة مقطع');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'أُضيف المقطع ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([Repository.instance, cloud]),
      builder: (context, _) {
        final videos = Repository.instance.videos;
        final staff = cloud.ready && cloud.isFullAdmin;
        return Scaffold(
          appBar: AppBar(title: const Text('المرئيات')),
          floatingActionButton: staff
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة مقطع'),
                  onPressed: () => _add(context),
                )
              : null,
          body: videos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_outline, size: 64, color: kGold),
                      const SizedBox(height: 12),
                      const YouTubeButton(url: 'https://youtube.com/@qaidghsh', label: 'فتح قناة الشيخ في يوتيوب'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: videos.length + 1,
                  itemBuilder: (context, i) {
                    if (i == videos.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: YouTubeButton(url: 'https://youtube.com/@qaidghsh', label: 'كل المقاطع في قناة الشيخ'),
                      );
                    }
                    final v = videos[i];
                    final added = cloud.extraVideos.any((x) => x.id == v.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Stack(
                        children: [
                          VideoCard(video: v),
                          if (staff && added)
                            PositionedDirectional(
                              top: 6,
                              end: 6,
                              child: IconButton.filledTonal(
                                tooltip: 'حذف المقطع',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => cloud.setVideos(
                                    cloud.extraVideos.where((x) => x.id != v.id).toList(), 'حذف مقطع'),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

/// A red «يوتيوب» box, for those who prefer to watch there.
class YouTubeButton extends StatelessWidget {
  final String url;
  final String label;
  const YouTubeButton({super.key, required this.url, this.label = 'مشاهدة على يوتيوب'});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE62117),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openUrl(context, url),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.smart_display, color: Colors.white),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Plays one video inside the app (and on the website).
class VideoPlayerScreen extends StatefulWidget {
  final Video video;
  const VideoPlayerScreen({super.key, required this.video});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _c = YoutubePlayerController.fromVideoId(
    videoId: widget.video.id,
    autoPlay: true,
    params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true),
  );

  @override
  void dispose() {
    _c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return Scaffold(
      appBar: AppBar(title: const Text('المرئيات')),
      body: ListView(
        children: [
          YoutubePlayer(controller: _c, aspectRatio: 16 / 9),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(v.title,
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 19, fontWeight: FontWeight.bold, height: 1.6)),
                if (v.published.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(v.published, style: const TextStyle(color: Colors.grey)),
                ],
                const SizedBox(height: 18),
                YouTubeButton(url: v.url),
              ],
            ),
          ),
        ],
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
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: video))),
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
