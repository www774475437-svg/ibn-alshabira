import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';

void _toast(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

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
  String _filter = 'new'; // new | answered | hidden

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'new', label: Text('جديدة')),
              ButtonSegment(value: 'answered', label: Text('أُجيب عنها')),
              ButtonSegment(value: 'hidden', label: Text('مخفية')),
            ],
            selected: {_filter},
            onSelectionChanged: (s) => setState(() => _filter = s.first),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Cloud.instance.allQuestions(),
            builder: (context, snap) {
              if (snap.hasError) {
                return const EmptyState(icon: Icons.error_outline, text: 'تعذّر تحميل الأسئلة');
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs.where((d) => (d.data()['status'] ?? 'new') == _filter).toList();
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
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText('${q['text'] ?? ''}',
                              style: const TextStyle(fontSize: 16, height: 1.7)),
                          if (reply.isNotEmpty) ...[
                            const Divider(height: 20),
                            Text(q['published'] == true ? 'الجواب (منشور للجميع)' : 'الجواب (خاص بالسائل)',
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
                                  builder: (_) => ReplyScreen(id: d.id, question: '${q['text'] ?? ''}', oldReply: reply),
                                )),
                              ),
                              if (_filter != 'hidden')
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.visibility_off_outlined, size: 18),
                                  label: const Text('إخفاء'),
                                  onPressed: () => Cloud.instance.setQuestionStatus(d.id, 'hidden'),
                                )
                              else ...[
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.undo, size: 18),
                                  label: const Text('إرجاع'),
                                  onPressed: () => Cloud.instance
                                      .setQuestionStatus(d.id, reply.isEmpty ? 'new' : 'answered'),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  label: const Text('حذف نهائي', style: TextStyle(color: Colors.red)),
                                  onPressed: () => Cloud.instance.deleteQuestion(d.id),
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
  const ReplyScreen({super.key, required this.id, required this.question, required this.oldReply});

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  late final _reply = TextEditingController(text: widget.oldReply);
  final _title = TextEditingController();
  String _chapter = Repository.instance.chapters.first.id;
  bool _publish = false;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    final err = await Cloud.instance.replyQuestion(
      widget.id,
      questionText: widget.question,
      reply: _reply.text,
      publish: _publish,
      chapter: _chapter,
      title: _title.text,
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
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  await Cloud.instance.clearMiss(term);
                  setState(() => _future = Cloud.instance.topMisses());
                },
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
                  content: const Text('يُحذف من التطبيق عند الجميع، ولا يمكن التراجع.'),
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
            onChanged: (v) => setState(() => _chapter = v ?? _chapter),
          ),
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: _deco('العنوان')),
          const SizedBox(height: 12),
          TextField(controller: _question, maxLines: 3, decoration: _deco('السؤال')),
          const SizedBox(height: 12),
          TextField(controller: _answer, maxLines: 12, decoration: _deco('الجواب')),
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
            const Text('إضافة الجواب إلى سلسلة',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final s in Cloud.instance.series)
              ListTile(
                leading: const Icon(Icons.collections_bookmark_outlined, color: kGold),
                title: Text(s.title),
                subtitle: Text('${s.ids.length} جواب'),
                trailing: s.ids.contains(fatwa.id) ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () async {
                  final err = await Cloud.instance.addToSeries(s.id, fatwa.id);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _toast(context, err ?? 'أُضيف إلى «${s.title}» ✅');
                },
              ),
            const Divider(),
            TextField(controller: newTitle, decoration: _deco('سلسلة جديدة، مثل: أحكام رمضان')),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final err = await Cloud.instance.createSeries(newTitle.text, fatwa.id);
                if (!ctx.mounted) return;
                if (err == null) Navigator.pop(ctx);
                _toast(context, err ?? 'أُنشئت السلسلة ✅');
              },
              child: const Text('إنشاء السلسلة وإضافة الجواب'),
            ),
          ],
        ),
      ),
    ),
  );
}
