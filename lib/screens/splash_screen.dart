import 'package:flutter/material.dart';

import '../theme.dart';

/// Opening screen: the logo fades and grows in, a soft gold shine passes
/// over it, then the app continues.
class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..forward();

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, __, ___) => widget.next,
          transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
        ));
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appear = CurvedAnimation(parent: _c, curve: const Interval(0, 0.45, curve: Curves.easeOutBack));
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.35, curve: Curves.easeOut));
    final shine = CurvedAnimation(parent: _c, curve: const Interval(0.4, 0.9, curve: Curves.easeInOut));
    final textIn = CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.7, curve: Curves.easeOut));
    return Scaffold(
      backgroundColor: const Color(0xFF0A2417),
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: fade.value,
                child: Transform.scale(
                  scale: 0.7 + 0.3 * appear.value,
                  child: ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) {
                      final x = -1.0 + 3.0 * shine.value;
                      return LinearGradient(
                        begin: Alignment(x - 0.6, -1),
                        end: Alignment(x + 0.6, 1),
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                      ).createShader(rect);
                    },
                    child: ClipOval(
                      child: Image.asset('assets/icon/icon.png', width: 190, height: 190),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Opacity(
                opacity: textIn.value,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - textIn.value)),
                  child: const Column(
                    children: [
                      Text('ابن الشابرة',
                          style: TextStyle(color: kGold, fontSize: 32, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('أجوبة ومقالات وكتب الشيخ قائد بن غانم الشابرة',
                          style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
