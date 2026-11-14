import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart' show normalizeArabic;
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
                  showModalBottomSheet(
                      context: context, showDragHandle: true, builder: (_) => _Player(lesson: l));
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
    if (list.isNotEmpty) _cache = list;
    return list;
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

void openRecording(BuildContext context, Recording r) {
  if (r.playable) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => _Player(lesson: Lesson(r.title, r.playUrl, r.by), telegram: r.telegram),
    );
  } else {
    openUrl(context, r.telegram); // older audio files play in Telegram
  }
}

Widget _recordingTile(BuildContext context, Recording r) => Card(
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
        onTap: () => openRecording(context, r),
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
        for (final r in _list.take(5)) _recordingTile(context, r),
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
                    itemBuilder: (context, i) => _recordingTile(context, shown[i]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Player extends StatefulWidget {
  final Lesson lesson;
  final String telegram; // where to listen if it cannot play here
  const _Player({required this.lesson, this.telegram = ''});

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  final _player = AudioPlayer();
  String? _error;
  double _speed = 1.0;

  String get _key => 'audio_pos_${widget.lesson.url.hashCode}';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      var url = widget.lesson.url;
      if (url.startsWith('tg:')) {
        final link = await Recordings.voiceLink(int.parse(url.substring(3)));
        if (link == null) throw Exception('no link');
        url = link;
      }
      await _player.setUrl(url);
      final prefs = await SharedPreferences.getInstance();
      final pos = prefs.getInt(_key) ?? 0;
      if (pos > 0) await _player.seek(Duration(seconds: pos));
      _player.play();
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر تشغيل الملف، تأكد من الاتصال بالإنترنت');
    }
  }

  Future<void> _savePos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, _player.position.inSeconds);
  }

  @override
  void dispose() {
    _savePos();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.lesson.title,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_error != null)
              Column(children: [
                Text(_error!, style: const TextStyle(color: Colors.red)),
                if (widget.telegram.isNotEmpty)
                  TextButton.icon(
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('استمع في تيليجرام'),
                    onPressed: () => openUrl(context, widget.telegram),
                  ),
              ])
            else
              StreamBuilder<Duration>(
                stream: _player.positionStream,
                builder: (context, snap) {
                  final pos = snap.data ?? Duration.zero;
                  final total = _player.duration ?? Duration.zero;
                  final max = total.inMilliseconds.toDouble();
                  return Column(
                    children: [
                      Slider(
                        value: max <= 0 ? 0 : pos.inMilliseconds.clamp(0, max.toInt()).toDouble(),
                        max: max <= 0 ? 1 : max,
                        onChanged: max <= 0 ? null : (v) => _player.seek(Duration(milliseconds: v.toInt())),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text(_fmt(pos)), Text(_fmt(total))],
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'رجوع 15 ثانية',
                  iconSize: 32,
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => _player.seek(_player.position - const Duration(seconds: 15)),
                ),
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snap) {
                    final playing = snap.data?.playing ?? false;
                    return IconButton.filled(
                      iconSize: 44,
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        if (playing) {
                          _player.pause();
                          _savePos();
                        } else {
                          _player.play();
                        }
                      },
                    );
                  },
                ),
                IconButton(
                  tooltip: 'تقديم 15 ثانية',
                  iconSize: 32,
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => _player.seek(_player.position + const Duration(seconds: 15)),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
                final next = speeds[(speeds.indexOf(_speed) + 1) % speeds.length];
                setState(() => _speed = next);
                _player.setSpeed(next);
              },
              child: Text('السرعة ×$_speed'),
            ),
            const Text('يكمل من حيث توقفت عند فتحه مرة أخرى',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
