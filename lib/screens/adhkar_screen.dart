import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repository.dart' show normalizeArabic;
import '../services/notifications.dart';
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
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  /// How many adhkar of a square were finished today.
  int _doneToday(String key) => _prefs?.getInt('adhkar_${_today()}_$key') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الأذكار'),
        actions: [
          if (!kIsWeb)
            IconButton(
              tooltip: 'تذكير الأذكار',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () => showModalBottomSheet(
                context: context,
                showDragHandle: true,
                builder: (_) => const _ReminderSheet(),
              ),
            ),
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
          void open(_Category c, [String? key]) => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => _CategoryScreen(category: c, progressKey: key)))
              .then((_) {
            if (mounted) setState(() {});
          });
          _Category? at(int i) => i < all.length ? all[i] : null;
          // The four everyday chapters, as big squares on top.
          final squares = <(String, IconData, List<Color>, _Category?, String)>[
            ('أذكار الصباح', Icons.wb_sunny_outlined, const [Color(0xFFF2A93B), Color(0xFFE2762A)], at(0), 'morning'),
            ('أذكار المساء', Icons.nights_stay_outlined, const [Color(0xFF3F4C8C), Color(0xFF232B57)], at(0), 'evening'),
            ('أذكار النوم', Icons.bedtime_outlined, const [Color(0xFF5B4B9A), Color(0xFF342A63)], at(1), 'sleep'),
            ('أذكار بعد الصلاة', Icons.mosque_outlined, const [Color(0xFF2E8B57), Color(0xFF1B5E3A)], at(26), 'salah'),
          ];
          return CustomScrollView(
            slivers: [
              if (n.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                    children: [
                      for (final (name, icon, colors, c, key) in squares)
                        Material(
                          borderRadius: BorderRadius.circular(20),
                          clipBehavior: Clip.antiAlias,
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                  begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors),
                            ),
                            child: InkWell(
                              onTap: c == null ? null : () => open(c, key),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(icon, color: Colors.white, size: 32),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontFamily: 'Tajawal',
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold)),
                                        if (c != null && _doneToday(key) > 0)
                                          Text(
                                              _doneToday(key) >= c.items.length
                                                  ? 'أتممتها اليوم ✓'
                                                  : 'أتممت ${_doneToday(key)} من ${c.items.length}',
                                              style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Text('الفهرس',
                      style: TextStyle(fontFamily: 'Tajawal', fontSize: 19, fontWeight: FontWeight.bold)),
                ),
              ),
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final c = items[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kGold.withValues(alpha: 0.18),
                          child:
                              Text('${all.indexOf(c) + 1}', style: const TextStyle(color: kGoldChip, fontSize: 13)),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => open(c),
                      ),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('من كتاب «حصن المسلم» بترتيبه',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month}-${d.day}';
}

class _CategoryScreen extends StatefulWidget {
  final _Category category;

  /// When set, how many adhkar were finished today is saved under this name.
  final String? progressKey;
  const _CategoryScreen({required this.category, this.progressKey});

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
                      final key = widget.progressKey;
                      if (key != null && _left[i] <= 0) {
                        final done = _left.where((n) => n <= 0).length;
                        SharedPreferences.getInstance().then((p) {
                          final k = 'adhkar_${_today()}_$key';
                          if (done > (p.getInt(k) ?? 0)) p.setInt(k, done);
                        });
                      }
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


/// Morning and evening reminders: off until the user turns them on.
class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet();

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  SharedPreferences? _p;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _p = p);
    });
  }

  Widget _row(String key, int id, String title, IconData icon, int defHour) {
    final p = _p!;
    final on = p.getBool('${key}On') ?? false;
    final h = p.getInt('${key}H') ?? defHour;
    final m = p.getInt('${key}M') ?? 0;
    final t = TimeOfDay(hour: h, minute: m);
    Future<void> apply(bool v, TimeOfDay time) async {
      await p.setBool('${key}On', v);
      await p.setInt('${key}H', time.hour);
      await p.setInt('${key}M', time.minute);
      await AdhkarNotifications.set(id, v, time.hour, time.minute, title);
      if (mounted) setState(() {});
    }

    return ListTile(
      leading: Icon(icon, color: kGold),
      title: Text(title),
      subtitle: Text(on ? 'كل يوم الساعة ${t.format(context)}' : 'متوقف'),
      onTap: () async {
        final picked = await showTimePicker(context: context, initialTime: t);
        if (picked != null) await apply(true, picked);
      },
      trailing: Switch(value: on, onChanged: (v) => apply(v, t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_p == null) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('تذكير الأذكار', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ),
          const Text('اضغط على السطر لاختيار الوقت', style: TextStyle(color: Colors.grey, fontSize: 12.5)),
          _row('adhkarMorning', 2, 'أذكار الصباح', Icons.wb_sunny_outlined, 6),
          _row('adhkarEvening', 3, 'أذكار المساء', Icons.nights_stay_outlined, 17),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
