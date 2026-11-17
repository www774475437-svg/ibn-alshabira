import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../services/cloud.dart';
import '../services/reminders.dart';
import '../services/telegram_out.dart';
import '../theme.dart';
import '../widgets/common.dart';

void _say(BuildContext context, String text, {bool ok = true}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        backgroundColor: ok ? const Color(0xFF2E7D32) : const Color(0xFFB3261E), content: Text(text)));
}

// ======================================================================= zakat
/// «حاسبة الزكاة». Readers see it after the sheikh approves it.
class ZakatScreen extends StatefulWidget {
  const ZakatScreen({super.key});

  @override
  State<ZakatScreen> createState() => _ZakatScreenState();
}

class _ZakatScreenState extends State<ZakatScreen> {
  final _f = {
    'cash': TextEditingController(),
    'gold': TextEditingController(),
    'goldPrice': TextEditingController(),
    'silver': TextEditingController(),
    'silverPrice': TextEditingController(),
    'trade': TextEditingController(),
    'owed': TextEditingController(),
    'debt': TextEditingController(),
  };
  String _base = 'gold';

  double _n(String k) => double.tryParse(_f[k]!.text.replaceAll(',', '').trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      _f['goldPrice']!.text = p.getString('zkGold') ?? '';
      _f['silverPrice']!.text = p.getString('zkSilver') ?? '';
      if (mounted) setState(() {});
    });
  }

  String _fmt(double v) => v.toStringAsFixed(v >= 100 ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    final staff = cloud.isAdmin;
    if (!cloud.zakatOn && !staff) {
      return Scaffold(
        appBar: AppBar(title: const Text('حاسبة الزكاة')),
        body: const EmptyState(icon: Icons.calculate_outlined, text: 'تُتاح قريباً بإذن الله.'),
      );
    }
    final goldValue = _n('gold') * _n('goldPrice');
    final silverValue = _n('silver') * _n('silverPrice');
    final total = _n('cash') + goldValue + silverValue + _n('trade') + _n('owed') - _n('debt');
    final nisab = _base == 'gold' ? 85 * _n('goldPrice') : 595 * _n('silverPrice');
    final ready = nisab > 0;
    final due = ready && total >= nisab;
    InputDecoration dec(String l, [String? h]) =>
        InputDecoration(labelText: l, helperText: h, border: const OutlineInputBorder(), isDense: true);
    Widget field(String k, String l, [String? h]) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _f[k],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              setState(() {});
              if (k == 'goldPrice') SharedPreferences.getInstance().then((p) => p.setString('zkGold', v));
              if (k == 'silverPrice') SharedPreferences.getInstance().then((p) => p.setString('zkSilver', v));
            },
            decoration: dec(l, h),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('حاسبة الزكاة')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        if (staff) _ZakatApproval(),
        const Text('اكتب ما عندك مما حال عليه الحول (سنة هجرية كاملة)، بعملة واحدة.',
            style: TextStyle(height: 1.7)),
        const SizedBox(height: 10),
        field('cash', 'المال النقدي والمدّخرات'),
        field('gold', 'الذهب بالجرام', 'عيار 24؛ وحوّل غيره إليه'),
        field('goldPrice', 'سعر جرام الذهب اليوم'),
        field('silver', 'الفضة بالجرام'),
        field('silverPrice', 'سعر جرام الفضة اليوم'),
        field('trade', 'عروض التجارة (قيمة البضاعة المعدّة للبيع)'),
        field('owed', 'ديون لك يُرجى سدادها'),
        field('debt', 'ديون عليك حالّة الآن'),
        const Text('النصاب على:', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('الذهب (85 جراماً)'), selected: _base == 'gold', onSelected: (_) => setState(() => _base = 'gold')),
          ChoiceChip(label: const Text('الفضة (595 جراماً)'), selected: _base == 'silver', onSelected: (_) => setState(() => _base = 'silver')),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (due ? const Color(0xFF2E7D32) : kGold).withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: due ? const Color(0xFF2E7D32) : kGold),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('مجموع مالك: ${_fmt(total)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(ready ? 'النصاب: ${_fmt(nisab)}' : 'اكتب سعر جرام ${_base == 'gold' ? 'الذهب' : 'الفضة'} لمعرفة النصاب',
                style: const TextStyle(height: 1.8)),
            const Divider(),
            Text(
                !ready
                    ? '—'
                    : due
                        ? 'تجب عليك الزكاة: ${_fmt(total * 0.025)}  (ربع العشر 2.5٪)'
                        : 'لم يبلغ مالك النصاب، فلا زكاة عليك فيه.',
                style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: due ? const Color(0xFF2E7D32) : null)),
          ]),
        ),
        if (cloud.zakatNote.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(cloud.zakatNote, style: const TextStyle(height: 1.8)),
        ],
        const SizedBox(height: 12),
        const Text('هذه حاسبة تقريبية للعون، ومن أشكل عليه شيء فليسأل الشيخ من «اسأل الشيخ».',
            style: TextStyle(color: Colors.grey, height: 1.7)),
      ]),
    );
  }
}

class _ZakatApproval extends StatefulWidget {
  @override
  State<_ZakatApproval> createState() => _ZakatApprovalState();
}

class _ZakatApprovalState extends State<_ZakatApproval> {
  late final _note = TextEditingController(text: Cloud.instance.zakatNote);

  @override
  Widget build(BuildContext context) => Card(
        color: kGold.withValues(alpha: .1),
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('للمشرفين فقط', style: TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
            TextField(
              controller: _note,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'تنبيه أو شرح يظهر تحت النتيجة (اختياري)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('اعتمدتُ الحاسبة، أظهرها للناس'),
              value: Cloud.instance.zakatOn,
              onChanged: (v) async {
                final err = await Cloud.instance
                    .setConfig('zakat', {'on': v, 'note': _note.text.trim()}, v ? 'اعتماد حاسبة الزكاة' : 'إخفاء حاسبة الزكاة');
                if (context.mounted) _say(context, err ?? 'تم الحفظ', ok: err == null);
                if (mounted) setState(() {});
              },
            ),
          ]),
        ),
      );
}

// =================================================================== lessons
const _days = ['', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

/// Sample lessons the staff see until they enter the real ones.
const _sample = [
  {'day': 6, 'time': '17:00', 'title': 'شرح كتاب التوحيد', 'place': 'المسجد', 'kind': 'mosque'},
  {'day': 1, 'time': '20:00', 'title': 'درس في الفقه', 'place': 'المسجد', 'kind': 'book'},
  {'day': 4, 'time': '19:30', 'title': 'درس مباشر على يوتيوب', 'place': 'يوتيوب', 'kind': 'live'},
];

class LessonsScreen extends StatefulWidget {
  const LessonsScreen({super.key});

  @override
  State<LessonsScreen> createState() => _LessonsScreenState();
}

class _LessonsScreenState extends State<LessonsScreen> {
  Set<String> _asked = {};

  @override
  void initState() {
    super.initState();
    Reminders.lessonsAsked().then((s) => mounted ? setState(() => _asked = s) : null);
  }

  Future<void> _edit([int? index]) async {
    final cloud = Cloud.instance;
    final list = [for (final m in (cloud.timetable.isEmpty ? _sample : cloud.timetable)) Map<String, dynamic>.from(m)];
    final m = index == null ? <String, dynamic>{'day': 6, 'time': '17:00', 'title': '', 'place': '', 'kind': 'mosque'} : list[index];
    final title = TextEditingController(text: '${m['title']}');
    final place = TextEditingController(text: '${m['place']}');
    var day = (m['day'] as num?)?.toInt() ?? 6;
    var time = '${m['time']}';
    var kind = '${m['kind']}';
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(c).viewInsets.bottom + 16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان الدرس')),
              TextField(controller: place, decoration: const InputDecoration(labelText: 'المكان أو الرابط')),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(label: Text(_days[d]), selected: day == d, onSelected: (_) => set(() => day = d)),
              ]),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.schedule),
                label: Text('الوقت: $time'),
                onPressed: () async {
                  final p = time.split(':');
                  final t = await showTimePicker(
                      context: c, initialTime: TimeOfDay(hour: int.tryParse(p[0]) ?? 17, minute: int.tryParse(p[1]) ?? 0));
                  if (t != null) set(() => time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                },
              ),
              Wrap(spacing: 6, children: [
                for (final k in const [('mosque', 'في المسجد'), ('book', 'شرح كتاب'), ('live', 'مباشر')])
                  ChoiceChip(label: Text(k.$2), selected: kind == k.$1, onSelected: (_) => set(() => kind = k.$1)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                if (index != null)
                  TextButton(onPressed: () => Navigator.pop(c, 'del'), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('حفظ')),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (res == null) return;
    if (res == 'del' && index != null) {
      list.removeAt(index);
    } else {
      final n = {'day': day, 'time': time, 'title': title.text.trim(), 'place': place.text.trim(), 'kind': kind};
      index == null ? list.add(n) : list[index] = n;
    }
    final err = await cloud.setConfig('timetable', {'on': cloud.timetableOn, 'items': list}, 'تعديل جدول الدروس');
    if (mounted) _say(context, err ?? 'تم الحفظ', ok: err == null);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Cloud.instance,
        builder: (context, _) {
          final cloud = Cloud.instance;
          final staff = cloud.isAdmin;
          final sample = cloud.timetable.isEmpty;
          final items = sample ? (staff ? _sample : const <Map<String, dynamic>>[]) : cloud.timetable;
          final sorted = [...items]..sort((a, b) {
              final d = ((a['day'] as num?) ?? 0).compareTo((b['day'] as num?) ?? 0);
              return d != 0 ? d : '${a['time']}'.compareTo('${b['time']}');
            });
          return Scaffold(
            appBar: AppBar(title: const Text('جدول دروس الشيخ')),
            floatingActionButton: staff
                ? FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('درس'))
                : null,
            body: !cloud.timetableOn && !staff
                ? const EmptyState(icon: Icons.event_note_outlined, text: 'يُضاف جدول الدروس قريباً بإذن الله.')
                : ListView(padding: const EdgeInsets.all(12), children: [
                    if (staff)
                      Card(
                        color: kGold.withValues(alpha: .1),
                        child: SwitchListTile(
                          title: const Text('أظهر الجدول للناس'),
                          subtitle: Text(sample ? 'هذه أمثلة فقط؛ عدّلها بدروسك ثم أظهر الجدول' : 'يراه الناس في الرئيسية والمزيد'),
                          value: cloud.timetableOn,
                          onChanged: (v) async {
                            final err = await cloud.setConfig(
                                'timetable', {'on': v, 'items': sample ? _sample : cloud.timetable}, v ? 'إظهار جدول الدروس' : 'إخفاء جدول الدروس');
                            if (context.mounted) _say(context, err ?? 'تم', ok: err == null);
                          },
                        ),
                      ),
                    for (var i = 0; i < sorted.length; i++)
                      _LessonTile(
                        m: sorted[i],
                        asked: _asked.contains(Reminders.lessonKey(sorted[i])),
                        onRemind: () async {
                          await Reminders.toggleLesson(Reminders.lessonKey(sorted[i]));
                          final s = await Reminders.lessonsAsked();
                          if (mounted) setState(() => _asked = s);
                        },
                        onEdit: staff ? () => _edit(items.indexOf(sorted[i])) : null,
                      ),
                  ]),
          );
        },
      );
}

class _LessonTile extends StatelessWidget {
  final Map<String, dynamic> m;
  final bool asked;
  final VoidCallback onRemind;
  final VoidCallback? onEdit;
  const _LessonTile({required this.m, required this.asked, required this.onRemind, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final kind = '${m['kind']}';
    final place = '${m['place'] ?? ''}';
    return Card(
      child: ListTile(
        onTap: place.startsWith('http') ? () => launchUrl(Uri.parse(place), mode: LaunchMode.externalApplication) : onEdit,
        onLongPress: onEdit,
        leading: CircleAvatar(
          backgroundColor: kGold.withValues(alpha: .18),
          child: Icon(kind == 'live' ? Icons.live_tv : kind == 'book' ? Icons.menu_book : Icons.mosque, color: kGoldChip),
        ),
        title: Text('${m['title']}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${_days[((m['day'] as num?)?.toInt() ?? 0).clamp(0, 7)]} · ${m['time']}${place.isEmpty ? '' : ' · $place'}'),
        trailing: IconButton(
          tooltip: 'ذكّرني قبل الدرس',
          icon: Icon(asked ? Icons.notifications_active : Icons.notifications_none, color: asked ? kGold : null),
          onPressed: onRemind,
        ),
      ),
    );
  }
}

/// The timetable on the home page (only when the sheikh turned it on).
class LessonsHomeCard extends StatelessWidget {
  const LessonsHomeCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Cloud.instance,
        builder: (context, _) {
          final cloud = Cloud.instance;
          if (!cloud.timetableOn || cloud.timetable.isEmpty) return const SizedBox.shrink();
          final now = DateTime.now();
          // The next lesson from now.
          Map<String, dynamic>? next;
          var best = 99999;
          for (final m in cloud.timetable) {
            final wd = (m['day'] as num?)?.toInt() ?? 0;
            final p = '${m['time']}'.split(':');
            final mins = ((wd - now.weekday + 7) % 7) * 1440 +
                (int.tryParse(p[0]) ?? 0) * 60 +
                (int.tryParse(p.length > 1 ? p[1] : '0') ?? 0) -
                (now.hour * 60 + now.minute);
            final v = mins < 0 ? mins + 7 * 1440 : mins;
            if (v < best) (best, next) = (v, m);
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Material(
              borderRadius: BorderRadius.circular(18),
              color: const Color(0xFF0E3B44),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LessonsScreen())),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kGold)),
                  child: Row(children: [
                    const Icon(Icons.mosque, color: kGold, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('الدرس القادم', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                        Text('${next?['title'] ?? ''}',
                            style: const TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('${_days[((next?['day'] as num?)?.toInt() ?? 0).clamp(0, 7)]} · ${next?['time'] ?? ''} · ${next?['place'] ?? ''}',
                            style: const TextStyle(color: kGold)),
                      ]),
                    ),
                    const Icon(Icons.chevron_left, color: kGold),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

// ===================================================================== sunan
/// The sheikh: turn the Sunnah reminders on/off and edit their texts.
/// Readers: turn them off for themselves.
class SunanScreen extends StatefulWidget {
  const SunanScreen({super.key});

  @override
  State<SunanScreen> createState() => _SunanScreenState();
}

class _SunanScreenState extends State<SunanScreen> {
  late final _t = {for (final k in Reminders.kinds.keys) k: TextEditingController(text: Reminders.textOf(k))};
  bool _mine = true;

  @override
  void initState() {
    super.initState();
    Reminders.userOn().then((v) => mounted ? setState(() => _mine = v) : null);
  }

  Future<void> _save(bool on) async {
    final err = await Cloud.instance.setConfig(
        'sunan', {'on': on, 'texts': {for (final e in _t.entries) e.key: e.value.text.trim()}}, 'تعديل تذكيرات السنن');
    await Reminders.schedule();
    if (mounted) _say(context, err ?? 'تم الحفظ', ok: err == null);
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    final staff = cloud.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('تذكيرات السنن')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        const Text('تذكير بسورة الكهف يوم الجمعة، وبصيام الاثنين والخميس، والأيام البيض، ويوم عرفة، وعاشوراء.',
            style: TextStyle(height: 1.8)),
        const SizedBox(height: 8),
        if (!cloud.sunanOn && !staff)
          const Text('لم تُفعَّل بعد.', style: TextStyle(color: Colors.grey))
        else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('أريد هذه التذكيرات'),
            value: _mine,
            onChanged: (v) async {
              await Reminders.setUserOn(v);
              setState(() => _mine = v);
            },
          ),
        if (staff) ...[
          const Divider(height: 30),
          const Text('للمشرفين', style: TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('شغّل التذكيرات للجميع'),
            subtitle: const Text('مطفأة في الأصل'),
            value: cloud.sunanOn,
            onChanged: (v) async {
              await _save(v);
              setState(() {});
            },
          ),
          for (final e in Reminders.kinds.entries)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _t[e.key],
                maxLines: 2,
                decoration: InputDecoration(labelText: e.value.$1, border: const OutlineInputBorder()),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton(onPressed: () => _save(cloud.sunanOn), child: const Text('حفظ النصوص')),
        ],
      ]),
    );
  }
}

// ====================================================== live lesson «مجلس العلم»
String? youtubeId(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return null;
  if (u.host.contains('youtu.be')) return u.pathSegments.isEmpty ? null : u.pathSegments.first;
  if (u.queryParameters['v'] != null) return u.queryParameters['v'];
  final i = u.pathSegments.indexWhere((s) => s == 'live' || s == 'embed' || s == 'shorts');
  if (i >= 0 && i + 1 < u.pathSegments.length) return u.pathSegments[i + 1];
  return null;
}

/// Red home banner while the sheikh is live.
class LiveBanner extends StatelessWidget {
  const LiveBanner({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Cloud.instance,
        builder: (context, _) {
          final c = Cloud.instance;
          if (!c.liveOn || c.liveUrl.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Material(
              color: const Color(0xFFC62828),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LiveRoomScreen())),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.sensors, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('الشيخ في درس مباشر الآن',
                            style: TextStyle(fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        if (c.liveTitle.isNotEmpty) Text(c.liveTitle, style: const TextStyle(color: Colors.white70)),
                      ]),
                    ),
                    const Text('ادخل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// Staff: start or stop a live lesson.
class LiveControlScreen extends StatefulWidget {
  const LiveControlScreen({super.key});

  @override
  State<LiveControlScreen> createState() => _LiveControlScreenState();
}

class _LiveControlScreenState extends State<LiveControlScreen> {
  late final _url = TextEditingController(text: Cloud.instance.liveUrl);
  late final _title = TextEditingController(text: Cloud.instance.liveTitle);
  bool _announce = true;

  Future<void> _set(bool on) async {
    if (on && youtubeId(_url.text) == null) {
      _say(context, 'ضع رابط بث يوتيوب صحيحاً', ok: false);
      return;
    }
    final room = on ? '${DateTime.now().millisecondsSinceEpoch}' : Cloud.instance.liveRoom;
    final err = await Cloud.instance.setConfig(
        'live', {'on': on, 'url': _url.text.trim(), 'title': _title.text.trim(), 'room': room}, on ? 'بدء درس مباشر' : 'إنهاء الدرس المباشر');
    if (on && err == null && _announce) {
      await TelegramOut.queueText('🔴 الشيخ في درس مباشر الآن${_title.text.trim().isEmpty ? '' : ': ${_title.text.trim()}'}\n\n${_url.text.trim()}');
    }
    if (mounted) _say(context, err ?? (on ? 'ظهر الشريط للناس' : 'انتهى الدرس'), ok: err == null);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final on = Cloud.instance.liveOn;
    return Scaffold(
      appBar: AppBar(title: const Text('درس مباشر')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _url, decoration: const InputDecoration(labelText: 'رابط البث في يوتيوب', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'عنوان الدرس (اختياري)', border: OutlineInputBorder())),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('أعلِن في قناة تيليجرام أيضاً'),
          value: _announce,
          onChanged: (v) => setState(() => _announce = v ?? true),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52), backgroundColor: on ? Colors.grey.shade700 : const Color(0xFFC62828)),
          icon: Icon(on ? Icons.stop : Icons.sensors),
          label: Text(on ? 'أنهِ الدرس المباشر' : 'ابدأ: أظهر الشريط للناس'),
          onPressed: () => _set(!on),
        ),
        const SizedBox(height: 10),
        const Text('يظهر للناس شريط أحمر في الرئيسية، فيدخلون البث داخل التطبيق ويكتبون تعليقاتهم تحته.',
            style: TextStyle(color: Colors.grey, height: 1.7)),
      ]),
    );
  }
}

/// The live lesson inside the app, with comments below (one a minute).
class LiveRoomScreen extends StatefulWidget {
  const LiveRoomScreen({super.key});

  @override
  State<LiveRoomScreen> createState() => _LiveRoomScreenState();
}

class _LiveRoomScreenState extends State<LiveRoomScreen> {
  YoutubePlayerController? _yt;
  final _text = TextEditingController();
  bool _hideName = false;
  int _wait = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    final id = youtubeId(Cloud.instance.liveUrl);
    if (id != null) {
      _yt = YoutubePlayerController.fromVideoId(videoId: id, autoPlay: true, params: const YoutubePlayerParams(showFullscreenButton: true));
    }
    SharedPreferences.getInstance().then((p) {
      final last = p.getInt('liveLast') ?? 0;
      final left = 60 - (DateTime.now().millisecondsSinceEpoch - last) ~/ 1000;
      if (left > 0) _countdown(left);
      if (mounted) setState(() => _hideName = p.getBool('liveHideName') ?? false);
    });
  }

  void _countdown(int s) {
    _wait = s;
    _t?.cancel();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _yt?.close();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    final c = Cloud.instance;
    if (text.isEmpty) return;
    if (c.user == null) {
      _say(context, 'سجّل الدخول من «المزيد» لتكتب تعليقاً', ok: false);
      return;
    }
    if (_wait > 0) {
      _say(context, 'انتظر دقيقة بين كل تعليق', ok: false);
      return;
    }
    try {
      final ms = DateTime.now().millisecondsSinceEpoch.toString().padLeft(14, '0');
      await FirebaseFirestore.instance.collection('liveComments').doc('${ms}_${c.user!.uid}').set({
        'room': c.liveRoom,
        'uid': c.user!.uid,
        'name': _hideName ? '' : (c.user!.displayName ?? ''),
        'text': text.length > 400 ? text.substring(0, 400) : text,
        'at': FieldValue.serverTimestamp(),
      });
      _text.clear();
      (await SharedPreferences.getInstance()).setInt('liveLast', DateTime.now().millisecondsSinceEpoch);
      _countdown(60);
    } catch (_) {
      if (mounted) _say(context, 'تعذّر الإرسال', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Cloud.instance;
    return Scaffold(
      appBar: AppBar(title: Text(c.liveTitle.isEmpty ? 'مجلس العلم' : c.liveTitle)),
      body: Column(children: [
        if (_yt != null) YoutubePlayer(controller: _yt!, aspectRatio: 16 / 9),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('liveComments')
                .where('room', isEqualTo: c.liveRoom)
                .orderBy(FieldPath.documentId)
                .limitToLast(60)
                .snapshots(),
            builder: (context, snap) {
              final docs = (snap.data?.docs ?? const []).reversed.toList();
              if (docs.isEmpty) {
                return const Center(child: Text('لا تعليقات بعد.', style: TextStyle(color: Colors.grey)));
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(10),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final name = '${m['name'] ?? ''}'.trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${name.isEmpty ? 'متابع' : name}: ', style: const TextStyle(fontWeight: FontWeight.bold, color: kGoldChip)),
                      TextSpan(text: '${m['text'] ?? ''}'),
                    ]), style: const TextStyle(height: 1.6)),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Checkbox(
                  value: _hideName,
                  onChanged: (v) {
                    setState(() => _hideName = v ?? false);
                    SharedPreferences.getInstance().then((p) => p.setBool('liveHideName', _hideName));
                  },
                ),
                const Text('أخفِ اسمي'),
              ]),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    maxLength: 400,
                    decoration: const InputDecoration(counterText: '', hintText: 'اكتب تعليقك أو سؤالك', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(onPressed: _wait > 0 ? null : _send, child: Text(_wait > 0 ? '$_wait' : 'إرسال')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
