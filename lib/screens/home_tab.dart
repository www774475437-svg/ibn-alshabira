import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/update_check.dart';

import '../data/hijri.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../services/cloud.dart';
import 'ask_screen.dart';
import 'channel_screen.dart';
import 'book_reader_screen.dart';
import 'content_screens.dart';
import 'chapter_screen.dart';

class HomeTab extends StatefulWidget {
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenMore;

  const HomeTab({super.key, required this.onOpenSearch, required this.onOpenMore});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  DateTime? _updateAt;

  @override
  void initState() {
    super.initState();
    updatePublishedAt().then((v) {
      if (mounted && v != null) setState(() => _updateAt = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onOpenSearch = widget.onOpenSearch;
    final repo = Repository.instance;
    final latest = repo.fatwas.reversed.take(5).toList();
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Header(onOpenSearch: onOpenSearch, onOpenMore: widget.onOpenMore)),
          const SliverToBoxAdapter(child: _CloudSections()),
          if (!kIsWeb && repo.lastBook != null)
            SliverToBoxAdapter(child: _ContinueReading(book: repo.lastBook!)),
          if (_updateAt != null)
            SliverToBoxAdapter(
              child: _Banner(
                icon: Icons.system_update,
                title: 'يوجد تحديث جديد للتطبيق',
                subtitle: 'اضغط لتحميل النسخة الجديدة',
                note: 'صدر ${updateTimeText(_updateAt!)}',
                url: AppConfig.apkUrl,
              ),
            ),
          if (kIsWeb)
            const SliverToBoxAdapter(
              child: _Banner(
                icon: Icons.android,
                title: 'حمّل تطبيق «ابن الشابرة»',
                subtitle: 'لأجهزة أندرويد — يعمل دون إنترنت',
                url: AppConfig.apkUrl,
              ),
            ),
          SliverToBoxAdapter(child: _TodayStrip(onSetWird: widget.onOpenMore)),
          if (repo.fatwaOfDay != null)
            SliverToBoxAdapter(child: _FatwaOfDay(fatwa: repo.fatwaOfDay!)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: const BorderSide(color: kGold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.shuffle, color: kGold),
                label: const Text('جواب عشوائي لم تقرأه بعد'),
                onPressed: () {
                  final f = repo.randomUnread();
                  if (f != null) openFatwa(context, f);
                },
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.forum_outlined, color: kGold),
                  title: const Text('اسأل الشيخ', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: ListenableBuilder(
                    listenable: Cloud.instance,
                    builder: (context, _) => Cloud.instance.unseenReplies > 0
                        ? const Text('وصلك رد جديد من الشيخ ✉️',
                            style: TextStyle(color: kGoldChip, fontWeight: FontWeight.bold))
                        : const Text('أرسل سؤالك ويصلك الجواب'),
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AskScreen())),
                ),
              ),
            ),
          ),
          if (repo.latest().isNotEmpty) ...[
            const SliverToBoxAdapter(child: _SectionTitle('أُضيف حديثاً')),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: repo.latest().length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final f = repo.latest()[i];
                    return SizedBox(
                      width: 240,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => openFatwa(context, f),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${repo.chapterName(f.chapter)} · ${Hijri.parse(f.date) ?? f.date}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: kGoldChip, fontSize: 12)),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: Text(f.title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(height: 1.6, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
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
          if (repo.channel.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionTitle('أحدث منشورات القناة',
                  action: 'الكل',
                  onAction: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ChannelScreen()))),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: repo.channel.length < 8 ? repo.channel.length : 8,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final p = repo.channel[i];
                    return SizedBox(
                      width: 250,
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => openChannelPost(context, p),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.date, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                const SizedBox(height: 6),
                                Expanded(
                                  child: Text(p.text,
                                      maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.7)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          if (repo.videos.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionTitle('أحدث المرئيات',
                  action: 'الكل',
                  onAction: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const VideosScreen()))),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 215,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: repo.videos.length > 8 ? 8 : repo.videos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => VideoCard(video: repo.videos[i], width: 240),
                ),
              ),
            ),
          ],
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
  final VoidCallback onOpenMore;
  const _Header({required this.onOpenSearch, required this.onOpenMore});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? kGold : brandColor(context);
    final soft = theme.colorScheme.onSurface.withValues(alpha: 0.65);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: CustomPaint(
        painter: _PatternPainter(dark: dark),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 10, 18, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: dark
                  ? [const Color(0xE6101010), const Color(0xE61A1A1A)]
                  : [
                      const Color(0xCCFBF1D6),
                      const Color(0xCCFFFFFF),
                      kTeal.withValues(alpha: 0.16),
                    ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipOval(child: Image.asset('assets/icon/icon.png', width: 40, height: 40)),
                  const SizedBox(width: 10),
                  Text('ابن الشابرة',
                      style: TextStyle(
                          fontFamily: 'Tajawal', color: ink, fontSize: 21, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'البحث',
                    icon: Icon(Icons.search, color: ink),
                    onPressed: onOpenSearch,
                  ),
                  IconButton(
                    tooltip: dark ? 'الوضع الفاتح' : 'الوضع الداكن',
                    icon: Icon(dark ? Icons.wb_sunny_outlined : Icons.nightlight_outlined, color: ink),
                    onPressed: () => repo.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
                  ),
                  IconButton(
                    tooltip: 'المزيد',
                    icon: Icon(Icons.menu, color: ink),
                    onPressed: onOpenMore,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('أهلاً بك في تطبيق الشيخ',
                  style: TextStyle(
                      fontFamily: 'Amiri', color: kGoldChip, fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('قايد بن غانم الشابرة',
                  style: TextStyle(
                      fontFamily: 'Tajawal', color: ink, fontSize: 29, fontWeight: FontWeight.bold, height: 1.5)),
              const SizedBox(height: 8),
              Text('أجوبة ومقالات وكتب، مرتّبة على الأبواب، مع البحث بالموضوع.',
                  style: TextStyle(color: soft, fontSize: 15, height: 1.7)),
              const SizedBox(height: 18),
              Material(
                color: dark ? const Color(0xFF1E1E1E) : Colors.white,
                elevation: 3,
                shadowColor: Colors.black26,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  onTap: onOpenSearch,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: soft),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('ابحث، مثل: الأذان', style: TextStyle(color: soft, fontSize: 16)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          decoration: BoxDecoration(
                            color: dark ? kGold : brandColor(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text('بحث',
                              style: TextStyle(
                                  color: dark ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Soft geometric lattice (overlapping diamonds) behind the header.
class _PatternPainter extends CustomPainter {
  final bool dark;
  _PatternPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? Colors.black : Colors.white);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = kGold.withValues(alpha: dark ? 0.16 : 0.30);
    void diamond(Offset c, double r) {
      final p = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close();
      canvas.drawPath(p, line);
    }

    const step = 86.0;
    for (var y = -step; y < size.height + step; y += step) {
      for (var x = -step; x < size.width + step; x += step) {
        diamond(Offset(x, y), step * 0.5);
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: step * 0.5, height: step * 0.5), line);
      }
    }
    // two large accents
    final big = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = kGold.withValues(alpha: dark ? 0.22 : 0.40);
    for (final r in [size.height * 0.55, size.height * 0.75]) {
      final c = Offset(size.width * 0.12, size.height * 0.30);
      final p = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close();
      canvas.drawPath(p, big);
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.dark != dark;
}

/// Announcement and series (from the online database).
class _CloudSections extends StatelessWidget {
  const _CloudSections();

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (cloud.announcement.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: brandColor(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.campaign, color: kGold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(cloud.announcement,
                          style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.7)),
                    ),
                  ],
                ),
              ),
            ),
          if (cloud.pinned.isNotEmpty) ...[
            const _SectionTitle('أجوبة مختارة'),
            for (final id in cloud.pinned.take(6))
              if (Repository.instance.findById(id) case final f?) FatwaTile(fatwa: f),
          ],
          if (cloud.tracks.isNotEmpty) ...[
            const _SectionTitle('مسارات التعلّم'),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: cloud.tracks.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final s = cloud.tracks[i];
                  return SizedBox(
                    width: 190,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => SeriesScreen(seriesId: s.id))),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(children: [
                                const Icon(Icons.route_outlined, color: kGold, size: 20),
                                const SizedBox(width: 6),
                                Text('${s.ids.where(Repository.instance.everRead.contains).length} من ${s.ids.length}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ]),
                              const SizedBox(height: 6),
                              Text(s.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (cloud.plainSeries.isNotEmpty) ...[
            const _SectionTitle('سلاسل الأجوبة'),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: cloud.plainSeries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final s = cloud.plainSeries[i];
                  return SizedBox(
                    width: 190,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => SeriesScreen(seriesId: s.id))),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(children: [
                                const Icon(Icons.collections_bookmark_outlined, color: kGold, size: 20),
                                const SizedBox(width: 6),
                                Text('${s.ids.length} جواب', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              ]),
                              const SizedBox(height: 6),
                              Text(s.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContinueReading extends StatelessWidget {
  final Book book;
  const _ContinueReading({required this.book});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.auto_stories, color: kGold, size: 30),
            title: const Text('أكمل القراءة', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => BookReaderScreen(book: book))),
          ),
        ),
      );
}

class _FatwaOfDay extends StatelessWidget {
  final Fatwa fatwa;
  const _FatwaOfDay({required this.fatwa});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Material(
        color: kGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openFatwa(context, fatwa),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wb_sunny_outlined, color: kGold, size: 20),
                    SizedBox(width: 6),
                    Text('جواب اليوم',
                        style: TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(fatwa.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.5)),
                const SizedBox(height: 6),
                const Text('اضغط لقراءة الجواب', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  final String? note;
  const _Banner({required this.icon, required this.title, required this.subtitle, required this.url, this.note});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        color: brandColor(context),
        child: ListTile(
          leading: Icon(icon, color: kGold, size: 30),
          title: Text(title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle, style: const TextStyle(color: Colors.white70)),
              if (note != null)
                Text(note!, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
          trailing: const Icon(Icons.download, color: kGold),
          onTap: () => openUrl(context, url),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const _SectionTitle(this.text, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 8, 10),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 22,
            decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(fontFamily: 'Tajawal', fontSize: 19, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}


/// Today's Hijri date, a greeting on Ramadan and the Eids, and the
/// reader's daily reading with their streak.
class _TodayStrip extends StatelessWidget {
  final VoidCallback onSetWird;
  const _TodayStrip({required this.onSetWird});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final today = Hijri.from(DateTime.now());
    final greeting = today.greeting;
    final target = repo.wirdTarget;
    final done = repo.readToday;
    final streak = repo.streak;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (greeting != null)
            Card(
              color: kGold.withValues(alpha: 0.16),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Icon(Icons.celebration_outlined, color: kGoldChip),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(greeting,
                        style: const TextStyle(fontWeight: FontWeight.bold, height: 1.7, color: kGoldChip)),
                  ),
                ]),
              ),
            ),
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: target == 0 ? onSetWird : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.calendar_month_outlined, size: 18, color: kGold),
                      const SizedBox(width: 6),
                      Expanded(child: Text('$today', style: const TextStyle(fontWeight: FontWeight.w600))),
                      if (streak > 0) ...[
                        const Icon(Icons.local_fire_department, size: 18, color: Colors.deepOrange),
                        Text(' $streak ${streak == 1 ? 'يوم' : streak == 2 ? 'يومان' : streak <= 10 ? 'أيام' : 'يوماً'} متتالية',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    if (target == 0)
                      const Text('اجعل لك وِرداً يومياً من الأجوبة: اضغط هنا ثم اختره من الإعدادات.',
                          style: TextStyle(color: Colors.grey, fontSize: 13))
                    else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: (done / target).clamp(0.0, 1.0), minHeight: 7),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          done >= target
                              ? 'أتممت وِرد اليوم ✅ ($done من $target)'
                              : 'وِرد اليوم: قرأت $done من $target',
                          style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
