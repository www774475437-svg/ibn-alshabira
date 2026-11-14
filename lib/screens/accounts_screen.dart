import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// «قنوات وحسابات»: the sheikh's official accounts, then the accounts the
/// sheikh or the admins add for other scholars and people, each with its
/// owner's name, a note about him, and as many links as needed.
class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  static const platforms = <String, String>{
    'telegram': 'تيليجرام',
    'youtube': 'يوتيوب',
    'whatsapp': 'واتساب',
    'facebook': 'فيسبوك',
    'x': 'إكس',
    'instagram': 'إنستغرام',
    'tiktok': 'تيك توك',
    'snapchat': 'سناب شات',
    'audio': 'صوتيات',
    'group': 'مجموعة',
    'link': 'موقع أو رابط آخر',
  };

  static Future<void> _save(BuildContext context, List<Map<String, dynamic>> people, String log) async {
    final err = await Cloud.instance.setConfig('accounts', {'people': people}, log);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'تم الحفظ ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([cloud, repo]),
      builder: (context, _) {
        final people = cloud.accounts;
        final canEdit = cloud.ready && cloud.isFullAdmin;
        return Scaffold(
          appBar: AppBar(title: const Text('قنوات وحسابات أنصح بها')),
          floatingActionButton: canEdit
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('إضافة شيخ أو قناة'),
                  onPressed: () async {
                    final p = await Navigator.of(context).push<Map<String, dynamic>>(
                        MaterialPageRoute(builder: (_) => const _PersonEditor()));
                    if (p != null && context.mounted) await _save(context, [...people, p], 'إضافة صاحب حساب');
                  },
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
            children: [
              _PersonCard(
                name: 'الشيخ قايد بن غانم الشابرة',
                about: 'الحسابات الرسمية للشيخ',
                links: [
                  for (final l in repo.sheikhLinks) {'platform': l.platform, 'name': l.name, 'url': l.url},
                ],
                highlight: true,
                // The sheikh or an admin adds another account of the sheikh's own here.
                onEdit: canEdit
                    ? () async {
                        final p = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(
                            builder: (_) => _PersonEditor(
                                  sheikh: true,
                                  person: {
                                    'name': 'الشيخ قايد بن غانم الشابرة',
                                    'links': [
                                      for (final l in repo.sheikhLinks)
                                        {'platform': l.platform, 'name': l.name, 'url': l.url},
                                    ],
                                  },
                                )));
                        if (p == null || !context.mounted) return;
                        final err = await cloud.setConfig(
                          'links',
                          {
                            'items': [
                              for (final l in (p['links'] ?? []) as List)
                                {'platform': l['platform'], 'name': l['name'], 'url': l['url']},
                            ],
                          },
                          'تعديل حسابات الشيخ',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'تم الحفظ ✅')));
                        }
                      }
                    : null,
              ),
              // The heading of what the sheikh recommends.
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFFB3261E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.recommend_outlined, color: Colors.white),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('قنوات وحسابات مشايخ أنصح بها',
                          style: TextStyle(
                              fontFamily: 'Tajawal', color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < people.length; i++)
                _PersonCard(
                  name: '${people[i]['name'] ?? ''}',
                  title: '${people[i]['title'] ?? ''}',
                  about: '${people[i]['about'] ?? ''}',
                  links: [for (final l in (people[i]['links'] ?? []) as List) Map<String, dynamic>.from(l as Map)],
                  onEdit: canEdit
                      ? () async {
                          final p = await Navigator.of(context).push<Map<String, dynamic>>(
                              MaterialPageRoute(builder: (_) => _PersonEditor(person: people[i])));
                          if (p == null || !context.mounted) return;
                          final next = [...people];
                          if (p['_delete'] == true) {
                            next.removeAt(i);
                          } else {
                            next[i] = p;
                          }
                          await _save(context, next, p['_delete'] == true ? 'حذف صاحب حساب' : 'تعديل صاحب حساب');
                        }
                      : null,
                ),
              if (people.isEmpty && canEdit)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('اضغط «إضافة شيخ أو قناة» لتضيف شيخاً أو طالب علم مع حساباته.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PersonCard extends StatelessWidget {
  final String name;
  final String title;
  final String about;
  final List<Map<String, dynamic>> links;
  final bool highlight;
  final VoidCallback? onEdit;
  const _PersonCard(
      {required this.name,
      this.title = '',
      this.about = '',
      required this.links,
      this.highlight = false,
      this.onEdit});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: highlight ? const BorderSide(color: kGold, width: 1.5) : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onEdit,
                child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: kGold.withValues(alpha: 0.18),
                    child: Icon(Icons.person_outline, color: kGoldChip),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                        if (title.isNotEmpty) Text(title, style: TextStyle(color: kGoldChip, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (onEdit != null)
                    IconButton(tooltip: 'تعديل', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
                ],
                ),
              ),
              if (about.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(about, style: const TextStyle(height: 1.8)),
                ),
              const SizedBox(height: 4),
              for (final l in links)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(platformIcon('${l['platform']}'), color: kGold),
                  title: Text('${l['name'] ?? ''}'.isEmpty
                      ? (AccountsScreen.platforms['${l['platform']}'] ?? 'رابط')
                      : '${l['name']}'),
                  subtitle: '${l['note'] ?? ''}'.isEmpty ? null : Text('${l['note']}'),
                  trailing: const Icon(Icons.chevron_left),
                  enabled: '${l['url'] ?? ''}'.isNotEmpty,
                  onTap: () => openUrl(context, '${l['url']}'),
                ),
            ],
          ),
        ),
      );
}

/// The form for one owner: name, title, a note, and his links.
class _PersonEditor extends StatefulWidget {
  final Map<String, dynamic>? person;

  /// The sheikh's own card: only his accounts are edited.
  final bool sheikh;
  const _PersonEditor({this.person, this.sheikh = false});

  @override
  State<_PersonEditor> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<_PersonEditor> {
  late final _name = TextEditingController(text: '${widget.person?['name'] ?? ''}');
  late final _title = TextEditingController(text: '${widget.person?['title'] ?? ''}');
  late final _about = TextEditingController(text: '${widget.person?['about'] ?? ''}');
  late final List<Map<String, dynamic>> _links = [
    for (final l in (widget.person?['links'] ?? []) as List) Map<String, dynamic>.from(l as Map),
  ];
  bool _changed = false;

  InputDecoration _deco(String label, [String? hint]) =>
      InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder());

  Future<void> _editLink([int? index]) async {
    final old = index == null ? null : _links[index];
    var platform = '${old?['platform'] ?? 'telegram'}';
    final name = TextEditingController(text: '${old?['name'] ?? ''}');
    final url = TextEditingController(text: '${old?['url'] ?? ''}');
    final note = TextEditingController(text: '${old?['note'] ?? ''}');
    final res = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: AccountsScreen.platforms.containsKey(platform) ? platform : 'link',
                decoration: _deco('نوع الحساب'),
                items: [
                  for (final e in AccountsScreen.platforms.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setS(() => platform = v ?? platform),
              ),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: _deco('اسم القناة أو الحساب', 'مثل: القناة الرسمية')),
              const SizedBox(height: 10),
              TextField(
                controller: url,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: _deco('الرابط', 'https://'),
              ),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: _deco('ملاحظة (اختياري)', 'مثل: دروس يومية')),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final u = url.text.trim();
                  if (!u.startsWith('http')) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(const SnackBar(content: Text('اكتب الرابط كاملاً ويبدأ بـ https')));
                    return;
                  }
                  Navigator.pop(ctx, {
                    'platform': platform,
                    'name': name.text.trim(),
                    'url': u,
                    'note': note.text.trim(),
                  });
                },
                child: const Text('حفظ الحساب'),
              ),
            ],
          ),
        ),
      ),
    );
    if (res == null) return;
    setState(() {
      _changed = true;
      if (index == null) {
        _links.add(res);
      } else {
        _links[index] = res;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.person == null;
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('اضغط «حفظ» أولاً، أو «تجاهل التغييرات»')));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.sheikh ? 'حسابات الشيخ' : (isNew ? 'إضافة شيخ أو قناة' : 'تعديل')),
          actions: [
            if (_changed)
              TextButton(
                onPressed: () {
                  setState(() => _changed = false);
                  WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context));
                },
                child: const Text('تجاهل التغييرات', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!widget.sheikh) ...[
            TextField(
                controller: _name,
                onChanged: (_) => setState(() => _changed = true),
                decoration: _deco('الاسم', 'مثل: الشيخ فلان بن فلان')),
            const SizedBox(height: 10),
            TextField(
                controller: _title,
                onChanged: (_) => setState(() => _changed = true),
                decoration: _deco('الوصف المختصر (اختياري)', 'مثل: من طلاب الشيخ')),
            const SizedBox(height: 10),
            TextField(
                controller: _about,
                maxLines: 5,
                onChanged: (_) => setState(() => _changed = true),
                decoration: _deco('نبذة وتفاصيل (اختياري)')),
            const SizedBox(height: 16),
            ],
            const Text('الحسابات والقنوات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            for (var i = 0; i < _links.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(platformIcon('${_links[i]['platform']}'), color: kGold),
                title: Text('${_links[i]['name']}'.isEmpty
                    ? (AccountsScreen.platforms['${_links[i]['platform']}'] ?? 'رابط')
                    : '${_links[i]['name']}'),
                subtitle: Text('${_links[i]['url']}',
                    textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _editLink(i),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => setState(() {
                    _links.removeAt(i);
                    _changed = true;
                  }),
                ),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_link),
              label: const Text('إضافة حساب أو قناة'),
              onPressed: _editLink,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white, minimumSize: const Size(0, 50)),
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              onPressed: () {
                if (_name.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب الاسم أولاً')));
                  return;
                }
                setState(() => _changed = false);
                final out = {
                  'name': _name.text.trim(),
                  'title': _title.text.trim(),
                  'about': _about.text.trim(),
                  'links': _links,
                };
                WidgetsBinding.instance.addPostFrameCallback((_) => Navigator.pop(context, out));
              },
            ),
            if (!isNew && !widget.sheikh)
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('حذف صاحب الحساب وكل حساباته', style: TextStyle(color: Colors.red)),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('حذف؟'),
                      content: Text('سيُحذف «${_name.text.trim()}» وكل حساباته من هذه الصفحة.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('حذف', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  setState(() => _changed = false);
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => Navigator.pop(context, <String, dynamic>{'_delete': true}));
                },
              ),
          ],
        ),
      ),
    );
  }
}
