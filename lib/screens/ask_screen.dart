import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// «اسأل الشيخ»: the user sends a question and sees the sheikh's replies
/// here, like a private chat.
class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> {
  final _text = TextEditingController();
  bool _sending = false;

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final err = await Cloud.instance.ask(_text.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (err == null) {
      _text.clear();
      FocusScope.of(context).unfocus();
      _toast('وصل سؤالك، ويظهر الجواب هنا عند رد الشيخ');
    } else {
      _toast(err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('اسأل الشيخ')),
      body: ListenableBuilder(
        listenable: cloud,
        builder: (context, _) {
          if (kIsWeb) {
            return _Info(
              icon: Icons.android,
              title: 'هذه الخدمة في تطبيق أندرويد',
              text: 'حمّل التطبيق لترسل سؤالك إلى الشيخ ويصلك الجواب.',
              button: 'تحميل التطبيق',
              onTap: () => openUrl(context, AppConfig.apkUrl),
            );
          }
          if (!cloud.ready) {
            return const _Info(
              icon: Icons.wifi_off,
              title: 'لا يوجد اتصال',
              text: 'تأكد من الاتصال بالإنترنت ثم افتح الصفحة مرة أخرى.',
            );
          }
          if (cloud.user == null) {
            return _Info(
              icon: Icons.forum_outlined,
              title: 'سجّل الدخول لترسل سؤالك',
              text: 'نحتاج حسابك ليصلك جواب الشيخ في محادثة خاصة بك.\n'
                  'وإذا نُشر الجواب في التطبيق فلا يظهر اسمك أبداً.',
              button: 'الدخول بحساب جوجل',
              onTap: () async {
                final err = await cloud.signIn();
                if (err != null && context.mounted) _toast(err);
              },
            );
          }
          return Column(
            children: [
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: cloud.myQuestions(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return const EmptyState(icon: Icons.error_outline, text: 'تعذّر تحميل الأسئلة');
                    }
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final docs = [...snap.data!.docs];
                    int ms(QueryDocumentSnapshot<Map<String, dynamic>> d) {
                      final t = d.data()['at'];
                      return t is Timestamp ? t.millisecondsSinceEpoch : 1 << 62;
                    }

                    docs.sort((a, b) => ms(a).compareTo(ms(b)));
                    if (docs.isEmpty) {
                      return const EmptyState(
                        icon: Icons.forum_outlined,
                        text: 'اكتب سؤالك في الأسفل.\nيصلك جواب الشيخ هنا، ولا يراه غيرك إلا إذا نشره الشيخ دون اسمك.',
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: docs.length,
                      itemBuilder: (context, i) => _QuestionBubble(data: docs[i].data()),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    border: Border(top: BorderSide(color: kGold.withValues(alpha: 0.3))),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 1500,
                          decoration: InputDecoration(
                            hintText: 'اكتب سؤالك هنا…',
                            counterText: '',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'send-question',
                        onPressed: _sending ? null : _send,
                        child: _sending
                            ? const SizedBox(
                                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  final Map<String, dynamic> data;
  const _QuestionBubble({required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reply = '${data['reply'] ?? ''}';
    final published = data['published'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The user's question
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Container(
            margin: const EdgeInsetsDirectional.only(top: 10, end: 40),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(16),
                topEnd: Radius.circular(16),
                bottomEnd: Radius.circular(16),
              ),
            ),
            child: SelectableText('${data['text'] ?? ''}', style: const TextStyle(fontSize: 16, height: 1.7)),
          ),
        ),
        // The sheikh's reply
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            margin: const EdgeInsetsDirectional.only(top: 6, start: 40),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: 0.14),
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(16),
                topEnd: Radius.circular(16),
                bottomStart: Radius.circular(16),
              ),
            ),
            child: reply.isEmpty
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule, size: 16, color: Colors.grey),
                      SizedBox(width: 6),
                      Text('بانتظار رد الشيخ', style: TextStyle(color: Colors.grey)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('جواب الشيخ',
                          style: TextStyle(color: kGoldChip, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      SelectableText(reply, style: const TextStyle(fontSize: 16, height: 1.8)),
                      if (published)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('نُشر هذا الجواب في التطبيق دون ذكر اسمك',
                              style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String? button;
  final VoidCallback? onTap;
  const _Info({required this.icon, required this.title, required this.text, this.button, this.onTap});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Icon(icon, size: 72, color: kGold),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.8)),
          if (button != null) ...[
            const SizedBox(height: 22),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: onTap,
              child: Text(button!, style: const TextStyle(fontSize: 16)),
            ),
          ],
        ],
      );
}
