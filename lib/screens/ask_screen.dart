import 'package:flutter/material.dart';

import '../theme.dart';

/// Placeholder until the online part (Firebase) is set up:
/// questions to the sheikh, his replies, and the admin accounts.
class AskScreen extends StatelessWidget {
  const AskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسأل الشيخ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          Icon(Icons.forum_outlined, size: 72, color: kGold),
          SizedBox(height: 16),
          Text('قريباً بإذن الله',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          Text(
            'ستتمكن من إرسال سؤالك إلى الشيخ من هنا مباشرة، ويرد عليك الشيخ في محادثة خاصة.\n\n'
            'وقد ينشر الشيخ السؤال وجوابه فتوى في التطبيق ليستفيد منها الجميع، '
            'ولا يظهر اسم السائل أبداً.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.8),
          ),
        ],
      ),
    );
  }
}
