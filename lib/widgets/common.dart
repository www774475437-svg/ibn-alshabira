import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/repository.dart';

/// Icons the staff can give to any chapter.
const chapterIcons = <String, IconData>{
  'i_shield_outlined': Icons.shield_outlined,
  'i_mosque_outlined': Icons.mosque_outlined,
  'i_water_drop_outlined': Icons.water_drop_outlined,
  'i_volunteer_activism_outlined': Icons.volunteer_activism_outlined,
  'i_nightlight_round': Icons.nightlight_round,
  'i_flight_takeoff': Icons.flight_takeoff,
  'i_handshake_outlined': Icons.handshake_outlined,
  'i_family_restroom': Icons.family_restroom,
  'i_favorite_border': Icons.favorite_border,
  'i_alt_route': Icons.alt_route,
  'i_spa_outlined': Icons.spa_outlined,
  'i_library_books_outlined': Icons.library_books_outlined,
  'i_menu_book_outlined': Icons.menu_book_outlined,
  'i_auto_stories_outlined': Icons.auto_stories_outlined,
  'i_school_outlined': Icons.school_outlined,
  'i_gavel_outlined': Icons.gavel_outlined,
  'i_balance_outlined': Icons.balance_outlined,
  'i_account_balance_outlined': Icons.account_balance_outlined,
  'i_paid_outlined': Icons.paid_outlined,
  'i_storefront_outlined': Icons.storefront_outlined,
  'i_work_outline': Icons.work_outline,
  'i_home_outlined': Icons.home_outlined,
  'i_groups_outlined': Icons.groups_outlined,
  'i_person_outline': Icons.person_outline,
  'i_child_care_outlined': Icons.child_care_outlined,
  'i_elderly_outlined': Icons.elderly_outlined,
  'i_woman_outlined': Icons.woman_outlined,
  'i_man_outlined': Icons.man_outlined,
  'i_restaurant_outlined': Icons.restaurant_outlined,
  'i_local_drink_outlined': Icons.local_drink_outlined,
  'i_checkroom_outlined': Icons.checkroom_outlined,
  'i_medical_services_outlined': Icons.medical_services_outlined,
  'i_healing_outlined': Icons.healing_outlined,
  'i_psychology_outlined': Icons.psychology_outlined,
  'i_lightbulb_outline': Icons.lightbulb_outline,
  'i_star_border': Icons.star_border,
  'i_wb_sunny_outlined': Icons.wb_sunny_outlined,
  'i_bedtime_outlined': Icons.bedtime_outlined,
  'i_calendar_month_outlined': Icons.calendar_month_outlined,
  'i_schedule_outlined': Icons.schedule_outlined,
  'i_public_outlined': Icons.public_outlined,
  'i_travel_explore_outlined': Icons.travel_explore_outlined,
  'i_directions_car_outlined': Icons.directions_car_outlined,
  'i_phone_android_outlined': Icons.phone_android_outlined,
  'i_campaign_outlined': Icons.campaign_outlined,
  'i_record_voice_over_outlined': Icons.record_voice_over_outlined,
  'i_mic_none_outlined': Icons.mic_none_outlined,
  'i_edit_note_outlined': Icons.edit_note_outlined,
  'i_question_answer_outlined': Icons.question_answer_outlined,
  'i_help_outline': Icons.help_outline,
  'i_warning_amber_outlined': Icons.warning_amber_outlined,
  'i_block_outlined': Icons.block_outlined,
  'i_verified_outlined': Icons.verified_outlined,
  'i_security_outlined': Icons.security_outlined,
  'i_eco_outlined': Icons.eco_outlined,
  'i_park_outlined': Icons.park_outlined,
  'i_pets_outlined': Icons.pets_outlined,
  'i_agriculture_outlined': Icons.agriculture_outlined,
  'i_landscape_outlined': Icons.landscape_outlined,
  'i_terrain_outlined': Icons.terrain_outlined,
  'i_celebration_outlined': Icons.celebration_outlined,
  'i_card_giftcard_outlined': Icons.card_giftcard_outlined,
  'i_savings_outlined': Icons.savings_outlined,
  'i_receipt_long_outlined': Icons.receipt_long_outlined,
  'i_inventory_2_outlined': Icons.inventory_2_outlined,
  'i_bookmark_border': Icons.bookmark_border,
  'i_label_outline': Icons.label_outline,
  'i_flag_outlined': Icons.flag_outlined,
  'i_explore_outlined': Icons.explore_outlined,
  'i_diamond_outlined': Icons.diamond_outlined,
  'i_emoji_events_outlined': Icons.emoji_events_outlined,
  'i_front_hand_outlined': Icons.front_hand_outlined,
  'i_clean_hands_outlined': Icons.clean_hands_outlined,
  'i_self_improvement': Icons.self_improvement,
  'i_visibility_outlined': Icons.visibility_outlined,
  'i_hearing_outlined': Icons.hearing_outlined,
};

/// A sheet with all the icons; returns the key of the chosen one.
Future<String?> pickChapterIcon(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('اختر رمز الباب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 6,
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final e in chapterIcons.entries)
                      IconButton(
                        icon: Icon(e.value, size: 28),
                        onPressed: () => Navigator.pop(ctx, e.key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

IconData chapterIcon(String key) {
  final chosen = chapterIcons[key];
  if (chosen != null) return chosen;
  switch (key) {
    case 'aqeedah':
      return Icons.shield_outlined;
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
    case 'manhaj':
      return Icons.alt_route;
    case 'mawaiz':
      return Icons.spa_outlined;
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
                  if (isRecent(fatwa.date)) ...[
                    const SizedBox(width: 6),
                    const _Chip(text: 'جديد', color: Color(0xFFD9534F)),
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

/// True when the date (yyyy-MM-dd) is within the last 7 days.
bool isRecent(String date) {
  final d = DateTime.tryParse(date);
  return d != null && DateTime.now().difference(d).inDays < 7;
}

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
