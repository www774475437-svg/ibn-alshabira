import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme.dart';
import 'home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final _controller = PageController();
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  int _page = 0;

  static const _pages = [
    (
      Icons.menu_book_rounded,
      'مرحباً بك في «ابن الشابرة»',
      'تطبيق يجمع أجوبة ومقالات وكتب ورسائل الشيخ قايد بن غانم الشابرة حفظه الله.',
    ),
    (
      Icons.search_rounded,
      'ابحث عن أي مسألة',
      'اكتب كلمة واحدة، فتظهر لك الأجوبة المتعلقة بها، مرتّبة على أبواب العقيدة والفقه والآداب.',
    ),
    (
      Icons.forum_outlined,
      'اسأل الشيخ',
      'أرسل سؤالك من داخل التطبيق، ويصلك جواب الشيخ في محادثة خاصة بك.',
    ),
    (
      Icons.auto_stories_outlined,
      'المصحف والأذكار',
      'مصحف المدينة كاملاً وأذكار «حصن المسلم»، يعملان بلا إنترنت.',
    ),
  ];

  @override
  void dispose() {
    _intro.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    Repository.instance.setOnboarded();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  /// The logo: the gold ring is drawn first, then the logo fades in with a glow.
  Widget _logo() => AnimatedBuilder(
        animation: _intro,
        builder: (context, _) {
          final ring = Curves.easeOutCubic.transform(_intro.value.clamp(0.0, 0.6) / 0.6);
          final show = Curves.easeOut.transform(((_intro.value - 0.35) / 0.65).clamp(0.0, 1.0));
          return SizedBox(
            width: 210,
            height: 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 170 + 30 * show,
                  height: 170 + 30 * show,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: kGold.withValues(alpha: 0.35 * show), blurRadius: 50, spreadRadius: 6),
                    ],
                  ),
                ),
                CustomPaint(size: const Size(196, 196), painter: _RingPainter(ring)),
                Opacity(
                  opacity: show,
                  child: Transform.scale(
                    scale: 0.85 + 0.15 * show,
                    child: ClipOval(child: Image.asset('assets/icon/icon.png', width: 168, height: 168)),
                  ),
                ),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E2F1F), Color(0xFF1F5E3B), Color(0xFF123524)],
          ),
        ),
        child: Stack(
          children: [
            // A faint star pattern behind everything.
            const Positioned.fill(child: CustomPaint(painter: _PatternPainter())),
            SafeArea(
              child: Column(
                children: [
                  Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: TextButton(
                      onPressed: _finish,
                      child: const Text('تخطّي', style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      itemCount: _pages.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (context, i) {
                        final p = _pages[i];
                        return Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (i == 0)
                                _logo()
                              else
                                TweenAnimationBuilder<double>(
                                  key: ValueKey(i),
                                  tween: Tween(begin: 0.6, end: 1),
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeOutBack,
                                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                                  child: Container(
                                    padding: const EdgeInsets.all(34),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.06),
                                      border: Border.all(color: kGold, width: 2),
                                      boxShadow: [
                                        BoxShadow(color: kGold.withValues(alpha: 0.25), blurRadius: 40),
                                      ],
                                    ),
                                    child: Icon(p.$1, size: 84, color: kGold),
                                  ),
                                ),
                              const SizedBox(height: 40),
                              Text(p.$2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontFamily: 'Tajawal',
                                      color: Colors.white,
                                      fontSize: 27,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Container(width: 54, height: 3, color: kGold),
                              const SizedBox(height: 18),
                              Text(p.$3,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.8)),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _page ? 26 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _page ? kGold : Colors.white30,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kGold,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: last
                            ? _finish
                            : () => _controller.nextPage(
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutCubic,
                                ),
                        child: Text(last ? 'ابدأ' : 'التالي',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The gold ring around the logo, drawn as an arc that closes.
class _RingPainter extends CustomPainter {
  final double t;
  _RingPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, -math.pi / 2, 2 * math.pi * t, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

/// Faint eight-pointed stars on the background.
class _PatternPainter extends CustomPainter {
  const _PatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x12FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const step = 96.0;
    for (var y = 0.0; y < size.height + step; y += step) {
      for (var x = 0.0; x < size.width + step; x += step) {
        final c = Offset(x + ((y / step).round().isEven ? 0 : step / 2), y);
        for (final turn in const [0.0, math.pi / 4]) {
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(turn);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: 44, height: 44), paint);
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => false;
}
