import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart' show normalizeArabic;
import '../services/audio_center.dart';
import '../services/cloud.dart';
import 'content_screens.dart';
import '../theme.dart';
import '../widgets/common.dart';

bool _isAudioFile(String url) =>
    RegExp(r'\.(mp3|m4a|aac|ogg|oga|opus|wav)(\?|$)', caseSensitive: false).hasMatch(url);

/// The sheikh's recorded lessons. Staff add them (title + link); direct
/// audio files play inside the app and resume where the listener stopped.
class AudioLibraryScreen extends StatelessWidget {
  const AudioLibraryScreen({super.key});

  Future<void> _edit(BuildContext context, {int? index}) async {
    final cloud = Cloud.instance;
    final old = index == null ? null : cloud.lessons[index];
    final title = TextEditingController(text: old?.title ?? '');
    final url = TextEditingController(text: old?.url ?? '');
    final group = TextEditingController(text: old?.group ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(old == null ? 'درس جديد' : 'تعديل الدرس'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
              TextField(controller: group, decoration: const InputDecoration(labelText: 'السلسلة (اختياري)')),
              TextField(
                controller: url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'الرابط (ملف صوتي، أو رابط تيليجرام/يوتيوب)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !url.text.trim().startsWith('http')) return;
    final list = [...cloud.lessons];
    final l = Lesson(title.text.trim(), url.text.trim(), group.text.trim());
    if (index == null) {
      list.insert(0, l);
    } else {
      list[index] = l;
    }
    final err = await cloud.setLessons(list, index == null ? 'إضافة درس صوتي' : 'تعديل درس صوتي');
    if (context.mounted && err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final staff = cloud.ready && cloud.isFullAdmin;
        final items = cloud.lessons;
        // Lessons grouped by their series, in the order they were added.
        final groups = <String, List<int>>{};
        for (var i = 0; i < items.length; i++) {
          groups.putIfAbsent(items[i].group.isEmpty ? 'دروس متفرقة' : items[i].group, () => []).add(i);
        }
        Widget lessonTile(int i) {
          final l = items[i];
          final playable = _isAudioFile(l.url);
          final yt = VideosScreen.videoIdFrom(l.url);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: kGold.withValues(alpha: 0.18),
                child: Icon(
                    playable ? Icons.play_arrow : (yt != null ? Icons.smart_display_outlined : Icons.open_in_new),
                    color: kGoldChip),
              ),
              title: Text(l.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: staff
                  ? PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') {
                          _edit(context, index: i);
                        } else {
                          await cloud.setLessons([...items]..removeAt(i), 'حذف درس صوتي');
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('تعديل')),
                        PopupMenuItem(value: 'delete', child: Text('حذف')),
                      ],
                    )
                  : null,
              onTap: () {
                if (playable) {
                  // This lesson, then the next ones of the same series.
                  final same = [
                    for (final j in groups[l.group.isEmpty ? 'دروس متفرقة' : l.group] ?? [i])
                      if (_isAudioFile(items[j].url)) items[j]
                  ];
                  final at = same.indexOf(l);
                  AudioCenter.instance.playQueue(
                      [for (final x in same) AudioItem(x.title, x.url, by: x.group)], at < 0 ? 0 : at);
                  PlayerSheet.open(context);
                } else if (yt != null) {
                  // YouTube lessons play inside the app.
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => VideoPlayerScreen(video: Video(id: yt, title: l.title, published: ''))));
                } else {
                  openUrl(context, l.url);
                }
              },
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('الدروس والتسجيلات الصوتية')),
          floatingActionButton: staff
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('درس جديد'),
                  onPressed: () => _edit(context),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            children: [
              const _Recordings(),
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 14, 6, 8),
                  child: Row(children: [
                    Icon(Icons.playlist_play, color: kGoldChip),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('${g.key} (${g.value.length})',
                          style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                    ),
                  ]),
                ),
                for (final i in g.value) lessonTile(i),
              ],
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('تُضاف سلاسل دروس الشيخ هنا بإذن الله.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One recording of the sheikh's channel (t.me/QaidSandVe).
class Recording {
  final int id;
  final String kind; // v: voice note, a: audio file
  final String title, by, date, dur;
  String file = ''; // the audio file kept by the bot, when there is one
  Recording(this.id, this.kind, this.title, this.by, this.date, this.dur);

  String get telegram => 'https://t.me/$recordingsChannel/$id';

  /// Plays inside the app: voice notes always (on Android), files once the bot has them.
  bool get playable => file.isNotEmpty || (kind == 'v' && !kIsWeb);

  String get playUrl => file.isNotEmpty ? file : 'tg:$id';
}

const recordingsChannel = 'QaidSandVe';
const _mediaBase = 'https://raw.githubusercontent.com/${AppConfig.owner}/${AppConfig.repo}/media/';

/// The list of recordings, kept on the phone so it opens at once.
class Recordings {
  static List<Recording>? _cache;

  static Future<List<Recording>> load({bool fresh = false}) async {
    if (_cache != null && !fresh) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    String? body;
    try {
      final res = await http.get(Uri.parse('${_mediaBase}recordings.json')).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        body = utf8.decode(res.bodyBytes);
        await prefs.setString('recordingsList', body);
      }
    } catch (_) {}
    body ??= prefs.getString('recordingsList');
    final list = <Recording>[];
    if (body != null) {
      try {
        final j = jsonDecode(body);
        final items = (j is Map ? j['items'] : j) as List;
        for (final e in items) {
          final m = e as Map;
          list.add(Recording(((m['id'] ?? 0) as num).toInt(), '${m['k'] ?? 'v'}', '${m['t'] ?? m['title'] ?? ''}',
              '${m['b'] ?? ''}', '${m['d'] ?? m['date'] ?? ''}', '${m['u'] ?? m['dur'] ?? ''}'));
        }
      } catch (_) {}
    }
    // Files the bot took from the channel: played from our own copy.
    try {
      final res = await http.get(Uri.parse('${_mediaBase}audio.json')).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final byId = {for (final r in list) r.id: r};
        for (final e in jsonDecode(utf8.decode(res.bodyBytes)) as List) {
          final m = e as Map;
          final id = int.tryParse('${m['key']}'.split('_').last) ?? 0;
          final url = '$_mediaBase${m['file']}';
          final r = byId[id];
          if (r != null) {
            r.file = url;
          } else {
            list.add(Recording(id, 'a', '${m['title'] ?? ''}', '', '${m['date'] ?? ''}', '')..file = url);
          }
        }
        list.sort((a, b) => b.id.compareTo(a.id));
      }
    } catch (_) {}
    // The newest recordings, read straight from the channel, so a new one
    // shows within minutes instead of waiting for the list to be rebuilt.
    if (!kIsWeb) {
      try {
        list.insertAll(0, await _newest(list.isEmpty ? 0 : list.map((r) => r.id).reduce((a, b) => a > b ? a : b)));
      } catch (_) {}
    }
    if (list.isNotEmpty) _cache = list;
    return list;
  }

  static Future<List<Recording>> _newest(int known) async {
    final res = await http
        .get(Uri.parse('https://t.me/s/$recordingsChannel'),
            headers: {'User-Agent': 'Mozilla/5.0 (Android 13) ibn-alshabira-app'})
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];
    final body = utf8.decode(res.bodyBytes);
    final blocks = RegExp(r'<div class="tgme_widget_message_wrap[\s\S]*?(?=<div class="tgme_widget_message_wrap|$)')
        .allMatches(body)
        .map((m) => m.group(0)!)
        .toList();
    final postRe = RegExp('data-post="$recordingsChannel/(\\d+)"');
    final textRe = RegExp(r'<div class="tgme_widget_message_text[^"]*"[^>]*>([\s\S]*?)</div>');
    String text(String b) {
      final m = textRe.firstMatch(b);
      if (m == null) return '';
      return m
          .group(1)!
          .replaceAll(RegExp(r'<br\s*/?>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&quot;', '"')
          .replaceAll('&amp;', '&')
          .replaceAll('&nbsp;', ' ')
          .trim();
    }

    String firstLine(String t) {
      for (final l in t.split('\n')) {
        final s = l.replaceAll(RegExp(r'^[^\p{L}\p{N}(«]+|[^\p{L}\p{N})»؟?!.]+$', unicode: true), '').trim();
        if (s.length >= 4 && !s.startsWith('http')) return s.length > 110 ? '${s.substring(0, 110)}…' : s;
      }
      return '';
    }

    final out = <Recording>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final id = int.tryParse(postRe.firstMatch(b)?.group(1) ?? '') ?? 0;
      if (id <= known || !b.contains('tgme_widget_message_voice')) continue;
      var title = firstLine(text(b));
      // A voice note without words: its description is usually the next post.
      for (var j = i + 1; title.isEmpty && j < blocks.length && j <= i + 2; j++) {
        if (!blocks[j].contains('tgme_widget_message_voice')) title = firstLine(text(blocks[j]));
      }
      final dur = RegExp(r'tgme_widget_message_voice_duration[^>]*>([^<]+)<').firstMatch(b)?.group(1) ?? '';
      final date = RegExp(r'<time[^>]*datetime="([^"]+)"').firstMatch(b)?.group(1) ?? '';
      out.add(Recording(id, 'v', title.isEmpty ? 'تسجيل صوتي جديد' : title, '',
          date.length >= 10 ? date.substring(0, 10) : '', dur.trim()));
    }
    out.sort((a, b) => b.id.compareTo(a.id));
    return out;
  }

  /// Asks Telegram for the playable link of a voice note.
  static Future<String?> voiceLink(int id) async {
    try {
      final res = await http
          .get(Uri.parse('https://t.me/$recordingsChannel/$id?embed=1&mode=tme'))
          .timeout(const Duration(seconds: 15));
      final m = RegExp(r'<audio[^>]+src="([^"]+)"').firstMatch(utf8.decode(res.bodyBytes));
      return m?.group(1)?.replaceAll('&amp;', '&');
    } catch (_) {
      return null;
    }
  }
}

AudioItem _item(Recording r) => AudioItem(r.title, r.playUrl, by: r.by, telegram: r.telegram);

/// Plays [r]; when [list] is given, the recordings after it follow by themselves.
void openRecording(BuildContext context, Recording r, {List<Recording>? list}) {
  if (!r.playable) {
    openUrl(context, r.telegram); // older audio files play in Telegram
    return;
  }
  AudioCenter.voiceLink ??= Recordings.voiceLink;
  final playable = (list ?? [r]).where((x) => x.playable).toList();
  final at = playable.indexWhere((x) => x.id == r.id);
  if (at < 0) {
    AudioCenter.instance.play(_item(r));
  } else {
    AudioCenter.instance.playQueue([for (final x in playable) _item(x)], at);
  }
  PlayerSheet.open(context);
}

Widget _recordingTile(BuildContext context, Recording r, [List<Recording>? list]) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: kGold.withValues(alpha: 0.18),
          child: Icon(r.playable ? Icons.play_arrow : Icons.send_outlined, color: kGoldChip),
        ),
        title: Text(r.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
        subtitle: Text(
          [if (r.by.isNotEmpty) r.by, if (r.dur.isNotEmpty) '⏱ ${r.dur}', r.date].join('  ·  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => openRecording(context, r, list: list),
      ),
    );

/// The sheikh's recordings from his channel: the newest five, and all of them.
class _Recordings extends StatefulWidget {
  const _Recordings();

  @override
  State<_Recordings> createState() => _RecordingsState();
}

class _RecordingsState extends State<_Recordings> {
  List<Recording> _list = [];

  @override
  void initState() {
    super.initState();
    Recordings.load().then((l) {
      if (mounted) setState(() => _list = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: Row(children: [
            Icon(Icons.mic_none, color: kGoldChip),
            const SizedBox(width: 6),
            Expanded(
              child: Text('التسجيلات الصوتية (${_list.length})',
                  style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ]),
        ),
        for (final r in _list.take(5)) _recordingTile(context, r, _list),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.library_music_outlined),
          label: Text('كل التسجيلات (${_list.length})'),
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecordingsScreen())),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// «التسجيلات الصوتية»: every recording of the channel, with search.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<Recording>? _all;
  String _q = '';

  @override
  void initState() {
    super.initState();
    Recordings.load().then((l) {
      if (mounted) setState(() => _all = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final q = normalizeArabic(_q.trim());
    final shown = all == null || q.isEmpty
        ? (all ?? <Recording>[])
        : all.where((r) => normalizeArabic('${r.title} ${r.by}').contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('التسجيلات الصوتية')),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'ابحث في عناوين التسجيلات',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Text('${shown.length} تسجيلاً', style: const TextStyle(color: Colors.grey)),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _recordingTile(context, shown[i], shown),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The full player: opened from a recording, a lesson or the bar at the top.
class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key});

  static void open(BuildContext context) => showModalBottomSheet(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const PlayerSheet(),
      );

  static String fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final a = AudioCenter.instance;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final it = a.current;
        if (it == null) return const SizedBox(height: 120, child: Center(child: Text('لا يوجد تسجيل يعمل')));
        final p = a.player;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(it.title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.5)),
              if (a.queue.length > 1)
                Text('${a.index + 1} من ${a.queue.length}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 10),
              if (a.error != null)
                Column(children: [
                  Text(a.error!, style: const TextStyle(color: Colors.red)),
                  if (it.telegram.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('استمع في تيليجرام'),
                      onPressed: () => openUrl(context, it.telegram),
                    ),
                ])
              else if (a.loading)
                const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator())
              else
                StreamBuilder<Duration>(
                  stream: p.positionStream,
                  builder: (context, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final total = p.duration ?? Duration.zero;
                    final max = total.inMilliseconds.toDouble();
                    return Column(children: [
                      Slider(
                        value: max <= 0 ? 0 : pos.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                        max: max <= 0 ? 1 : max,
                        onChanged: max <= 0 ? null : (v) => p.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text(fmt(pos)), Text(fmt(total))],
                      ),
                    ]);
                  },
                ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  tooltip: 'السابق',
                  icon: const Icon(Icons.skip_next), // RTL: «next» arrow points back
                  onPressed: a.index > 0 ? a.previous : null,
                ),
                IconButton(tooltip: 'رجوع 15 ثانية', iconSize: 30, icon: const Icon(Icons.replay_10), onPressed: () => a.seekBy(-15)),
                IconButton.filled(
                  iconSize: 44,
                  icon: Icon(a.playing ? Icons.pause : Icons.play_arrow),
                  onPressed: a.toggle,
                ),
                IconButton(tooltip: 'تقديم 15 ثانية', iconSize: 30, icon: const Icon(Icons.forward_10), onPressed: () => a.seekBy(15)),
                IconButton(
                  tooltip: 'التالي',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: a.hasNext ? a.next : null,
                ),
              ]),
              Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
                TextButton(onPressed: a.nextSpeed, child: Text('السرعة ×${a.speed}')),
                if (!kIsWeb) _DownloadButton(item: it),
                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('إغلاق'),
                  onPressed: () {
                    a.close();
                    Navigator.of(context).maybePop();
                  },
                ),
              ]),
              const Text('يكمل من حيث توقفت، ويستمر وأنت خارج التطبيق، ثم يبدأ التالي وحده',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }
}

class _DownloadButton extends StatefulWidget {
  final AudioItem item;
  const _DownloadButton({required this.item});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool? _have;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant _DownloadButton old) {
    super.didUpdateWidget(old);
    if (old.item.url != widget.item.url) _check();
  }

  Future<void> _check() async {
    final v = await AudioCenter.instance.isDownloaded(widget.item);
    if (mounted) setState(() => _have = v);
  }

  @override
  Widget build(BuildContext context) {
    final a = AudioCenter.instance;
    if (a.downloading.contains(widget.item.key)) {
      return const TextButton(onPressed: null, child: Text('جارٍ التنزيل…'));
    }
    if (_have == true) {
      return TextButton.icon(
        icon: const Icon(Icons.download_done),
        label: const Text('محفوظ بلا إنترنت'),
        onPressed: () async {
          await a.removeDownload(widget.item);
          _check();
        },
      );
    }
    return TextButton.icon(
      icon: const Icon(Icons.download_outlined),
      label: const Text('نزّله'),
      onPressed: () async {
        final err = await a.download(widget.item);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'نُزّل، تسمعه الآن بلا إنترنت')));
        _check();
      },
    );
  }
}

/// The slim bar at the top of every page while something plays: read and
/// listen together; tap it for the player, ✕ to stop.
class NowPlayingBar extends StatelessWidget {
  const NowPlayingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final a = AudioCenter.instance;
    return ListenableBuilder(
      listenable: a,
      builder: (context, _) {
        final it = a.current;
        if (it == null) return const SizedBox.shrink();
        return Material(
          color: const Color(0xFF0E3A40),
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: () {
                final ctx = playerNavKey?.currentContext;
                if (ctx != null) PlayerSheet.open(ctx);
              },
              child: SizedBox(
                height: 44,
                child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(a.playing ? Icons.graphic_eq : Icons.headphones, color: kGold, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                  ),
                  if (a.loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
                    )
                  else
                    IconButton(
                      // No tooltips here: this bar sits above the pages' overlay.
                      icon: Icon(a.playing ? Icons.pause : Icons.play_arrow, color: Colors.white),
                      onPressed: a.toggle,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: a.close,
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Set by main.dart: where the bar opens the player.
GlobalKey<NavigatorState>? playerNavKey;
