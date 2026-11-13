import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/repository.dart';

IconData chapterIcon(String key) {
  switch (key) {
    case 'aqeedah':
      return Icons.auto_awesome;
    case 'taharah':
      return Icons.water_drop_outlined;
    case 'salah':
      return Icons.mosque_outlined;
    case 'zakah':
      return Icons.volunteer_activism_outlined;
    case 'siyam':
      return Icons.nightlight_round;
    case 'hajj':
      return Icons.flight_takeoff;
    case 'muamalat':
      return Icons.handshake_outlined;
    case 'nikah':
      return Icons.family_restroom;
    case 'akhlaq':
      return Icons.favorite_border;
    default:
      return Icons.library_books_outlined;
  }
}

IconData platformIcon(String p) {
  switch (p) {
    case 'telegram':
      return Icons.send;
    case 'youtube':
      return Icons.play_circle_outline;
    case 'facebook':
      return Icons.facebook;
    case 'x':
      return Icons.alternate_email;
    case 'whatsapp':
      return Icons.chat;
    case 'audio':
      return Icons.headphones;
    case 'group':
      return Icons.groups;
    default:
      return Icons.link;
  }
}

Future<void> openUrl(BuildContext context, String url) async {
  final ok = url.isNotEmpty &&
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تعذّر فتح الرابط')),
    );
  }
}

/// Opens a fatwa through its named route, so the web address becomes
/// its own shareable link (…/#/fatwa/<id>).
void openFatwa(BuildContext context, Fatwa fatwa) {
  Navigator.of(context).pushNamed('/fatwa/${Uri.encodeComponent(fatwa.id)}');
}

class FatwaTile extends StatelessWidget {
  final Fatwa fatwa;
  final bool showChapter;

  const FatwaTile({super.key, required this.fatwa, this.showChapter = true});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final scheme = Theme.of(context).colorScheme;
    final preview = fatwa.question.isNotEmpty ? fatwa.question : fatwa.answer;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => openFatwa(context, fatwa),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Chip(text: fatwa.typeLabel, color: scheme.primary),
                  if (showChapter) ...[
                    const SizedBox(width: 6),
                    _Chip(text: repo.chapterName(fatwa.chapter), color: kGoldChip),
                  ],
                  const Spacer(),
                  if (repo.isFavorite(fatwa.id))
                    const Icon(Icons.bookmark, size: 18, color: kGoldChip),
                ],
              ),
              const SizedBox(height: 8),
              Text(fatwa.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ),
    );
  }
}

const kGoldChip = Color(0xFFB8913A);

class _Chip extends StatelessWidget {
  final String text;
  final Color color;
  const _Chip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: c),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: c, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
