import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'admin_extra.dart';

/// Staff: go through the answers of one chapter (by default «متفرقات»)
/// one by one, and send each to its right chapter with a single tap.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  late String _from = Repository.instance.chapters.last.id; // '' = all chapters
  final _skipped = <String>{};
  bool _busy = false;
  bool _verifiedTab = false;

  List<Fatwa> get _pool {
    final repo = Repository.instance;
    return _from.isEmpty ? repo.fatwas : repo.byChapter(_from);
  }

  List<Fatwa> get _verified {
    final ids = Repository.instance.verifiedIds;
    return _pool.where((f) => ids.contains(f.id)).toList();
  }

  List<Fatwa> get _queue {
    final repo = Repository.instance;
    return _pool.where((f) => !_skipped.contains(f.id) && !repo.verifiedIds.contains(f.id)).toList();
  }

  Future<void> _act(Future<String?> Function() job, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await job();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(duration: const Duration(seconds: 1), content: Text(err ?? ok)));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Repository.instance,
        builder: (context, _) => _build(context),
      );

  Widget _tabButton(String label, int count, IconData icon, Color color, bool on, VoidCallback tap) => Expanded(
        child: Material(
          color: on ? color.withValues(alpha: .14) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: on ? color : Colors.grey.withValues(alpha: .35), width: on ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.bold, color: on ? color : null)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('$count',
                      style: TextStyle(fontFamily: 'Tajawal', fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _build(BuildContext context) {
    final repo = Repository.instance;
    final queue = _queue;
    final verified = _verified;
    final f = _verifiedTab || queue.isEmpty ? null : queue.first;
    return Scaffold(
      appBar: AppBar(title: const Text('المتحقق منه وغير المتحقق منه')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              _tabButton('غير المتحقق منه', queue.length, Icons.pending_actions_outlined, const Color(0xFFC0392B),
                  !_verifiedTab, () => setState(() => _verifiedTab = false)),
              const SizedBox(width: 10),
              _tabButton('المتحقق منه', verified.length, Icons.verified_outlined, const Color(0xFF2E8B57),
                  _verifiedTab, () => setState(() => _verifiedTab = true)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: DropdownButtonFormField<String>(
              value: _from,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'أراجع منشورات باب', border: OutlineInputBorder(), isDense: true),
              items: [
                const DropdownMenuItem(value: '', child: Text('كل الأبواب')),
                for (final c in repo.chapters)
                  DropdownMenuItem(value: c.id, child: Text('${c.name} (${repo.countInChapter(c.id)})')),
              ],
              onChanged: (v) => setState(() {
                _from = v ?? _from;
                _skipped.clear();
              }),
            ),
          ),
          if (_verifiedTab)
            Expanded(
              child: verified.isEmpty
                  ? const EmptyState(icon: Icons.verified_outlined, text: 'لم يُتحقق من شيء في هذا الباب بعد.')
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: verified.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final v = verified[i];
                        return ListTile(
                          leading: const Icon(Icons.verified, color: Color(0xFF2E8B57)),
                          title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(repo.chapterName(v.chapter), style: const TextStyle(fontSize: 12)),
                          onTap: () => openFatwa(context, v),
                          trailing: TextButton(
                            onPressed: _busy
                                ? null
                                : () => _act(() => Cloud.instance.setVerified(v.id, false, v.title),
                                    'أُعيد إلى غير المتحقق منه'),
                            child: const Text('إلغاء التحقق', style: TextStyle(fontSize: 12)),
                          ),
                        );
                      },
                    ),
            )
          else
          Expanded(
            child: f == null
                ? const EmptyState(icon: Icons.task_alt, text: 'لا شيء يحتاج مراجعة في هذا الباب.')
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      Text(f.title,
                          style: const TextStyle(
                              fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17, height: 1.6)),
                      const SizedBox(height: 8),
                      if (f.question.isNotEmpty) ...[
                        Text(f.question, style: const TextStyle(color: kGoldChip, height: 1.8)),
                        const Divider(),
                      ],
                      Text(f.answer, style: const TextStyle(height: 1.9, fontSize: 16)),
                    ],
                  ),
          ),
          if (f != null)
            Material(
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('اختر بابه الصحيح', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        alignment: WrapAlignment.center,
                        children: [
                          for (final c in repo.chapters)
                            if (c.id != f.chapter)
                              ActionChip(
                                avatar: Icon(chapterIcon(c.icon), size: 16, color: kGold),
                                label: Text(c.name),
                                onPressed: _busy
                                    ? null
                                    : () => _act(
                                        () => Cloud.instance.setChapter(f.id, c.id, f.title), 'نُقل إلى ${c.name} ✅'),
                              ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16, color: Colors.green),
                            label: const Text('باب جديد'),
                            onPressed: () => addChapterDialog(context),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.check),
                              label: const Text('صحيح'),
                              onPressed: _busy
                                  ? null
                                  : () => _act(() => Cloud.instance.setVerified(f.id, true, f.title), 'تم التحقق ✅'),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('تصحيح'),
                              onPressed: () async {
                                await showBundledEdit(context, f);
                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.skip_next),
                              label: const Text('تخطٍّ'),
                              onPressed: () => setState(() => _skipped.add(f.id)),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              icon: const Icon(Icons.visibility_off_outlined, color: Colors.red),
                              label: const Text('إخفاء', style: TextStyle(color: Colors.red)),
                              onPressed: _busy
                                  ? null
                                  : () => _act(() => Cloud.instance.setHidden(f.id, true, f.title), 'أُخفي من التطبيق'),
                            ),
                          ),
                        ],
                      ),
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

/// Staff: answers hidden from the app, with a button to show them again.
class HiddenScreen extends StatelessWidget {
  const HiddenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('المنشورات المخفية')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final items = repo.hidden;
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.visibility_outlined, text: 'لا توجد منشورات مخفية.');
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => ListTile(
              leading: const Icon(Icons.visibility_off_outlined, color: Colors.grey),
              title: Text(items[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: TextButton(
                onPressed: () => Cloud.instance.setHidden(items[i].id, false, items[i].title),
                child: const Text('إظهار'),
              ),
            ),
          );
        },
      ),
    );
  }
}
