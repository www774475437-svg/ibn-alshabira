import 'package:flutter/material.dart';

import '../screens/challenge_screens.dart';
import '../screens/quiz_screens.dart';
import '../services/cloud.dart';
import '../theme.dart';

/// Colours the staff can give the announcement: background and name.
const annColors = <String, (Color, String)>{
  'gold': (Color(0xFF0E4D45), 'الأصلي'),
  'red': (Color(0xFFB3261E), 'أحمر'),
  'yellow': (Color(0xFFF2C230), 'أصفر'),
  'pink': (Color(0xFFD63384), 'وردي'),
  'green': (Color(0xFF2E7D32), 'أخضر'),
  'blue': (Color(0xFF1565C0), 'أزرق'),
};

/// The announcement on the home page, shown only in the place the staff chose.
class HomeAnnouncement extends StatelessWidget {
  final String place;
  const HomeAnnouncement({super.key, required this.place});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Cloud.instance,
        builder: (context, _) {
          final c = Cloud.instance;
          final where = const ['top', 'middle', 'bottom'].contains(c.annPlace) ? c.annPlace : 'middle';
          if (!c.announcementNow || where != place) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: AnnouncementCard(text: c.announcement, color: c.annColor, action: c.annAction, button: c.annButton),
          );
        },
      );
}

class AnnouncementCard extends StatelessWidget {
  final String text, color, action, button;
  final bool preview;
  const AnnouncementCard(
      {super.key, required this.text, required this.color, this.action = '', this.button = '', this.preview = false});

  void _open(BuildContext context) {
    if (preview) return;
    if (action == 'challenges') {
      openChallenges(context);
    } else if (action == 'quiz') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuizHomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = color == 'gold' || !annColors.containsKey(color) ? brandColor(context) : annColors[color]!.$1;
    final light = color == 'yellow';
    final fg = light ? const Color(0xFF3A2A00) : Colors.white;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.campaign, color: light ? fg : kGold),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 15, height: 1.7))),
        ]),
        if (action.isNotEmpty) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: light ? const Color(0xFF3A2A00) : Colors.white,
                foregroundColor: light ? Colors.white : bg),
            icon: Icon(action == 'challenges' ? Icons.bolt : Icons.quiz_outlined),
            label: Text(button.trim().isNotEmpty ? button.trim() : (action == 'challenges' ? 'افتح التحدّيات' : 'افتح الأسئلة')),
            onPressed: () => _open(context),
          ),
        ],
      ]),
    );
  }
}
