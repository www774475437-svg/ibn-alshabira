import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services/cloud.dart';
import '../services/site_files.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'book_reader_screen.dart';

/// «كتب ينصح بها الشيخ»: books for students of knowledge, chosen by the staff
/// (title, author, a short note, and the PDF on Drive or a link).
/// Readers get the list from the server file (no Firestore reads); the staff
/// see it live and can add, edit or remove.
class RecommendedBooksScreen extends StatefulWidget {
  const RecommendedBooksScreen({super.key});

  @override
  State<RecommendedBooksScreen> createState() => _RecommendedBooksScreenState();
}

class _RecommendedBooksScreenState extends State<RecommendedBooksScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  bool get _staff => Cloud.instance.isAdmin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var l = <Map<String, dynamic>>[];
    try {
      if (_staff) {
        final q = await FirebaseFirestore.instance.collection('recBooks').get();
        l = [for (final d in q.docs) {...d.data(), 'id': d.id}];
      } else {
        final m = await SiteFiles.get('recbooks.json');
        l = [for (final e in (m?['l'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
      }
    } catch (_) {}
    l.sort((a, b) {
      final o = ((a['o'] ?? 0) as num).compareTo((b['o'] ?? 0) as num);
      return o != 0 ? o : '${a['t']}'.compareTo('${b['t']}');
    });
    if (mounted) {
      setState(() {
        _list = l;
        _loading = false;
      });
    }
  }

  /// The Drive file id inside a link (or the id itself).
  static String _driveId(String s) {
    final t = s.trim();
    final m = RegExp(r'(?:/d/|[?&]id=)([A-Za-z0-9_-]{20,})').firstMatch(t);
    if (m != null) return m.group(1)!;
    return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(t) ? t : '';
  }

  void _open(Map<String, dynamic> b) {
    final id = _driveId('${b['d'] ?? ''}');
    if (id.isNotEmpty) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BookReaderScreen(book: Book(id: id, title: '${b['t']}', folder: 'كتب ينصح بها الشيخ'))));
    } else if ('${b['u'] ?? ''}'.isNotEmpty) {
      openUrl(context, '${b['u']}');
    }
  }

  Future<void> _edit([Map<String, dynamic>? b]) async {
    final t = TextEditingController(text: '${b?['t'] ?? ''}'),
        a = TextEditingController(text: '${b?['a'] ?? ''}'),
        n = TextEditingController(text: '${b?['n'] ?? ''}'),
        d = TextEditingController(text: '${b?['d'] ?? ''}'),
        u = TextEditingController(text: '${b?['u'] ?? ''}'),
        o = TextEditingController(text: '${b?['o'] ?? _list.length + 1}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(b == null ? 'كتاب جديد' : 'تعديل الكتاب'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, decoration: const InputDecoration(labelText: 'اسم الكتاب')),
            const SizedBox(height: 8),
            TextField(controller: a, decoration: const InputDecoration(labelText: 'المؤلف')),
            const SizedBox(height: 8),
            TextField(controller: n, maxLines: 4, decoration: const InputDecoration(labelText: 'نبذة مختصرة')),
            const SizedBox(height: 8),
            TextField(
                controller: d,
                decoration: const InputDecoration(
                    labelText: 'رابط ملف PDF في Drive (الأفضل)', helperText: 'يُقرأ داخل التطبيق')),
            const SizedBox(height: 8),
            TextField(controller: u, decoration: const InputDecoration(labelText: 'أو رابط تحميل/تصفح آخر')),
            const SizedBox(height: 8),
            TextField(
                controller: o,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الترتيب (1 أولاً)')),
          ]),
        ),
        actions: [
          if (b != null)
            TextButton(
              onPressed: () async {
                await FirebaseFirestore.instance.doc('recBooks/${b['id']}').delete();
                if (c.mounted) Navigator.pop(c, true);
              },
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              if (t.text.trim().isEmpty) return;
              final data = {
                't': t.text.trim(),
                'a': a.text.trim(),
                'n': n.text.trim(),
                'd': d.text.trim(),
                'u': u.text.trim(),
                'o': int.tryParse(o.text.trim()) ?? 0,
              };
              final col = FirebaseFirestore.instance.collection('recBooks');
              if (b == null) {
                await col.add(data);
              } else {
                await col.doc('${b['id']}').set(data);
              }
              if (c.mounted) Navigator.pop(c, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Cloud.instance.logAction('كتب ينصح بها الشيخ', t.text.trim());
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('كتب ينصح بها الشيخ')),
      floatingActionButton: _staff
          ? FloatingActionButton(tooltip: 'أضف كتاباً', onPressed: () => _edit(), child: const Icon(Icons.add))
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? EmptyState(
                  icon: Icons.local_library_outlined,
                  text: _staff
                      ? 'لا كتب بعد. اضغط ＋ لتضيف أول كتاب (يظهر للناس خلال ساعات).'
                      : 'ستُضاف الكتب التي ينصح بها الشيخ هنا قريباً إن شاء الله.')
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 6, bottom: 90),
                    itemCount: _list.length,
                    itemBuilder: (context, i) {
                      final b = _list[i];
                      final hasPdf = _driveId('${b['d'] ?? ''}').isNotEmpty;
                      final hasLink = '${b['u'] ?? ''}'.isNotEmpty;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        child: InkWell(
                          onTap: hasPdf || hasLink ? () => _open(b) : null,
                          onLongPress: _staff ? () => _edit(b) : null,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 52,
                                height: 68,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                      colors: [brandColor(context), Color.lerp(brandColor(context), Colors.black, .3)!]),
                                  border: Border.all(color: kGold.withValues(alpha: .6)),
                                ),
                                child: const Icon(Icons.menu_book_rounded, color: kGold),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${b['t']}',
                                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, height: 1.4)),
                                  if ('${b['a'] ?? ''}'.isNotEmpty)
                                    Text('${b['a']}',
                                        style: const TextStyle(fontFamily: kUiFont, color: kGoldChip, fontSize: 13.5)),
                                  if ('${b['n'] ?? ''}'.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text('${b['n']}',
                                          style: TextStyle(color: Pal.muted(context), height: 1.7, fontSize: 14.5)),
                                    ),
                                  if (hasPdf || hasLink)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Row(children: [
                                        Icon(hasPdf ? Icons.chrome_reader_mode_outlined : Icons.open_in_new,
                                            size: 18, color: Pal.accent(context)),
                                        const SizedBox(width: 6),
                                        Text(hasPdf ? 'اقرأه في التطبيق' : 'افتح الرابط',
                                            style: TextStyle(
                                                fontFamily: kUiFont,
                                                fontWeight: FontWeight.bold,
                                                color: Pal.accent(context))),
                                      ]),
                                    ),
                                  if (_staff)
                                    Text('اضغط مطوّلاً للتعديل',
                                        style: TextStyle(fontSize: 11.5, color: Pal.muted(context))),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
