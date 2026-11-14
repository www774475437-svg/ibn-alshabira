import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';

void _toast(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

/// Pick a sub-chapter of [chapterId] ('' = none).
class SubPicker extends StatelessWidget {
  final String chapterId;
  final String value;
  final ValueChanged<String> onChanged;
  const SubPicker({super.key, required this.chapterId, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final names = [...?Cloud.instance.subs[chapterId]];
    if (value.isNotEmpty && !names.contains(value)) names.add(value);
    if (names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('$chapterId|$value'),
        value: value,
        decoration: _deco('الباب الفرعي (اختياري)'),
        items: [
          const DropdownMenuItem(value: '', child: Text('بدون')),
          for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
        ],
        onChanged: (v) => onChanged(v ?? ''),
      ),
    );
  }
}

/// «رمضان، السفر» → ['رمضان', 'السفر']
List<String> parseTags(String text) => text
    .split(RegExp('[,،#\\n]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toSet()
    .toList();

InputDecoration _deco(String label) =>
    InputDecoration(labelText: label, border: const OutlineInputBorder(), alignLabelWithHint: true);

/// Admin: questions sent by users. Three choices for each question:
/// reply and publish, reply privately, or hide.
class QuestionsTab extends StatefulWidget {
  const QuestionsTab({super.key});

  @override
  State<QuestionsTab> createState() => _QuestionsTabState();
}

class _QuestionsTabState extends State<QuestionsTab> {
  String _filter = 'new'; // new | answered | hidden | blocked

  Widget _blockedList() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Cloud.instance.blockedStream(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const EmptyState(icon: Icons.block, text: 'لا يوجد محظورون');
          return ListView(
            children: [
              for (final d in docs)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.block, color: Colors.red),
                    title: Text('${d.data()['sample'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: const Text('سؤال من هذا السائل'),
                    trailing: TextButton(
                      onPressed: () => Cloud.instance.unblockUser(d.id),
                      child: const Text('رفع الحظر'),
                    ),
                  ),
                ),
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    final repo = Repository.instance;
    return Column(
      children: [
        if (cloud.isFullAdmin)
          ListenableBuilder(
            listenable: cloud,
            builder: (context, _) => SwitchListTile(
              dense: true,
              title: const Text('استقبال الأسئلة من الناس'),
              subtitle: Text(cloud.askOpen ? 'مفتوح' : 'متوقف مؤقتاً'),
              value: cloud.askOpen,
              onChanged: (v) =>
                  cloud.saveAsk(open: v, logText: v ? 'فتح استقبال الأسئلة' : 'إيقاف استقبال الأسئلة'),
            ),
          ),
        if (cloud.isFullAdmin)
          ListenableBuilder(
            listenable: cloud,
            builder: (context, _) => ListTile(
              dense: true,
              title: const Text('عدد الأسئلة المسموح للشخص في اليوم'),
              trailing: DropdownButton<int>(
                value: const [1, 2, 3, 5, 10, 20].contains(cloud.askLimit) ? cloud.askLimit : 3,
                underline: const SizedBox(),
                items: [for (final n in const [1, 2, 3, 5, 10, 20]) DropdownMenuItem(value: n, child: Text('$n'))],
                onChanged: (n) => cloud.saveAsk(limit: n ?? 3),
              ),
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'new', label: Text('جديدة')),
              ButtonSegment(value: 'answered', label: Text('أُجيب عنها')),
              ButtonSegment(value: 'hidden', label: Text('مخفية')),
              ButtonSegment(value: 'blocked', label: Text('المحظورون')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
        ),
        Expanded(
          child: _filter == 'blocked'
              ? _blockedList()
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: cloud.allQuestions(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const EmptyState(icon: Icons.error_outline, text: 'تعذّر تحميل الأسئلة');
                    }
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final docs =
                        snap.data!.docs.where((d) => (d.data()['status'] ?? 'new') == _filter).toList();
                    if (docs.isEmpty) {
                      return const EmptyState(icon: Icons.inbox_outlined, text: 'لا توجد أسئلة هنا');
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final q = d.data();
                        final reply = '${q['reply'] ?? ''}';
                        final text = '${q['text'] ?? ''}';
                        final chapter = '${q['chapter'] ?? ''}';
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (chapter.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text('باب ${repo.chapterName(chapter)}',
                                        style: const TextStyle(color: kGoldChip, fontSize: 12)),
                                  ),
                                if ('${q['name'] ?? ''}'.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      const Icon(Icons.person_outline, size: 16, color: kGoldChip),
                                      const SizedBox(width: 4),
                                      Text('${q['name']}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
                                    ]),
                                  ),
                                SelectableText(text, style: const TextStyle(fontSize: 16, height: 1.7)),
                                if (reply.isNotEmpty) ...[
                                  const Divider(height: 20),
                                  Text(
                                      q['published'] == true
                                          ? 'الجواب (منشور للجميع)'
                                          : 'الجواب (خاص بالسائل)',
                                      style: const TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(reply, style: const TextStyle(height: 1.7)),
                                ],
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    FilledButton.icon(
                                      icon: const Icon(Icons.reply, size: 18),
                                      label: Text(reply.isEmpty ? 'الرد' : 'تعديل الرد'),
                                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => ReplyScreen(
                                            id: d.id, question: text, oldReply: reply, chapter: chapter),
                                      )),
                                    ),
                                    if (_filter != 'hidden')
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.visibility_off_outlined, size: 18),
                                        label: const Text('إخفاء'),
                                        onPressed: () => cloud.setQuestionStatus(d.id, 'hidden'),
                                      )
                                    else ...[
                                      OutlinedButton.icon(
                                        icon: const Icon(Icons.undo, size: 18),
                                        label: const Text('إرجاع'),
                                        onPressed: () => cloud.setQuestionStatus(
                                            d.id, reply.isEmpty ? 'new' : 'answered'),
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                        label: const Text('حذف نهائي', style: TextStyle(color: Colors.red)),
                                        onPressed: () => cloud.deleteQuestion(d.id),
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.speed, size: 18),
                                        label: Text(cloud.askLimits.containsKey('${q['uid']}')
                                            ? 'حدّه اليومي: ${cloud.askLimits['${q['uid']}']}'
                                            : 'حدّه اليومي'),
                                        onPressed: () async {
                                          final uid = '${q['uid']}';
                                          final n = await showDialog<int>(
                                            context: context,
                                            builder: (ctx) => SimpleDialog(
                                              title: const Text('كم سؤالاً يُسمح لهذا السائل في اليوم؟'),
                                              children: [
                                                SimpleDialogOption(
                                                  onPressed: () => Navigator.pop(ctx, 0),
                                                  child: Text('مثل الجميع (${cloud.askLimit})'),
                                                ),
                                                for (final v in const [1, 2, 5, 10, 20, 50])
                                                  SimpleDialogOption(
                                                    onPressed: () => Navigator.pop(ctx, v),
                                                    child: Text('$v'),
                                                  ),
                                              ],
                                            ),
                                          );
                                          if (n == null) return;
                                          final err = await cloud.saveAsk(uid: uid, userLimit: n == 0 ? null : n);
                                          if (context.mounted) _toast(context, err ?? 'تم الحفظ ✅');
                                        },
                                      ),
                                      TextButton.icon(
                                        icon: const Icon(Icons.block, size: 18, color: Colors.red),
                                        label: const Text('حظر السائل', style: TextStyle(color: Colors.red)),
                                        onPressed: () async {
                                          await cloud.blockUser('${q['uid']}', text);
                                          if (context.mounted) _toast(context, 'حُظر السائل من إرسال الأسئلة');
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Write the reply, then choose: private reply, or publish for everyone.
class ReplyScreen extends StatefulWidget {
  final String id;
  final String question;
  final String oldReply;
  final String chapter;
  const ReplyScreen(
      {super.key, required this.id, required this.question, required this.oldReply, this.chapter = ''});

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  late final _reply = TextEditingController(text: widget.oldReply);
  final _title = TextEditingController();
  late String _chapter = Repository.instance.chapters.any((c) => c.id == widget.chapter)
      ? widget.chapter
      : Repository.instance.chapters.first.id;
  bool _publish = false;
  bool _busy = false;
  String _refId = '';

  /// Refer the asker to an answer that already exists in the app.
  void _pickExisting() {
    final repo = Repository.instance;
    var results = repo.similarToText(widget.question, limit: 8);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    decoration: _deco('ابحث عن الجواب الموجود'),
                    onChanged: (v) => setSheet(() => results = repo.search(v)),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final f in results)
                        ListTile(
                          title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('باب ${repo.chapterName(f.chapter)}'),
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _refId = f.id;
                              _publish = false;
                              _reply.text = 'جواب سؤالك موجود في التطبيق بعنوان:\n«${f.title}»';
                            });
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final err = await Cloud.instance.replyQuestion(
      widget.id,
      questionText: widget.question,
      reply: _reply.text,
      publish: _publish,
      chapter: _chapter,
      title: _title.text,
      refId: _refId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      _toast(context, err);
      return;
    }
    _toast(context, _publish ? 'أُرسل الرد ونُشر الجواب للجميع ✅' : 'أُرسل الرد إلى السائل ✅');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('الرد على السؤال')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SelectableText(widget.question, style: const TextStyle(fontSize: 16, height: 1.7)),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            icon: const Icon(Icons.link),
            label: Text(_refId.isEmpty ? 'إحالة إلى جواب موجود في التطبيق' : 'أُحيل إلى جواب موجود ✓'),
            onPressed: _pickExisting,
          ),
          const SizedBox(height: 10),
          TextField(controller: _reply, maxLines: 10, decoration: _deco('الجواب')),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('نشر السؤال والجواب في التطبيق'),
            subtitle: const Text('يراه الجميع، دون اسم السائل'),
            value: _publish,
            onChanged: (v) => setState(() => _publish = v),
          ),
          if (_publish) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(_chapter),
              value: _chapter,
              decoration: _deco('الباب'),
              items: [for (final c in repo.chapters) DropdownMenuItem(value: c.id, child: Text(c.name))],
              onChanged: (v) => setState(() => _chapter = v ?? _chapter),
            ),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: _deco('عنوان الجواب')),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_publish ? 'إرسال الرد ونشره' : 'إرسال رد خاص'),
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// Admin: pinned announcement on the home page.
class AnnouncementTab extends StatefulWidget {
  const AnnouncementTab({super.key});

  @override
  State<AnnouncementTab> createState() => _AnnouncementTabState();
}

class _AnnouncementTabState extends State<AnnouncementTab> {
  late final _text = TextEditingController(text: Cloud.instance.announcement);
  late final _schedule = TextEditingController(text: Cloud.instance.schedule);

  Future<void> _save(String text) async {
    final err = await Cloud.instance.setAnnouncement(text);
    if (!mounted) return;
    _toast(context, err ?? (text.trim().isEmpty ? 'أُزيل الإعلان' : 'نُشر الإعلان ✅'));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('يظهر هذا الإعلان في أعلى الصفحة الرئيسية لكل مستخدمي التطبيق.',
            style: TextStyle(height: 1.7)),
        const SizedBox(height: 12),
        TextField(controller: _text, maxLines: 4, maxLength: 300, decoration: _deco('نص الإعلان')),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.campaign),
          label: const Text('نشر الإعلان'),
          onPressed: () => _save(_text.text),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('إزالة الإعلان'),
          onPressed: () {
            _text.clear();
            _save('');
          },
        ),
        const Divider(height: 36),
        const Text('جدول دروس الشيخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('اكتب الأيام والأوقات والروابط. إن تركته فارغاً لا يظهر للناس.',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(controller: _schedule, maxLines: 6, decoration: _deco('الجدول')),
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: () async {
            final err = await Cloud.instance
                .setConfig('schedule', {'text': _schedule.text.trim()}, 'تعديل جدول الدروس');
            if (context.mounted) _toast(context, err ?? 'حُفظ الجدول ✅');
          },
          child: const Text('حفظ الجدول'),
        ),
        if (Cloud.instance.isDeveloper) ...[
          const Divider(height: 36),
          const Text('التحديث الإجباري (للمطوّر)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(
              Cloud.instance.minBuild > 0
                  ? 'مفعّل: كل نسخة أقدم من البناء رقم ${Cloud.instance.minBuild} يُطلب من صاحبها التحديث.'
                  : 'غير مفعّل: كل النسخ القديمة تعمل.',
              style: const TextStyle(height: 1.7)),
          const SizedBox(height: 8),
          if (AppConfig.buildNumber > 0)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.system_update),
              label: Text('ألزِم الجميع بهذه النسخة (${AppConfig.version}) أو أحدث'),
              onPressed: () async {
                final err = await Cloud.instance.setConfig(
                    'app', {'minBuild': AppConfig.buildNumber}, 'تفعيل التحديث الإجباري');
                if (!context.mounted) return;
                _toast(context, err ?? 'فُعّل التحديث الإجباري ✅');
                setState(() {});
              },
            ),
          if (Cloud.instance.minBuild > 0)
            TextButton(
              onPressed: () async {
                final err = await Cloud.instance
                    .setConfig('app', {'minBuild': 0}, 'إلغاء التحديث الإجباري');
                if (!context.mounted) return;
                _toast(context, err ?? 'أُلغي التحديث الإجباري');
                setState(() {});
              },
              child: const Text('إلغاء التحديث الإجباري'),
            ),
        ],
      ],
    );
  }
}

/// Admin: what people searched for and did not find.
class MissesTab extends StatefulWidget {
  const MissesTab({super.key});

  @override
  State<MissesTab> createState() => _MissesTabState();
}

class _MissesTabState extends State<MissesTab> {
  late Future<List<(String, int)>> _future = Cloud.instance.topMisses();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return const EmptyState(
              icon: Icons.search_off, text: 'لا توجد كلمات بعد.\nتظهر هنا الكلمات التي بحث عنها الناس ولم يجدوا لها جواباً.');
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) {
            final (term, count) = items[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: kGold.withValues(alpha: 0.2),
                child: Text('$count', style: const TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
              ),
              title: Text(term),
              subtitle: const Text('مرات البحث دون نتيجة'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'اربطها بكلمة موجودة',
                    icon: const Icon(Icons.link),
                    onPressed: () async {
                      final c = TextEditingController();
                      final target = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('اربط «$term» بكلمة'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('اكتب الكلمة التي توجد في الأجوبة، فمن بحث بـ«الحواجب» مثلاً يجد أجوبة «النمص».',
                                  style: TextStyle(color: Colors.grey)),
                              const SizedBox(height: 8),
                              TextField(controller: c, autofocus: true, decoration: _deco('الكلمة')),
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('ربط')),
                          ],
                        ),
                      );
                      if (target == null || target.trim().isEmpty) return;
                      final err = await Cloud.instance.addSynonym(term, target);
                      if (err == null) await Cloud.instance.clearMiss(term);
                      if (!context.mounted) return;
                      _toast(context, err ?? 'رُبطت ✅ صار البحث بها يجد الأجوبة');
                      setState(() => _future = Cloud.instance.topMisses());
                    },
                  ),
                  IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  await Cloud.instance.clearMiss(term);
                  setState(() => _future = Cloud.instance.topMisses());
                },
              ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Admin: full edit (or delete) of an answer that was published in-app.
class EditAnswerScreen extends StatefulWidget {
  final Fatwa fatwa;
  const EditAnswerScreen({super.key, required this.fatwa});

  @override
  State<EditAnswerScreen> createState() => _EditAnswerScreenState();
}

class _EditAnswerScreenState extends State<EditAnswerScreen> {
  late final _title = TextEditingController(text: widget.fatwa.title);
  late final _question = TextEditingController(text: widget.fatwa.question);
  late final _answer = TextEditingController(text: widget.fatwa.answer);
  late String _chapter = widget.fatwa.chapter;
  late final _tags = TextEditingController(text: widget.fatwa.tags.join('، '));
  late final _audio = TextEditingController(text: widget.fatwa.audio);
  late String _sub = widget.fatwa.sub;

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final chapterIds = repo.chapters.map((c) => c.id).toSet();
    if (!chapterIds.contains(_chapter)) _chapter = repo.chapters.first.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل الجواب'),
        actions: [
          IconButton(
            tooltip: 'حذف الجواب',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('حذف الجواب؟'),
                  content: const Text('يُحذف من التطبيق عند الجميع، ويبقى في سلة المحذوفات 30 يوماً يمكن استرجاعه فيها.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                  ],
                ),
              );
              if (ok != true) return;
              final err = await Cloud.instance.deleteAnswer(widget.fatwa.id);
              if (!context.mounted) return;
              _toast(context, err ?? 'حُذف الجواب');
              if (err == null) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _chapter,
            decoration: _deco('الباب (للنقل إلى باب آخر)'),
            items: [for (final c in repo.chapters) DropdownMenuItem(value: c.id, child: Text(c.name))],
            onChanged: (v) => setState(() {
              _chapter = v ?? _chapter;
              _sub = '';
            }),
          ),
          SubPicker(chapterId: _chapter, value: _sub, onChanged: (v) => setState(() => _sub = v)),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: _deco('العنوان')),
          const SizedBox(height: 12),
          TextField(controller: _question, maxLines: 3, decoration: _deco('السؤال')),
          const SizedBox(height: 12),
          TextField(controller: _answer, maxLines: 12, decoration: _deco('الجواب')),
          const SizedBox(height: 12),
          TextField(controller: _tags, decoration: _deco('الوسوم (افصل بينها بفاصلة)')),
          const SizedBox(height: 12),
          TextField(
            controller: _audio,
            textDirection: TextDirection.ltr,
            decoration: _deco('رابط تسجيل صوتي للجواب (اختياري)'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.save),
            label: const Text('حفظ التعديل'),
            onPressed: () async {
              final err = await Cloud.instance.updateAnswer(
                widget.fatwa.id,
                chapter: _chapter,
                title: _title.text,
                question: _question.text,
                answer: _answer.text,
                tags: parseTags(_tags.text),
                sub: _sub,
                audio: _audio.text,
              );
              if (!context.mounted) return;
              _toast(context, err ?? 'تم الحفظ ✅');
              if (err == null) Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
    );
  }
}

/// Admin: add an answer to a series, or start a new series with it.
void showSeriesSheet(BuildContext context, Fatwa fatwa) {
  final newTitle = TextEditingController();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ListenableBuilder(
        listenable: Cloud.instance,
        builder: (ctx, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          children: [
            const Text('إضافة الجواب إلى سلسلة أو مسار',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final s in Cloud.instance.series)
              ListTile(
                leading: Icon(s.track ? Icons.route_outlined : Icons.collections_bookmark_outlined, color: kGold),
                title: Text(s.title),
                subtitle: Text('${s.track ? 'مسار' : 'سلسلة'} · ${s.ids.length} جواب'),
                trailing: s.ids.contains(fatwa.id) ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () async {
                  final err = await Cloud.instance.addToSeries(s.id, fatwa.id);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _toast(context, err ?? 'أُضيف إلى «${s.title}» ✅');
                },
              ),
            const Divider(),
            TextField(controller: newTitle, decoration: _deco('العنوان، مثل: أحكام رمضان')),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final err = await Cloud.instance.createSeries(newTitle.text, fatwa.id);
                if (!ctx.mounted) return;
                if (err == null) Navigator.pop(ctx);
                _toast(context, err ?? 'أُنشئت السلسلة ✅');
              },
              child: const Text('إنشاء سلسلة وإضافة الجواب'),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              icon: const Icon(Icons.route_outlined),
              onPressed: () async {
                final err = await Cloud.instance.createSeries(newTitle.text, fatwa.id, track: true);
                if (!ctx.mounted) return;
                if (err == null) Navigator.pop(ctx);
                _toast(context, err ?? 'أُنشئ المسار ✅');
              },
              label: const Text('إنشاء مسار تعليمي وإضافة الجواب'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('المسار: أجوبة مرتبة يتابعها القارئ خطوة خطوة، مثل «أحكام الصلاة للمبتدئ».',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
        ),
      ),
    ),
  );
}


/// Full admin: the sub-chapters of one chapter.
void showSubsSheet(BuildContext context, Chapter chapter) {
  final c = TextEditingController();
  var names = [...?Cloud.instance.subs[chapter.id]];
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        Future<void> save(List<String> list) async {
          final err = await Cloud.instance.setSubs(chapter.id, list);
          if (err == null) setS(() => names = list);
          if (context.mounted) _toast(context, err ?? 'تم الحفظ ✅');
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            children: [
              Text('الأبواب الفرعية في «${chapter.name}»',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('مثل: الأذان، الجمعة، صلاة المسافر. ثم تختار الباب الفرعي عند نشر الجواب أو تعديله.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              for (final n in names)
                ListTile(
                  leading: const Icon(Icons.subdirectory_arrow_left, color: kGold),
                  title: Text(n),
                  trailing: IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => save([...names]..remove(n)),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(controller: c, decoration: _deco('باب فرعي جديد')),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('إضافة'),
                onPressed: () {
                  final n = c.text.trim();
                  if (n.isEmpty || names.contains(n)) return;
                  c.clear();
                  save([...names, n]);
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Full admin: rename chapters and add new ones.
/// Saves the chapters settings: names, added chapters and chosen icons.
Future<void> saveChapters(BuildContext context, Map<String, String> names, List<Chapter> extra, String log,
    [Map<String, String>? icons]) async {
  final err = await Cloud.instance.setConfig(
    'chapters',
    {
      'names': names,
      'extra': [for (final c in extra) {'id': c.id, 'name': c.name}],
      'icons': icons ?? Repository.instance.chapterIconChoice,
    },
    log,
  );
  if (context.mounted) _toast(context, err ?? 'تم الحفظ ✅');
}

/// «باب جديد» with a name and an icon; used in the admin panel and while reviewing.
Future<void> addChapterDialog(BuildContext context) async {
  final repo = Repository.instance;
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('باب جديد'),
      content: TextField(controller: c, autofocus: true, decoration: _deco('اسم الباب')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('التالي: الرمز')),
      ],
    ),
  );
  if (name == null || name.isEmpty || !context.mounted) return;
  final icon = await pickChapterIcon(context);
  if (!context.mounted) return;
  final id = 'c${DateTime.now().millisecondsSinceEpoch}';
  final extra = repo.chapters.where((e) => !repo.isBaseChapter(e.id)).toList();
  final names = {for (final e in repo.chapters.where((e) => repo.isBaseChapter(e.id))) e.id: e.name};
  await saveChapters(
    context,
    names,
    [...extra, Chapter(id: id, name: name, icon: 'mutafarriq')],
    'إضافة باب',
    {...repo.chapterIconChoice, if (icon != null) id: icon},
  );
}

class ChaptersTab extends StatelessWidget {
  const ChaptersTab({super.key});

  Future<void> _save(BuildContext context, Map<String, String> names, List<Chapter> extra, String log,
          [Map<String, String>? icons]) =>
      saveChapters(context, names, extra, log, icons);

  Future<String?> _askName(BuildContext context, String title, String initial) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: _deco('اسم الباب')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final extra = repo.chapters.where((c) => !repo.isBaseChapter(c.id)).toList();
        final names = {for (final c in repo.chapters.where((c) => repo.isBaseChapter(c.id))) c.id: c.name};
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            for (final c in repo.chapters)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: Icon(chapterIcon(c.icon), color: kGold),
                  title: Text(c.name),
                  subtitle: Text('${repo.countInChapter(c.id)} مادة'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'الأبواب الفرعية',
                        icon: Badge(
                          isLabelVisible: (Cloud.instance.subs[c.id] ?? const []).isNotEmpty,
                          label: Text('${(Cloud.instance.subs[c.id] ?? const []).length}'),
                          child: const Icon(Icons.account_tree_outlined),
                        ),
                        onPressed: () => showSubsSheet(context, c),
                      ),
                      IconButton(
                        tooltip: 'تغيير الرمز',
                        icon: const Icon(Icons.emoji_symbols_outlined),
                        onPressed: () async {
                          final icon = await pickChapterIcon(context);
                          if (icon == null || !context.mounted) return;
                          await _save(context, names, extra, 'تغيير رمز باب', {...repo.chapterIconChoice, c.id: icon});
                        },
                      ),
                      IconButton(
                        tooltip: 'تغيير الاسم',
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final n = await _askName(context, 'تغيير اسم الباب', c.name);
                          if (n == null || n.isEmpty || !context.mounted) return;
                          if (repo.isBaseChapter(c.id)) {
                            names[c.id] = n;
                            await _save(context, names, extra, 'تغيير اسم باب');
                          } else {
                            final list = [
                              for (final e in extra)
                                e.id == c.id ? Chapter(id: e.id, name: n, icon: e.icon) : e,
                            ];
                            await _save(context, names, list, 'تغيير اسم باب');
                          }
                        },
                      ),
                      if (!repo.isBaseChapter(c.id))
                        IconButton(
                          tooltip: 'حذف الباب',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () {
                            if (repo.countInChapter(c.id) > 0) {
                              _toast(context, 'انقل أجوبة هذا الباب إلى باب آخر أولاً');
                              return;
                            }
                            _save(context, names, extra.where((e) => e.id != c.id).toList(), 'حذف باب');
                          },
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('إضافة باب جديد'),
              onPressed: () => addChapterDialog(context),
            ),
          ],
        );
      },
    );
  }
}

/// Full admin: the «عن الشيخ» text and the sheikh's accounts.
class AboutTab extends StatefulWidget {
  const AboutTab({super.key});

  @override
  State<AboutTab> createState() => _AboutTabState();
}

class _AboutTabState extends State<AboutTab> {
  late final _about = TextEditingController(text: Cloud.instance.aboutText);
  final _name = TextEditingController();
  final _url = TextEditingController();
  String _platform = 'telegram';

  static const _platforms = {
    'telegram': 'تليجرام',
    'whatsapp': 'واتساب',
    'youtube': 'يوتيوب',
    'facebook': 'فيسبوك',
    'x': 'إكس',
    'audio': 'صوتيات',
    'group': 'مجموعة',
    'link': 'رابط آخر',
  };

  Future<void> _saveLinks(List<SocialLink> links) async {
    final err = await Cloud.instance.setConfig(
      'links',
      {
        'items': [for (final l in links) {'platform': l.platform, 'name': l.name, 'url': l.url}],
      },
      'تعديل حسابات الشيخ',
    );
    if (mounted) _toast(context, err ?? 'تم الحفظ ✅');
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('نص صفحة «عن الشيخ»', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _about, maxLines: 8, decoration: _deco('التعريف بالشيخ')),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('حفظ النص'),
            onPressed: () async {
              final err = await Cloud.instance
                  .setConfig('about', {'text': _about.text.trim()}, 'تعديل صفحة عن الشيخ');
              if (context.mounted) _toast(context, err ?? 'تم الحفظ ✅');
            },
          ),
          const Divider(height: 36),
          const Text('حسابات الشيخ', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          for (final l in repo.sheikhLinks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(platformIcon(l.platform), color: kGold),
              title: Text(l.name),
              subtitle: Text(l.url, textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _saveLinks(repo.sheikhLinks.where((e) => e != l).toList()),
              ),
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _platform,
            decoration: _deco('النوع'),
            items: [for (final e in _platforms.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _platform = v ?? _platform),
          ),
          const SizedBox(height: 10),
          TextField(controller: _name, decoration: _deco('الاسم الظاهر')),
          const SizedBox(height: 10),
          TextField(controller: _url, textDirection: TextDirection.ltr, decoration: _deco('الرابط')),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.add_link),
            label: const Text('إضافة حساب'),
            onPressed: () {
              if (_name.text.trim().isEmpty || !_url.text.trim().startsWith('http')) {
                _toast(context, 'اكتب الاسم ورابطاً يبدأ بـ https');
                return;
              }
              final list = [
                ...repo.sheikhLinks,
                SocialLink(platform: _platform, name: _name.text.trim(), url: _url.text.trim()),
              ];
              _name.clear();
              _url.clear();
              _saveLinks(list);
            },
          ),
        ],
      ),
    );
  }
}

/// Developer only: who did what, and when.
class LogTab extends StatelessWidget {
  const LogTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Cloud.instance.logStream(),
      builder: (context, snap) {
        if (snap.hasError) return const EmptyState(icon: Icons.error_outline, text: 'تعذّر تحميل السجل');
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const EmptyState(icon: Icons.history, text: 'السجل فارغ');
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final at = d['at'];
            final when = at is Timestamp ? at.toDate().toLocal().toString().substring(0, 16) : '';
            final target = '${d['target'] ?? ''}';
            return ListTile(
              dense: true,
              leading: const Icon(Icons.history, color: kGold),
              title: Text('${d['action'] ?? ''}${target.isEmpty ? '' : ': $target'}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${d['by'] ?? ''} · $when', textDirection: TextDirection.ltr),
            );
          },
        );
      },
    );
  }
}


/// Developer only: what one staff member did, and when they came in.
class StaffActivityScreen extends StatefulWidget {
  final String email;
  const StaffActivityScreen({super.key, required this.email});

  @override
  State<StaffActivityScreen> createState() => _StaffActivityScreenState();
}

class _StaffActivityScreenState extends State<StaffActivityScreen> {
  late Future<List<Map<String, dynamic>>> _future = Cloud.instance.activityOf(widget.email);
  String _filter = '';

  static String when(DateTime t) {
    final d = DateTime.now().difference(t);
    String ago;
    if (d.inMinutes < 1) {
      ago = 'الآن';
    } else if (d.inMinutes < 60) {
      ago = 'قبل ${d.inMinutes} د';
    } else if (d.inHours < 24) {
      ago = 'قبل ${d.inHours} س';
    } else {
      ago = 'قبل ${d.inDays} يوم';
    }
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$ago · ${t.day}/${t.month}/${t.year} $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'ص' : 'م'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('نشاط المشرف')),
      body: FutureBuilder(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return const EmptyState(icon: Icons.error_outline, text: 'تعذّر التحميل');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          DateTime? at(Map<String, dynamic> m) =>
              m['at'] is Timestamp ? (m['at'] as Timestamp).toDate().toLocal() : null;
          final visits = all.where((m) => m['action'] == 'دخول').toList();
          final work = all.where((m) => m['action'] != 'دخول').toList();
          final counts = <String, int>{};
          for (final m in work) {
            final a = '${m['action'] ?? ''}';
            counts[a] = (counts[a] ?? 0) + 1;
          }
          final weekAgo = DateTime.now().subtract(const Duration(days: 7));
          final visitsWeek = visits.where((m) => at(m)?.isAfter(weekAgo) ?? false).length;
          final fromApp = visits.where((m) => m['target'] == 'التطبيق').length;
          final fromSite = visits.where((m) => m['target'] == 'الموقع').length;
          final lastVisit = visits.isEmpty ? null : at(visits.first);
          final lastWork = work.isEmpty ? null : at(work.first);
          final shown = _filter.isEmpty ? all : all.where((m) => m['action'] == _filter).toList();

          Widget stat(IconData icon, String label, String value) => Expanded(
                child: Card(
                  margin: const EdgeInsets.all(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    child: Column(children: [
                      Icon(icon, color: kGold),
                      const SizedBox(height: 4),
                      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ),
                ),
              );

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = Cloud.instance.activityOf(widget.email));
              await _future;
            },
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(widget.email,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.login, color: kGold, size: 20),
                          const SizedBox(width: 6),
                          Expanded(child: Text('آخر دخول: ${lastVisit == null ? 'لم يدخل بعد' : when(lastVisit)}')),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.edit_note, color: kGold, size: 20),
                          const SizedBox(width: 6),
                          Expanded(child: Text('آخر عمل: ${lastWork == null ? 'لا يوجد' : when(lastWork)}')),
                        ]),
                      ],
                    ),
                  ),
                ),
                Row(children: [
                  stat(Icons.login, 'مرات الدخول', '${visits.length}'),
                  stat(Icons.date_range, 'دخول هذا الأسبوع', '$visitsWeek'),
                  stat(Icons.task_alt, 'الأعمال', '${work.length}'),
                ]),
                Row(children: [
                  stat(Icons.phone_android, 'من التطبيق', '$fromApp'),
                  stat(Icons.language, 'من الموقع', '$fromSite'),
                ]),
                if (counts.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
                    child: Text('ماذا عمل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: Text('الكل (${all.length})'),
                        selected: _filter.isEmpty,
                        onSelected: (_) => setState(() => _filter = ''),
                      ),
                      ChoiceChip(
                        label: Text('الدخول (${visits.length})'),
                        selected: _filter == 'دخول',
                        onSelected: (_) => setState(() => _filter = 'دخول'),
                      ),
                      for (final e in (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                        ChoiceChip(
                          label: Text('${e.key} (${e.value})'),
                          selected: _filter == e.key,
                          onSelected: (_) => setState(() => _filter = e.key),
                        ),
                    ],
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
                  child: Text('السجل التفصيلي', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا شيء بعد', style: TextStyle(color: Colors.grey)),
                  ),
                for (final m in shown.take(300))
                  ListTile(
                    dense: true,
                    leading: Icon(m['action'] == 'دخول' ? Icons.login : Icons.history, color: kGold),
                    title: Text('${m['action'] ?? ''}${'${m['target'] ?? ''}'.isEmpty ? '' : ': ${m['target']}'}',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(at(m) == null ? '' : when(at(m)!)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}


/// Staff: correct an answer that came with the app (from the channel):
/// its title, chapter, and the place where the question ends and the
/// answer begins. Saving also marks it as checked.
Future<void> showBundledEdit(BuildContext context, Fatwa f) async {
  final repo = Repository.instance;
  final title = TextEditingController(text: f.title);
  final question = TextEditingController(text: f.question);
  final answer = TextEditingController(text: f.answer);
  var chapter = repo.chapters.any((x) => x.id == f.chapter) ? f.chapter : repo.chapters.last.id;
  var sub = f.sub;
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Scaffold(
        appBar: AppBar(title: const Text('تصحيح الجواب')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(controller: title, maxLines: 2, decoration: _deco('العنوان')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: chapter,
              isExpanded: true,
              decoration: _deco('الباب'),
              items: [for (final x in repo.chapters) DropdownMenuItem(value: x.id, child: Text(x.name))],
              onChanged: (v) => setS(() {
                chapter = v ?? chapter;
                sub = '';
              }),
            ),
            SubPicker(chapterId: chapter, value: sub, onChanged: (v) => setS(() => sub = v)),
            const SizedBox(height: 12),
            TextField(controller: question, maxLines: 5, decoration: _deco('السؤال (اتركه فارغاً إن كان مقالاً)')),
            const SizedBox(height: 12),
            TextField(controller: answer, maxLines: 14, decoration: _deco('الجواب')),
            const SizedBox(height: 6),
            const Text('انقل الكلام بين الخانتين إن كان التقسيم خطأ. لا تحذف من كلام الشيخ شيئاً.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.verified),
              label: const Text('حفظ وتحقّق'),
              onPressed: () async {
                if (answer.text.trim().isEmpty) {
                  _toast(ctx, 'خانة الجواب فارغة');
                  return;
                }
                final changed = question.text.trim() != f.question.trim() || answer.text.trim() != f.answer.trim();
                final err = await Cloud.instance.editBundled(f.id,
                    title: title.text,
                    chapter: chapter,
                    sub: sub,
                    question: changed ? question.text : null,
                    answer: changed ? answer.text : null);
                if (!ctx.mounted) return;
                _toast(ctx, err ?? 'تم الحفظ ✅');
                if (err == null) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  ));
}
