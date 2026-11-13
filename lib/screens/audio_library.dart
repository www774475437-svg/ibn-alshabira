import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloud.dart';
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
        return Scaffold(
          appBar: AppBar(title: const Text('المكتبة الصوتية')),
          floatingActionButton: staff
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('درس جديد'),
                  onPressed: () => _edit(context),
                )
              : null,
          body: items.isEmpty
              ? const EmptyState(icon: Icons.headphones, text: 'تُضاف دروس الشيخ الصوتية هنا قريباً بإذن الله.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final l = items[i];
                    final playable = _isAudioFile(l.url);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kGold.withValues(alpha: 0.18),
                          child: Icon(playable ? Icons.play_arrow : Icons.open_in_new, color: kGoldChip),
                        ),
                        title: Text(l.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: l.group.isEmpty ? null : Text(l.group),
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
                        onTap: () => playable
                            ? showModalBottomSheet(
                                context: context,
                                showDragHandle: true,
                                builder: (_) => _Player(lesson: l),
                              )
                            : openUrl(context, l.url),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _Player extends StatefulWidget {
  final Lesson lesson;
  const _Player({required this.lesson});

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
      await _player.setUrl(widget.lesson.url);
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
              Text(_error!, style: const TextStyle(color: Colors.red))
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
