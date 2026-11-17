import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../services/cloud.dart';
import '../services/telegram_out.dart';
import '../theme.dart';
import '../widgets/voice_recorder.dart';

/// The sheikh's «+»: write an article or a message, or record his voice,
/// and publish it in the app and/or his Telegram channel — now or later.
class ComposeScreen extends StatefulWidget {
  const ComposeScreen({super.key});

  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  String _kind = 'article'; // article | message | voice
  final _title = TextEditingController();
  final _text = TextEditingController();
  late String _chapter = Repository.instance.chapters.isEmpty ? 'mutafarriq' : Repository.instance.chapters.first.id;
  bool _inApp = true, _inChannel = true, _withLink = true;
  DateTime? _at;
  Recorded? _voice;
  bool _busy = false;

  InputDecoration _dec(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder());

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _publish() async {
    final cloud = Cloud.instance;
    if (_kind == 'voice') {
      if (_voice == null) return _say('سجّل أولاً');
      setState(() => _busy = true);
      final err = await TelegramOut.queueVoice(_voice!.bytes, _voice!.ext, caption: _title.text.trim(), at: _at);
      setState(() => _busy = false);
      if (err != null) return _say(err);
      _say(_at == null ? 'يُنشر التسجيل في قناة الصوتيات خلال دقائق، ثم يظهر في التسجيلات' : 'سيُنشر في وقته');
      if (mounted) Navigator.pop(context);
      return;
    }
    final text = _text.text.trim();
    if (text.isEmpty) return _say('اكتب النص');
    if (!_inApp && !_inChannel) return _say('اختر مكان النشر');
    setState(() => _busy = true);
    var id = '';
    if (_inApp) {
      final title = _title.text.trim().isEmpty ? text.split('\n').first : _title.text.trim();
      final err = await cloud.publishAnswer(
          chapter: _chapter, title: title, question: '', answer: text, publishAt: _at, type: _kind == 'article' ? 'article' : 'fatwa');
      if (err != null) {
        setState(() => _busy = false);
        return _say(err);
      }
      id = cloud.lastPublishedId;
    }
    if (_inChannel) {
      final err = await TelegramOut.queueText(
          TelegramOut.format(form: 'article', title: _kind == 'article' ? _title.text : '', text: text,
              link: _inApp && _withLink && id.isNotEmpty ? TelegramOut.linkOf(id) : ''),
          answerId: id,
          at: _at);
      if (err != null) {
        setState(() => _busy = false);
        return _say(err);
      }
    }
    setState(() => _busy = false);
    _say(_at != null ? 'جُدول النشر ✅' : (_inChannel ? 'نُشر في التطبيق، ويصل إلى القناة خلال دقائق ✅' : 'نُشر ✅'));
    if (mounted) Navigator.pop(context);
  }

  void _say(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('نشر جديد')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'article', label: Text('مقالة'), icon: Icon(Icons.article_outlined)),
            ButtonSegment(value: 'message', label: Text('رسالة'), icon: Icon(Icons.short_text)),
            ButtonSegment(value: 'voice', label: Text('صوت'), icon: Icon(Icons.mic)),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 14),
        if (_kind != 'message') ...[
          TextField(controller: _title, decoration: _dec(_kind == 'voice' ? 'عنوان التسجيل' : 'العنوان')),
          const SizedBox(height: 10),
        ],
        if (_kind == 'voice')
          VoiceRecorder(onDone: (r) => setState(() => _voice = r))
        else ...[
          TextField(controller: _text, maxLines: 12, decoration: _dec('النص')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: repo.chapters.any((c) => c.id == _chapter) ? _chapter : null,
            decoration: _dec('الباب'),
            items: [for (final c in repo.chapters) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() => _chapter = v ?? _chapter),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('في التطبيق'),
            value: _inApp,
            onChanged: (v) => setState(() => _inApp = v ?? true),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('في قناة تيليجرام'),
            value: _inChannel,
            onChanged: (v) => setState(() => _inChannel = v ?? true),
          ),
          if (_inApp && _inChannel)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('مع الرابط القصير إلى التطبيق'),
              value: _withLink,
              onChanged: (v) => setState(() => _withLink = v ?? true),
            ),
        ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.schedule),
          label: Text(_at == null
              ? 'انشر الآن (اضغط لتختار وقتاً لاحقاً)'
              : 'يُنشر: ${_at!.day}/${_at!.month} ${_at!.hour}:${_at!.minute.toString().padLeft(2, '0')}'),
          onPressed: _pickTime,
          onLongPress: () => setState(() => _at = null),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send),
          label: const Text('انشر'),
          onPressed: _busy ? null : _publish,
        ),
        const SizedBox(height: 10),
        const Text('الصوت يُنشر في قناة الصوتيات ويظهر في «التسجيلات» في التطبيق. والنص في القناة الرئيسية.',
            style: TextStyle(color: Colors.grey, height: 1.7)),
      ]),
    );
  }
}

/// The floating «+» on the home page: the developer and the sheikh only.
class ComposeFab extends StatelessWidget {
  const ComposeFab({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Cloud.instance,
        builder: (context, _) {
          if (!Cloud.instance.canManageStaff) return const SizedBox.shrink();
          return Material(
            color: kGold,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComposeScreen())),
              child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.add, color: Colors.black, size: 28)),
            ),
          );
        },
      );
}
