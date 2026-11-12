import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme.dart';
import 'home_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    (
      Icons.menu_book_rounded,
      'مرحباً بك في «ابن الشابرة»',
      'تطبيق يجمع فتاوى ومقالات وكتب ورسائل الشيخ قائد بن غانم الشابرة حفظه الله، من محافظة إب باليمن.',
    ),
    (
      Icons.search_rounded,
      'ابحث عن أي مسألة',
      'اكتب كلمة واحدة، فتظهر لك الفتاوى المتعلقة بها، مرتّبة على أبواب العقيدة والفقه والآداب.',
    ),
    (
      Icons.forum_outlined,
      'تواصل مع الشيخ',
      'قريباً بإذن الله: أرسل سؤالك إلى الشيخ من داخل التطبيق، وتابع حساباته على مواقع التواصل.',
    ),
  ];

  void _finish() {
    Repository.instance.setOnboarded();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: kGreen,
      body: SafeArea(
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
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: kGold, width: 2),
                          ),
                          child: Icon(p.$1, size: 72, color: kGold),
                        ),
                        const SizedBox(height: 36),
                        Text(p.$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Text(p.$3,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.7)),
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
                  width: i == _page ? 22 : 8,
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
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: last
                      ? _finish
                      : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          ),
                  child: Text(last ? 'ابدأ' : 'التالي', style: const TextStyle(fontSize: 17)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
