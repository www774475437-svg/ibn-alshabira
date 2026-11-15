import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// «فائدة من الكتب»: a sentence from the sheikh's books, a new one each day.
/// The staff write them (text, book and page); nothing shows until there is one.
class BenefitCard extends StatefulWidget {
  const BenefitCard({super.key});

  @override
  State<BenefitCard> createState() => _BenefitCardState();
}

class _BenefitCardState extends State<BenefitCard> {
  static List<Map<String, dynamic>>? _cache;
  List<Map<String, dynamic>> _items = _cache ?? const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await FirebaseFirestore.instance.collection('benefits').get();
      final l = [for (final d in q.docs) {...d.data(), 'id': d.id}]
        ..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
      _cache = l;
      if (mounted) setState(() => _items = l);
    } catch (_) {}
  }

  Future<void> _add() async {
    final text = TextEditingController(), book = TextEditingController(), page = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('فائدة جديدة من الكتب'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: text,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'نص الفائدة', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: book, decoration: const InputDecoration(labelText: 'اسم الكتاب', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: page, decoration: const InputDecoration(labelText: 'الصفحة', border: OutlineInputBorder())),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || text.text.trim().isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('benefits').add({
        'text': text.text.trim(),
        'book': book.text.trim(),
        'page': page.text.trim(),
        'at': FieldValue.serverTimestamp(),
      });
      await Cloud.instance.logAction('إضافة فائدة من الكتب', text.text.trim());
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final staff = Cloud.instance.isAdmin;
    if (_items.isEmpty && !staff) return const SizedBox.shrink();
    final day = DateTime.now().difference(DateTime(2024)).inDays;
    final b = _items.isEmpty ? null : _items[day % _items.length];
    final source = b == null
        ? ''
        : [if ('${b['book']}'.isNotEmpty) '${b['book']}', if ('${b['page']}'.isNotEmpty) 'ص ${b['page']}'].join(' — ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        color: kPaper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18), side: BorderSide(color: kGold.withValues(alpha: .7))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.format_quote_rounded, color: kGoldChip),
              const SizedBox(width: 6),
              const Text('فائدة من الكتب',
                  style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16, color: kGoldChip)),
              const Spacer(),
              if (staff)
                IconButton(
                  tooltip: 'أضف فائدة',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline, color: kGoldChip),
                  onPressed: _add,
                ),
            ]),
            if (b == null)
              const Text('لا فوائد بعد. اضغط ＋ لتضيف أول فائدة من كتب الشيخ (تظهر للناس بعدها).',
                  style: TextStyle(color: kInk, height: 1.7))
            else ...[
              const SizedBox(height: 4),
              SelectableText('${b['text']}',
                  style: const TextStyle(fontFamily: 'Amiri', fontSize: 18, height: 1.9, color: kInk)),
              if (source.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('[$source]', style: const TextStyle(color: kGoldChip, fontSize: 13)),
                ),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(
                  tooltip: 'نسخ',
                  icon: const Icon(Icons.copy_rounded, size: 20, color: kGoldChip),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: '${b['text']}\n[$source]'));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        backgroundColor: Color(0xFF2E7D32), duration: Duration(seconds: 1), content: Text('تم النسخ')));
                  },
                ),
                IconButton(
                  tooltip: 'مشاركة',
                  icon: const Icon(Icons.share_outlined, size: 20, color: kGoldChip),
                  onPressed: () => Share.share('${b['text']}\n[$source]\n\nتطبيق ابن الشابرة\nhttps://ibnalshabira.com'),
                ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
