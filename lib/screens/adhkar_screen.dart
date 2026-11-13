import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart' show normalizeArabic;
import '../theme.dart';
import '../widgets/common.dart';

class _Dhikr {
  final String text;
  final int count;
  _Dhikr(this.text, this.count);
}

class _Category {
  final String name;
  final List<_Dhikr> items;
  _Category(this.name, this.items);
}

Future<List<_Category>>? _adhkar;

Future<List<_Category>> _load() => _adhkar ??= () async {
      final list = jsonDecode(await rootBundle.loadString('assets/data/adhkar.json')) as List;
      return [
        for (final c in list)
          _Category('${(c as Map)['c']}', [
            for (final a in c['a'] as List) _Dhikr('${(a as Map)['t']}', ((a['n'] ?? 1) as num).toInt()),
          ]),
      ];
    }();

/// الأذكار: the chapters of «حصن المسلم» in the book's order, offline.
class AdhkarScreen extends StatefulWidget {
  const AdhkarScreen({super.key});

  @override
  State<AdhkarScreen> createState() => _AdhkarScreenState();
}

class _AdhkarScreenState extends State<AdhkarScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأذكار'),
        actions: [
          IconButton(
            tooltip: 'عدّاد التسبيح',
            icon: const Icon(Icons.touch_app_outlined),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TasbihScreen())),
          ),
        ],
      ),
      body: FutureBuilder<List<_Category>>(
        future: _load(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final all = snap.data!;
          final n = normalizeArabic(_q);
          final items = n.isEmpty ? all : all.where((c) => normalizeArabic(c.name).contains(n)).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    hintText: 'ابحث في الأبواب، مثل: النوم، السفر',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kGold.withValues(alpha: 0.18),
                        child: Text('${all.indexOf(c) + 1}', style: const TextStyle(color: kGoldChip, fontSize: 13)),
                      ),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => _CategoryScreen(category: c))),
                    );
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('من كتاب «حصن المسلم» بترتيبه', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryScreen extends StatefulWidget {
  final _Category category;
  const _CategoryScreen({required this.category});

  @override
  State<_CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<_CategoryScreen> {
  late final List<int> _left = [for (final d in widget.category.items) d.count];

  @override
  Widget build(BuildContext context) {
    final items = widget.category.items;
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final d = items[i];
          final done = _left[i] <= 0;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: done ? Colors.green.withValues(alpha: 0.10) : null,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: done
                  ? null
                  : () {
                      HapticFeedback.lightImpact();
                      setState(() => _left[i]--);
                    },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d.text, textAlign: TextAlign.justify, style: const TextStyle(fontSize: 19, height: 2.0)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: done ? Colors.green : kGold.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                              done
                                  ? 'تم ✓'
                                  : d.count == 1
                                      ? 'مرة واحدة'
                                      : 'بقي ${_left[i]} من ${d.count}',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, color: done ? Colors.white : kGoldChip)),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'نسخ',
                          icon: const Icon(Icons.copy, size: 20),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: d.text));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخ الذكر')));
                          },
                        ),
                        if (done)
                          IconButton(
                            tooltip: 'إعادة',
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () => setState(() => _left[i] = d.count),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A simple tasbih counter: tap anywhere to count.
class TasbihScreen extends StatefulWidget {
  const TasbihScreen({super.key});

  @override
  State<TasbihScreen> createState() => _TasbihScreenState();
}

class _TasbihScreenState extends State<TasbihScreen> {
  int _n = 0;

  void _tap() {
    setState(() => _n++);
    if (_n % 100 == 0) {
      HapticFeedback.vibrate();
    } else if (_n % 33 == 0) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عدّاد التسبيح'),
        actions: [
          IconButton(tooltip: 'تصفير', icon: const Icon(Icons.refresh), onPressed: () => setState(() => _n = 0)),
        ],
      ),
      body: InkWell(
        onTap: _tap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 230,
                height: 230,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kGold, width: 5),
                  color: kGold.withValues(alpha: 0.10),
                ),
                child: Text('$_n',
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 72, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),
              const Text('اضغط في أي مكان للعدّ', style: TextStyle(color: Colors.grey, fontSize: 16)),
              const SizedBox(height: 6),
              const Text('يهتزّ عند ٣٣ وعند كل ١٠٠', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
