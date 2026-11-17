import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../services/prayer.dart';
import '../theme.dart';
import '../widgets/sky_card.dart';

Future<void> openPrayer(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrayerScreen()));

/// «مواقيت الصلاة والقبلة». The location is asked here only, when the reader
/// opens this page himself; it stays on the phone.
class PrayerScreen extends StatefulWidget {
  const PrayerScreen({super.key});

  @override
  State<PrayerScreen> createState() => _PrayerScreenState();
}

class _PrayerScreenState extends State<PrayerScreen> {
  String? _problem; // off | denied | blocked
  bool _busy = false;
  bool _tomorrow = false;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final pr = Prayer.instance;
    await pr.load();
    await _locate(force: !pr.hasPlace);
  }

  Future<void> _locate({bool force = false}) async {
    setState(() => _busy = true);
    final r = await Prayer.instance.locate(force: force);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = Prayer.instance.hasPlace && !force ? null : r;
    });
    await Prayer.instance.pushWidget();
  }

  Future<void> _pickCity() async {
    final c = await showModalBottomSheet<(String, double, double)>(
      context: context,
      isScrollControlled: true,
      builder: (c) => _CityPicker(),
    );
    if (c != null) {
      await Prayer.instance.setCity(c);
      if (mounted) setState(() => _problem = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Prayer.instance,
        builder: (context, _) {
          final pr = Prayer.instance;
          final day = DateTime.now().add(Duration(days: _tomorrow ? 1 : 0));
          final times = pr.timesOf(day);
          final next = pr.next();
          return Scaffold(
            appBar: AppBar(title: const Text('مواقيت الصلاة والقبلة')),
            body: ListView(padding: const EdgeInsets.all(14), children: [
              PrayerSkyCard(onTap: () {}),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(color: kGold),
              if (!pr.hasPlace || _problem != null) _askCard(pr),
              if (times != null) ...[
                Row(children: [
                  Text(_tomorrow ? 'مواقيت الغد' : 'مواقيت اليوم',
                      style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [ButtonSegment(value: false, label: Text('اليوم')), ButtonSegment(value: true, label: Text('غداً'))],
                    selected: {_tomorrow},
                    onSelectionChanged: (s) => setState(() => _tomorrow = s.first),
                  ),
                ]),
                const SizedBox(height: 6),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(children: [
                    for (var i = 0; i < 6; i++)
                      ListTile(
                        dense: true,
                        leading: Icon(
                            const [Icons.nights_stay_outlined, Icons.wb_twilight, Icons.wb_sunny_outlined, Icons.sunny_snowing, Icons.wb_twilight, Icons.dark_mode_outlined][i],
                            color: !_tomorrow && next?.$1 == i ? kGold : null),
                        title: Text(Prayer.names[i],
                            style: TextStyle(fontWeight: !_tomorrow && next?.$1 == i ? FontWeight.bold : null)),
                        trailing: Text(_PrayerSkyCardTime.fmt(times[i]),
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: !_tomorrow && next?.$1 == i ? kGold : null)),
                      ),
                  ]),
                ),
                const SizedBox(height: 14),
                _Qibla(deg: pr.qibla!, live: _android),
                const SizedBox(height: 14),
                _settings(pr),
                if (_android) ...[const SizedBox(height: 14), const _WidgetHelp()],
              ],
              const SizedBox(height: 14),
              const Text('تُحسب الأوقات في جوالك نفسه، ولا يُرسل موقعك إلى أي مكان. وقد تختلف دقيقة أو دقيقتين عن تقويم بلدك.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12.5, height: 1.7)),
            ]),
          );
        },
      );

  Widget _askCard(Prayer pr) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(
                switch (_problem) {
                  'off' => 'خدمة الموقع مطفأة في جوالك. شغّلها، أو اختر مدينتك.',
                  'blocked' => 'منعتَ التطبيق من معرفة موقعك. اسمح له من إعدادات الجوال، أو اختر مدينتك.',
                  'denied' => 'لم تسمح بمعرفة موقعك. اسمح لحساب أوقات الصلاة في مدينتك، أو اختر مدينتك بيدك.',
                  _ => 'لحساب أوقات الصلاة في مدينتك نحتاج موقعك مرة واحدة، أو اختر مدينتك بيدك.',
                },
                style: const TextStyle(height: 1.7)),
            const SizedBox(height: 10),
            if (_problem == 'blocked' || _problem == 'off')
              FilledButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('افتح إعدادات الموقع'),
                onPressed: Prayer.instance.openSettings,
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('اسمح بمعرفة موقعي'),
                onPressed: _busy ? null : () => _locate(force: true),
              ),
            const SizedBox(height: 6),
            OutlinedButton.icon(icon: const Icon(Icons.location_city), label: const Text('اختر مدينتك'), onPressed: _pickCity),
          ]),
        ),
      );

  Widget _settings(Prayer pr) => Card(
        margin: EdgeInsets.zero,
        child: Column(children: [
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(pr.place.isEmpty ? 'موقعك' : pr.place),
            subtitle: const Text('يُحدَّث وحده مرة في الأسبوع إذا انتقلت إلى مدينة أخرى'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => v == 'gps' ? _locate(force: true) : _pickCity(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'gps', child: Text('حدّث موقعي الآن')),
                PopupMenuItem(value: 'city', child: Text('اختر مدينة')),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.calculate_outlined),
            title: const Text('طريقة الحساب'),
            trailing: DropdownButton<String>(
              value: pr.method,
              underline: const SizedBox(),
              items: [for (final e in Prayer.methods.entries) DropdownMenuItem(value: e.key, child: Text(e.value.$1))],
              onChanged: (v) => pr.setMethod(v ?? pr.method),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wb_sunny_outlined),
            title: const Text('العصر على المذهب الحنفي'),
            subtitle: const Text('الأصل: مثل ظل الشيء (الجمهور)'),
            value: pr.hanafi,
            onChanged: (v) => pr.setMethod(pr.method, asrHanafi: v),
          ),
        ]),
      );
}

class _PrayerSkyCardTime {
  static String fmt(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'ص' : 'م'}';
  }
}

class _CityPicker extends StatefulWidget {
  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = Prayer.cities.where((c) => c.$1.contains(_q.trim())).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * .75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'ابحث عن مدينتك', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final c in l) ListTile(title: Text(c.$1), onTap: () => Navigator.pop(context, c)),
          ]),
        ),
      ]),
    );
  }
}

/// The qibla: a needle turning with the phone (Android), or the degrees.
class _Qibla extends StatefulWidget {
  final double deg;
  final bool live;
  const _Qibla({required this.deg, required this.live});

  @override
  State<_Qibla> createState() => _QiblaState();
}

class _QiblaState extends State<_Qibla> {
  StreamSubscription<MagnetometerEvent>? _sub;
  double? _heading;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      try {
        _sub = magnetometerEventStream().listen((e) {
          // Phone held flat: the angle of its top edge from north.
          final h = (math.atan2(-e.x, e.y) * 180 / math.pi + 360) % 360;
          final old = _heading;
          if (old == null) {
            setState(() => _heading = h);
          } else {
            var d = h - old;
            if (d > 180) d -= 360;
            if (d < -180) d += 360;
            if (d.abs() > 1) setState(() => _heading = (old + d * .2 + 360) % 360);
          }
        }, onError: (_) {});
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _heading;
    final turn = h == null ? widget.deg : widget.deg - h;
    final facing = h != null && ((turn % 360 + 360) % 360 < 5 || (turn % 360 + 360) % 360 > 355);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          const Text('اتجاه القبلة', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 10),
          SizedBox(
            width: 190,
            height: 190,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: facing ? const Color(0xFF2E7D32) : kGold, width: 3),
                  color: kGold.withValues(alpha: .06),
                ),
              ),
              Transform.rotate(
                angle: turn * math.pi / 180,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mosque, color: facing ? const Color(0xFF2E7D32) : kGold, size: 34),
                  Container(width: 4, height: 60, color: facing ? const Color(0xFF2E7D32) : kGold),
                  const SizedBox(height: 64),
                ]),
              ),
              const CircleAvatar(radius: 6, backgroundColor: kGold),
            ]),
          ),
          const SizedBox(height: 8),
          Text(
              h == null
                  ? 'القبلة على ${widget.deg.round()}° من الشمال (باتجاه عقارب الساعة)'
                  : facing
                      ? 'أنت مستقبل القبلة ✓'
                      : 'ضع الجوال مستوياً، ثم أدِره حتى يصير السهم إلى الأعلى',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6)),
        ]),
      ),
    );
  }
}

/// How to put the prayer widget on the phone's home screen.
class _WidgetHelp extends StatelessWidget {
  const _WidgetHelp();

  static const _ch = MethodChannel('ibn_alshabira/icon');

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('أضف المواقيت إلى شاشة الجوال',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            FilledButton.icon(
              icon: const Icon(Icons.add_to_home_screen),
              label: const Text('أضف الآن'),
              onPressed: () async {
                bool ok = false;
                try {
                  ok = await _ch.invokeMethod<bool>('pinWidget') ?? false;
                } catch (_) {}
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('جوالك لا يقبل الإضافة من هنا، اتبع الخطوات بالأسفل')));
                }
              },
            ),
            const SizedBox(height: 10),
            const Text(
                'أو بيدك:\n'
                '1. اضغط مطوّلاً على مكان فارغ في شاشة الجوال.\n'
                '2. اختر «الأدوات» (في سامسونج: «أدوات الشاشة» أو Widgets).\n'
                '3. ابحث عن «ابن الشابرة»، واسحب «مواقيت الصلاة» إلى الشاشة.',
                style: TextStyle(height: 1.8)),
          ]),
        ),
      );
}
