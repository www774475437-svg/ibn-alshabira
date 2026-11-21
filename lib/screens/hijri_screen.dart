import 'package:flutter/material.dart';

import '../data/hijri.dart';
import '../theme.dart';
import '../widgets/common.dart' show kGoldChip;

/// «التقويم الهجري»: this Hijri month day by day, and how long is left to
/// the coming occasions (Ramadan, the two Eids, Arafah, Ashura…).
/// Calculated on the phone (approximate; it can differ by a day from the
/// moon sighting).
class HijriScreen extends StatelessWidget {
  const HijriScreen({super.key});

  static const _occasions = [
    (1, 1, 'رأس السنة الهجرية'),
    (1, 10, 'يوم عاشوراء'),
    (9, 1, 'رمضان'),
    (10, 1, 'عيد الفطر'),
    (12, 1, 'عشر ذي الحجة'),
    (12, 9, 'يوم عرفة'),
    (12, 10, 'عيد الأضحى'),
  ];

  /// The next Gregorian day whose Hijri date is [m]/[d] (within ~13 months).
  static DateTime? _next(int m, int d) {
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    for (var i = 0; i < 400; i++) {
      final h = Hijri.from(day);
      if (h.month == m && h.day == d) return day;
      day = day.add(const Duration(days: 1));
    }
    return null;
  }

  /// The coming occasions, nearest first: (name, day, days left).
  static List<(String, DateTime, int)> coming() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (final o in _occasions)
        if (_next(o.$1, o.$2) case final DateTime at) (o.$3, at, at.difference(today).inDays),
    ]..sort((a, b) => a.$3.compareTo(b.$3));
  }

  /// «1 رمضان 1448 هـ  ·  18/2/2027 م»
  static String bothDates(DateTime d) {
    final h = Hijri.from(d);
    return '${h.day} ${Hijri.months[h.month - 1]} ${h.year} هـ  ·  ${d.day}/${d.month}/${d.year} م';
  }

  static String left(int n) => n == 0 ? 'اليوم' : n == 1 ? 'غداً' : n == 2 ? 'بعد يومين' : 'بعد $n يوماً';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final h = Hijri.from(today);
    // The days of this Hijri month.
    final first = today.subtract(Duration(days: h.day - 1));
    final days = <(DateTime, Hijri)>[];
    for (var d = first; days.length < 30; d = d.add(const Duration(days: 1))) {
      final x = Hijri.from(d);
      if (x.month != h.month) break;
      days.add((d, x));
    }
    final coming = HijriScreen.coming();
    const wd = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return Scaffold(
      appBar: AppBar(title: const Text('التقويم الهجري')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(colors: [Color(0xFF0B2230), Color(0xFF16404B), Color(0xFF2E6B73)]),
          ),
          child: Column(children: [
            Text(wd[today.weekday - 1], style: const TextStyle(color: Colors.white70)),
            Text('${h.day}',
                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 52, fontWeight: FontWeight.bold, color: kGold)),
            Text('${Hijri.months[h.month - 1]} ${h.year} هـ',
                style: const TextStyle(fontFamily: 'Tajawal', fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${today.day}/${today.month}/${today.year} م', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 16),
        const Text('المناسبات القادمة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 6),
        for (final c in coming)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_available, color: kGold),
              title: Text(c.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(bothDates(c.$2)),
              trailing: Text(left(c.$3),
                  style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, color: kGoldChip)),
            ),
          ),
        const SizedBox(height: 16),
        Text('أيام ${Hijri.months[h.month - 1]}',
            style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final d in days)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: d.$1 == today
                      ? kGold
                      : (d.$2.day >= 13 && d.$2.day <= 15)
                          ? kGold.withValues(alpha: 0.18)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${d.$2.day}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16, color: d.$1 == today ? Colors.black : null)),
                  Text('${d.$1.day}/${d.$1.month}',
                      style: TextStyle(fontSize: 9.5, color: d.$1 == today ? Colors.black54 : Colors.grey)),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 10),
        const Text('الأيام المظلّلة هي الأيام البيض (13، 14، 15). التقويم محسوب في الجوال، وقد يختلف يوماً عن رؤية الهلال.',
            style: TextStyle(color: Colors.grey, height: 1.7, fontSize: 12.5)),
      ]),
    );
  }
}


/// A small card on the home page: the nearest occasion with its two dates
/// and how many days are left. Tapping it opens the calendar.
class OccasionCard extends StatelessWidget {
  const OccasionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final list = HijriScreen.coming();
    if (list.isEmpty) return const SizedBox.shrink();
    final c = list.first;
    return Card(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HijriScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(color: kGold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(18)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(c.$3 == 0 ? '🌙' : '${c.$3}',
                    style: const TextStyle(fontFamily: kUiFont, fontSize: 22, fontWeight: FontWeight.bold, color: kGoldChip)),
                if (c.$3 > 0) const Text('يوماً', style: TextStyle(fontFamily: kUiFont, fontSize: 11, color: kGoldChip)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.$3 == 0 ? 'اليوم: ${c.$1}' : 'بقي على ${c.$1}',
                    style: const TextStyle(fontFamily: kUiFont, fontSize: 16.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(HijriScreen.bothDates(c.$2), style: TextStyle(fontSize: 13, color: Pal.muted(context))),
                if (list.length > 1)
                  Text('ثم ${list[1].$1} ${HijriScreen.left(list[1].$3)}',
                      style: TextStyle(fontSize: 12.5, color: Pal.muted(context))),
              ]),
            ),
            Icon(Icons.chevron_left_rounded, color: Pal.muted(context)),
          ]),
        ),
      ),
    );
  }
}
