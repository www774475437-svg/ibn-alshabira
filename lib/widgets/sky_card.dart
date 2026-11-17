import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/hijri.dart';
import '../services/prayer.dart';
import '../theme.dart';

/// The sky behind the prayer card: several colours blending into each other
/// and flowing slowly side to side, changing with the time of day.
class SkyPalette {
  final List<Color> colors;
  final bool stars;
  final Color glow; // the sun or the moon
  final double glowY; // 0 top .. 1 bottom
  const SkyPalette(this.colors, {this.stars = false, required this.glow, this.glowY = .3});

  static const night = SkyPalette([Color(0xFF070B1E), Color(0xFF111C44), Color(0xFF1B2A5C), Color(0xFF0B1230)],
      stars: true, glow: Color(0xFFE9E4C8), glowY: .25);
  static const dawn = SkyPalette([Color(0xFF14204A), Color(0xFF34407A), Color(0xFF8E6A9E), Color(0xFFE59A7A)],
      stars: true, glow: Color(0xFFFFC98A), glowY: .9);
  static const sunrise = SkyPalette([Color(0xFF3D5A9E), Color(0xFFF2A65A), Color(0xFFF7C873), Color(0xFFE76F51)],
      glow: Color(0xFFFFE08A), glowY: .75);
  static const morning = SkyPalette([Color(0xFF1E6FB8), Color(0xFF4FA3E0), Color(0xFF8CCBF2), Color(0xFF3A86C8)],
      glow: Color(0xFFFFF6C8), glowY: .2);
  static const afternoon = SkyPalette([Color(0xFF2C77B5), Color(0xFF6AA8D8), Color(0xFFF0C978), Color(0xFFDDA35A)],
      glow: Color(0xFFFFE6A0), glowY: .45);
  static const sunset = SkyPalette([Color(0xFF2B1E4F), Color(0xFFB24A6B), Color(0xFFF07F4F), Color(0xFFF6B15D)],
      glow: Color(0xFFFF9F5A), glowY: .85);
  static const dusk = SkyPalette([Color(0xFF0E1638), Color(0xFF3A2C68), Color(0xFF7A4A7E), Color(0xFF1C2350)],
      stars: true, glow: Color(0xFFE9E4C8), glowY: .3);

  /// The sky for [now], from the day's prayer times (or the clock alone).
  static SkyPalette at(DateTime now, List<DateTime>? t) {
    final h = now.hour + now.minute / 60;
    if (t == null) {
      if (h < 4.5) return night;
      if (h < 6) return dawn;
      if (h < 7.5) return sunrise;
      if (h < 14) return morning;
      if (h < 17) return afternoon;
      if (h < 18.5) return sunset;
      if (h < 20) return dusk;
      return night;
    }
    bool before(DateTime x, [int min = 0]) => now.isBefore(x.add(Duration(minutes: min)));
    if (before(t[0])) return night;
    if (before(t[1])) return dawn;
    if (before(t[1], 60)) return sunrise;
    if (before(t[3])) return morning;
    if (before(t[4], -40)) return afternoon;
    if (before(t[4], 25)) return sunset;
    if (before(t[5])) return dusk;
    return night;
  }
}

class SkyBackground extends StatefulWidget {
  final SkyPalette sky;
  final Widget child;
  final BorderRadius radius;
  const SkyBackground({super.key, required this.sky, required this.child, this.radius = const BorderRadius.all(Radius.circular(24))});

  @override
  State<SkyBackground> createState() => _SkyBackgroundState();
}

class _SkyBackgroundState extends State<SkyBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 14))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: widget.radius,
        child: AnimatedBuilder(
          animation: _a,
          builder: (context, child) {
            final v = Curves.easeInOut.transform(_a.value);
            final c = widget.sky.colors;
            return Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.4 + v * .8, -1),
                      end: Alignment(1.4 - v * .8, 1),
                      colors: c,
                      stops: [0, .35 + v * .1, .7 - v * .1, 1],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(.6 - v * 1.2, widget.sky.glowY * 2 - 1),
                      radius: .9,
                      colors: [widget.sky.glow.withValues(alpha: .55), widget.sky.glow.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              if (widget.sky.stars) Positioned.fill(child: CustomPaint(painter: _Stars(v))),
              child!,
            ]);
          },
          child: widget.child,
        ),
      );
}

class _Stars extends CustomPainter {
  final double v;
  _Stars(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(7);
    final p = Paint()..color = Colors.white;
    for (var i = 0; i < 38; i++) {
      final x = r.nextDouble() * size.width, y = r.nextDouble() * size.height * .75;
      final tw = (math.sin((v * 6 + i) * 1.7) + 1) / 2;
      p.color = Colors.white.withValues(alpha: .25 + tw * .55);
      canvas.drawCircle(Offset(x, y), .6 + r.nextDouble() * 1.1, p);
    }
  }

  @override
  bool shouldRepaint(_Stars o) => o.v != v;
}

/// The prayer card (home page and «المزيد»). Before a place is known it shows
/// the sky alone with «اضغط لمعرفة أوقات الصلاة».
class PrayerSkyCard extends StatefulWidget {
  final VoidCallback onTap;
  const PrayerSkyCard({super.key, required this.onTap});

  @override
  State<PrayerSkyCard> createState() => _PrayerSkyCardState();
}

class _PrayerSkyCardState extends State<PrayerSkyCard> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    Prayer.instance.load();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  static String hm(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')}';
  }

  static String left(Duration d) =>
      '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Prayer.instance,
        builder: (context, _) {
          final pr = Prayer.instance;
          final now = DateTime.now();
          final times = pr.timesOf(now);
          final next = pr.next(now: now);
          final h = Hijri.from(now);
          const white = Colors.white;
          return GestureDetector(
            onTap: widget.onTap,
            child: SkyBackground(
              sky: SkyPalette.at(now, times),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: times == null || next == null
                    ? SizedBox(
                        height: 120,
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.mosque_outlined, color: white, size: 32),
                          const SizedBox(height: 8),
                          const Text('اضغط لمعرفة أوقات الصلاة',
                              style: TextStyle(fontFamily: 'Tajawal', color: white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('${h.day} ${Hijri.months[(h.month - 1).clamp(0, 11)]}',
                              style: TextStyle(color: white.withValues(alpha: .85))),
                        ]),
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(Prayer.names[next.$1],
                                style: const TextStyle(
                                    fontFamily: 'Tajawal', color: kGold, fontSize: 22, fontWeight: FontWeight.bold)),
                            Text(hm(next.$2), style: const TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.bold)),
                          ]),
                          Container(width: 1, height: 44, margin: const EdgeInsets.symmetric(horizontal: 14), color: white.withValues(alpha: .4)),
                          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${h.day}', style: const TextStyle(color: white, fontSize: 22, fontWeight: FontWeight.bold)),
                            Text(Hijri.months[(h.month - 1).clamp(0, 11)], style: TextStyle(color: white.withValues(alpha: .9))),
                          ]),
                          const Spacer(),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text('بعد', style: TextStyle(color: white.withValues(alpha: .85))),
                            Text(left(next.$2.difference(now)),
                                style: const TextStyle(
                                    color: kGold, fontSize: 22, fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()])),
                          ]),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          for (var i = 0; i < 6; i++)
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: i == next.$1 ? Colors.black.withValues(alpha: .35) : Colors.black.withValues(alpha: .15),
                                  borderRadius: BorderRadius.circular(14),
                                  border: i == next.$1 ? Border.all(color: kGold) : null,
                                ),
                                child: Column(children: [
                                  Text(Prayer.names[i],
                                      style: TextStyle(
                                          color: i == next.$1 ? kGold : white, fontSize: 12.5, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text(hm(times[i]),
                                      style: TextStyle(color: i == next.$1 ? kGold : white, fontSize: 14.5, fontWeight: FontWeight.bold)),
                                ]),
                              ),
                            ),
                        ]),
                        const SizedBox(height: 8),
                        Text('${pr.place} · ${now.day}/${now.month}/${now.year}',
                            textAlign: TextAlign.center, style: TextStyle(color: white.withValues(alpha: .85), fontSize: 12.5)),
                      ]),
              ),
            ),
          );
        },
      );
}
