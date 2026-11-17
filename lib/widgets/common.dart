import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/hijri.dart';
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
    case 'instagram':
      return Icons.camera_alt_outlined;
    case 'tiktok':
      return Icons.music_note_outlined;
    case 'snapchat':
      return Icons.photo_camera_front_outlined;
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
                    Flexible(child: _Chip(text: repo.chapterName(fatwa.chapter), color: kGoldChip)),
                  ],
                  if (isRecent(fatwa.date)) ...[
                    const SizedBox(width: 6),
                    const _Chip(text: 'جديد', color: Color(0xFFD9534F)),
                  ],
                  const Spacer(),
                  Icon(Icons.schedule, size: 13, color: scheme.onSurface.withValues(alpha: 0.45)),
                  const SizedBox(width: 3),
                  Text(readTimeText(readMinutes(fatwa)),
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurface.withValues(alpha: 0.55))),
                  if (repo.isFavorite(fatwa.id)) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.bookmark, size: 18, color: kGoldChip),
                  ],
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
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: color)),
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


// ------------------------------------------------------------ App logo
/// The logos the reader may choose from (settings → «شعار التطبيق»).
/// The first is the official one; the green and the third are alternatives.
const logoAssets = ['assets/icon/logo_2.jpg', 'assets/icon/icon.png', 'assets/icon/logo_3.jpg'];

/// Which logo is shown inside the app (and as the phone icon on Android).
final appLogo = ValueNotifier<int>(0);

/// The chosen logo, updated at once when the choice changes.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: appLogo,
        builder: (_, i, __) => Image.asset(logoAssets[i.clamp(0, logoAssets.length - 1)],
            width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round()),
      );
}


// ------------------------------------------------------------ small helpers
/// Reading time of an answer, in minutes (about 180 words a minute).
int readMinutes(Fatwa f) => ('${f.question} ${f.answer}'.split(RegExp(r'\s+')).length / 180).ceil().clamp(1, 999);

/// «دقيقة قراءة» · «دقيقتان» · «3 دقائق».
String readTimeText(int m) => m == 1
    ? 'دقيقة قراءة'
    : m == 2
        ? 'دقيقتان'
        : m <= 10
            ? '$m دقائق'
            : '$m دقيقة';

/// «اليوم» · «أمس» · «قبل 3 أيام», then the Hijri date.
String friendlyDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days <= 0) return 'اليوم';
  if (days == 1) return 'أمس';
  if (days == 2) return 'قبل يومين';
  if (days <= 10) return 'قبل $days أيام';
  final h = Hijri.from(d);
  return '${h.day} ${Hijri.months[(h.month - 1).clamp(0, 11)]} ${h.year} هـ';
}

/// A post's text for a small card: long links become «🔗 رابط».
String withShortLinks(String text) =>
    text.replaceAll(RegExp(r'(https?://|www\.|t\.me/)\S+'), '🔗 رابط').replaceAll(RegExp(r'\n{3,}'), '\n\n');

/// Text without emoji and symbols, for short labels.
String withoutSymbols(String text) => text
    .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]', unicode: true), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A grey shape that shines softly while something loads.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;
  const Skeleton({super.key, required this.height, this.width, this.radius = 12});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
    ..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF2A3236) : const Color(0xFFE6E9EA);
    final shine = dark ? const Color(0xFF3A4448) : const Color(0xFFF6F7F7);
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) => Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          gradient: LinearGradient(
            begin: Alignment(-1.5 + 3 * _a.value, 0),
            end: Alignment(-0.5 + 3 * _a.value, 0),
            colors: [base, shine, base],
          ),
        ),
      ),
    );
  }
}

/// A list card that is still loading.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  @override
  Widget build(BuildContext context) => const Card(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Skeleton(height: 16, width: 90, radius: 8),
            SizedBox(height: 10),
            Skeleton(height: 18),
            SizedBox(height: 8),
            Skeleton(height: 14, width: 220, radius: 8),
          ]),
        ),
      );
}
