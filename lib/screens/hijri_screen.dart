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
    final coming = [
      for (final o in _occasions)
        if (_next(o.$1, o.$2) case final DateTime at) (o.$3, at, at.difference(today).inDays),
    ]..sort((a, b) => a.$3.compareTo(b.$3));
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
              subtitle: Text('${c.$2.day}/${c.$2.month}/${c.$2.year} م'),
              trailing: Text(c.$3 == 0 ? 'اليوم' : c.$3 == 1 ? 'غداً' : 'بعد ${c.$3} يوماً',
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
