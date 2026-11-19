import 'package:flutter/material.dart';

import '../services/home_widgets.dart';
import '../theme.dart';

/// «ويدجت الشاشة الرئيسية»: every widget with a small preview and «أضف».
class WidgetsScreen extends StatelessWidget {
  const WidgetsScreen({super.key});

  static const _colors = {
    'prayer': [Color(0xFF070B1E), Color(0xFF1B2A5C), Color(0xFF3A86C8)],
    'answer': [Color(0xFF0B2230), Color(0xFF16404B), Color(0xFF2E6B73)],
    'dhikr': [Color(0xFF082E22), Color(0xFF14532D), Color(0xFF2F7A4D)],
    'read': [Color(0xFF3A2A0C), Color(0xFF7A5A22), Color(0xFFC9A54C)],
    'quiz': [Color(0xFF0B1230), Color(0xFF1B2A5C), Color(0xFF3A2E6B)],
    'tour': [Color(0xFF0B2230), Color(0xFF16404B), Color(0xFF2E6B73)],
  };

  static const _icons = {
    'prayer': Icons.mosque_outlined,
    'answer': Icons.article_outlined,
    'dhikr': Icons.spa_outlined,
    'read': Icons.auto_stories_outlined,
    'quiz': Icons.quiz_outlined,
    'tour': Icons.emoji_events_outlined,
  };

  @override
  Widget build(BuildContext context) {
    HomeWidgets.push();
    return Scaffold(
      appBar: AppBar(title: const Text('ويدجت الشاشة الرئيسية')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        Text(
          HomeWidgets.supported
              ? 'ضع ما تحب على شاشة جوالك، فتراه دون أن تفتح التطبيق، ويفتح لك صفحته بضغطة.'
              : 'الويدجت في تطبيق الأندرويد. نزّل التطبيق لتضعها على شاشة جوالك.',
          style: const TextStyle(color: Colors.grey, height: 1.7),
        ),
        const SizedBox(height: 10),
        for (final k in HomeWidgets.kinds)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: _colors[k.$1]!,
              ),
            ),
            child: Row(children: [
              Icon(_icons[k.$1], color: kGold, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k.$2,
                      style: const TextStyle(
                          fontFamily: 'Tajawal', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 2),
                  Text(k.$3, style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.5)),
                ]),
              ),
              if (HomeWidgets.supported)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
                  onPressed: () async {
                    final ok = await HomeWidgets.pin(k.$1);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('جوالك لا يقبل الإضافة من هنا: اضغط مطوّلاً على الشاشة ← الأدوات ← ابن الشابرة')));
                    }
                  },
                  child: const Text('أضف'),
                ),
            ]),
          ),
        const SizedBox(height: 6),
        const Text(
            'إن لم تظهر نافذة الإضافة:\n'
            '1. اضغط مطوّلاً على مكان فارغ في شاشة الجوال.\n'
            '2. اختر «الأدوات» (في سامسونج: «أدوات الشاشة»).\n'
            '3. ابحث عن «ابن الشابرة» واسحب ما تريد إلى الشاشة.',
            style: TextStyle(height: 1.8)),
      ]),
    );
  }
}
