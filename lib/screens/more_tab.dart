import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/notifications.dart';

import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'ask_screen.dart';
import 'audio_library.dart';
import 'channel_screen.dart';
import 'account_screens.dart';
import 'accounts_screen.dart';
import 'adhkar_screen.dart';
import 'quran_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'content_screens.dart';
import 'extra_screens.dart';
import 'review_screen.dart';
import '../services/cloud.dart';

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListenableBuilder(
        listenable: Listenable.merge([repo, Cloud.instance]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _ReaderStats(count: repo.readThisMonth),
            _BigCard(
              icon: Icons.auto_stories_outlined,
              title: 'المصحف',
              subtitle: 'مصحف المدينة برواية حفص، بلا إنترنت',
              color: kGold,
              fg: const Color(0xFF1B1B1B),
              iconColor: const Color(0xFF1B1B1B),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuranScreen())),
            ),
            _BigCard(
              icon: Icons.spa_outlined,
              title: 'الأذكار',
              subtitle: 'حصن المسلم كاملاً، وعدّاد التسبيح',
              color: const Color(0xFF2E7D32),
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdhkarScreen())),
            ),
            // A small gold strip: channels and accounts of the sheikh and of those the staff add.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: kGold.withValues(alpha: 0.16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: kGold),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const AccountsScreen())),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(Icons.campaign_outlined, color: kGoldChip, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('قنوات وحسابات أنصح بها',
                              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                        Icon(Icons.chevron_left, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('أرسل التطبيق لصديق'),
                onPressed: () {
                  Cloud.instance.countAppShare();
                  Share.share(shareAppText());
                },
              ),
            ),
            const _Group('الحساب'),
            _Section(children: [
              ListTile(
                leading: const _IconBox(Icons.insights_outlined),
                title: const Text('قراءتي'),
                subtitle: const Text('كم قرأت، وكم بقي في كل باب'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const MyReadingScreen())),
              ),
              ListenableBuilder(
                listenable: Cloud.instance,
                builder: (context, _) {
                  final u = Cloud.instance.user;
                  return ListTile(
                    leading: Badge(
                      isLabelVisible: Cloud.instance.newQuestions > 0,
                      label: Text('${Cloud.instance.newQuestions}'),
                      child: const _IconBox(Icons.account_circle_outlined),
                    ),
                    title: Text(u == null ? 'تسجيل الدخول أو إنشاء حساب' : (u.displayName ?? 'حسابي')),
                    subtitle: u == null ? null : Text(Cloud.instance.isAdmin ? (Cloud.instance.isFullAdmin ? 'مشرف · لوحة الإدارة' : 'محرّر · لوحة المحرّر') : (u.email ?? '')),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const AccountScreen())),
                  );
                },
              ),
              ListTile(
                leading: const _IconBox(Icons.trending_up),
                title: const Text('الأكثر قراءة'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MostReadScreen())),
              ),
            ]),
            if (Cloud.instance.ready && Cloud.instance.isAdmin) ...[
              const _Group('أدوات المشرفين'),
              _Section(children: [
                if (Cloud.instance.isFullAdmin) ...[
                  SwitchListTile(
                    secondary: const _IconBox(Icons.auto_awesome_outlined),
                    title: const Text('الذكاء الاصطناعي في بحث كتب الثقات'),
                    subtitle: const Text('يقسّم السؤال إلى مسائله'),
                    value: Cloud.instance.aiEnabled,
                    onChanged: (v) => Cloud.instance.setConfig(
                        'ai', {'enabled': v, 'summary': Cloud.instance.aiSummary}, 'تشغيل/إيقاف الذكاء'),
                  ),
                  SwitchListTile(
                    secondary: const _IconBox(Icons.short_text),
                    title: const Text('الحكم المختصر الآلي'),
                    subtitle: const Text('تلخيص من نصوص الشيخ؛ أطفئه لتُعرض النصوص وحدها'),
                    value: Cloud.instance.aiSummary,
                    onChanged: Cloud.instance.aiEnabled
                        ? (v) => Cloud.instance
                            .setConfig('ai', {'enabled': true, 'summary': v}, 'تشغيل/إيقاف الحكم المختصر')
                        : null,
                  ),
                ],
                ListTile(
                  leading: const _IconBox(Icons.rule_folder_outlined),
                  title: const Text('لم يُتحقق منها'),
                  subtitle: const Text('راجع المنشورات واحداً واحداً: صحّح، انقل، ثم تحقّق'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const ReviewScreen())),
                ),
                ListTile(
                  leading: const _IconBox(Icons.visibility_off_outlined),
                  title: const Text('المنشورات المخفية'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const HiddenScreen())),
                ),
              ]),
            ],
            const _Group('التعريف بالشيخ وحساباته'),
            _Section(children: [
              ListTile(
                leading: const _IconBox(Icons.person_outline),
                title: const Text('عن الشيخ'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AboutSheikhScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.campaign_outlined),
                title: const Text('من قناة الشيخ'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ChannelScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.headphones),
                title: const Text('المكتبة الصوتية'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AudioLibraryScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.play_circle_outline),
                title: const Text('المرئيات'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const VideosScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.groups_outlined),
                title: const Text('المشايخ الثقات المعتمدون'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ScholarsScreen())),
              ),
              if (Cloud.instance.schedule.trim().isNotEmpty)
                ListTile(
                  leading: const _IconBox(Icons.event_available_outlined),
                  title: const Text('جدول دروس الشيخ'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('جدول دروس الشيخ'),
                      content: SingleChildScrollView(
                        child: SelectableText(Cloud.instance.schedule, style: const TextStyle(height: 1.9)),
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))],
                    ),
                  ),
                ),
              ExpansionTile(
                leading: const _IconBox(Icons.link),
                title: const Text('حسابات الشيخ الرسمية'),
                shape: const Border(),
                children: [
                  for (final l in repo.sheikhLinks)
                    ListTile(
                      leading: _IconBox(platformIcon(l.platform)),
                      title: Text(l.name),
                      subtitle: l.url.isEmpty ? const Text('يُضاف قريباً') : null,
                      trailing: const Icon(Icons.chevron_left),
                      enabled: l.url.isNotEmpty,
                      onTap: () => openUrl(context, l.url),
                    ),
                ],
              ),
            ]),
            const _Group('التواصل'),
            _Section(children: [
              ListTile(
                leading: const _IconBox(Icons.forum_outlined),
                title: const Text('اسأل الشيخ'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AskScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.code),
                title: const Text('تواصل مع المطوّر'),
                subtitle: Text(repo.developerName),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => openUrl(context, repo.developerUrl),
              ),
            ]),
            const _Group('الإعدادات'),
            _Section(children: [
              if (!kIsWeb) ...[
                SwitchListTile(
                  secondary: const _IconBox(Icons.notifications_active_outlined),
                  title: const Text('تنبيه «جواب اليوم»'),
                  value: repo.dailyNotification,
                  onChanged: (v) {
                    repo.setDailyNotification(v);
                    DailyNotifications.setEnabled(v,
                        hour: repo.notifyHour, minute: repo.notifyMinute);
                  },
                ),
                ListTile(
                  leading: const _IconBox(Icons.schedule),
                  title: const Text('وقت التنبيه'),
                  enabled: repo.dailyNotification,
                  trailing: Text(
                    TimeOfDay(hour: repo.notifyHour, minute: repo.notifyMinute).format(context),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(hour: repo.notifyHour, minute: repo.notifyMinute),
                    );
                    if (t == null) return;
                    repo.setNotifyTime(t.hour, t.minute);
                    DailyNotifications.setEnabled(true, hour: t.hour, minute: t.minute);
                  },
                ),
              ],
              ListTile(
                leading: const _IconBox(Icons.palette_outlined),
                title: const Text('ألوان التطبيق'),
                trailing: DropdownButton<String>(
                  value: repo.palette,
                  underline: const SizedBox(),
                  onChanged: (p) => repo.setPalette(p ?? 'teal'),
                  items: const [
                    DropdownMenuItem(value: 'teal', child: Text('فيروزي وذهبي')),
                    DropdownMenuItem(value: 'green', child: Text('أخضر وذهبي')),
                    DropdownMenuItem(value: 'black', child: Text('أسود وذهبي')),
                    DropdownMenuItem(value: 'paper', child: Text('ورقي هادئ')),
                  ],
                ),
              ),
              ListTile(
                leading: const _IconBox(Icons.font_download_outlined),
                title: const Text('نوع الخط'),
                trailing: DropdownButton<String>(
                  value: repo.fontFamily,
                  underline: const SizedBox(),
                  onChanged: (f) => repo.setFontFamily(f ?? ''),
                  items: const [
                    DropdownMenuItem(value: 'Amiri', child: Text('أميري', style: TextStyle(fontFamily: 'Amiri'))),
                    DropdownMenuItem(value: 'Tajawal', child: Text('تجوّل (واضح)', style: TextStyle(fontFamily: 'Tajawal'))),
                    DropdownMenuItem(value: 'ReemKufi', child: Text('ريم كوفي', style: TextStyle(fontFamily: 'ReemKufi'))),
                    DropdownMenuItem(value: '', child: Text('خط الجهاز')),
                  ],
                ),
              ),
              ListTile(
                leading: const _IconBox(Icons.dark_mode_outlined),
                title: const Text('المظهر'),
                // One menu: 3 = dark after sunset, light by day.
                trailing: DropdownButton<int>(
                  value: repo.autoNight ? 3 : repo.themeMode.index,
                  underline: const SizedBox(),
                  onChanged: (v) {
                    if (v == 3) {
                      repo.setAutoNight(true);
                    } else {
                      repo.setAutoNight(false);
                      repo.setThemeMode(ThemeMode.values[v ?? 0]);
                    }
                  },
                  items: [
                    DropdownMenuItem(value: ThemeMode.system.index, child: const Text('حسب الجهاز')),
                    DropdownMenuItem(value: ThemeMode.light.index, child: const Text('فاتح')),
                    DropdownMenuItem(value: ThemeMode.dark.index, child: const Text('داكن')),
                    const DropdownMenuItem(value: 3, child: Text('داكن بعد المغرب')),
                  ],
                ),
              ),
              SwitchListTile(
                secondary: const _IconBox(Icons.text_increase),
                title: const Text('الخط الكبير'),
                subtitle: const Text('لمن يحتاج خطاً أوضح'),
                value: repo.fontScale >= 1.3,
                onChanged: (v) {
                  repo.setFontScale(v ? 1.35 : 1.0);
                  repo.saveReadingScale(v ? 1.3 : 1.0);
                },
              ),
              ListTile(
                leading: const _IconBox(Icons.local_fire_department_outlined),
                title: const Text('الوِرد اليومي من الأجوبة'),
                trailing: DropdownButton<int>(
                  value: const [0, 1, 3, 5, 10].contains(repo.wirdTarget) ? repo.wirdTarget : 0,
                  underline: const SizedBox(),
                  onChanged: (n) => repo.setWirdTarget(n ?? 0),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('بدون')),
                    DropdownMenuItem(value: 1, child: Text('جواب')),
                    DropdownMenuItem(value: 3, child: Text('3 أجوبة')),
                    DropdownMenuItem(value: 5, child: Text('5 أجوبة')),
                    DropdownMenuItem(value: 10, child: Text('10 أجوبة')),
                  ],
                ),
              ),
              ListTile(
                leading: const _IconBox(Icons.format_size),
                title: const Text('حجم الخط'),
                subtitle: Slider(
                  value: repo.fontScale,
                  min: 0.85,
                  max: 1.5,
                  divisions: 13,
                  onChanged: repo.setFontScale,
                ),
              ),
            ]),
            const _Group('التطبيق والموقع'),
            _Section(children: [
              ListTile(
                leading: const _IconBox(Icons.qr_code_2),
                title: const Text('رمز الموقع (QR) ونشر التطبيق'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const QrScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.backup_outlined),
                title: const Text('النسخة الاحتياطية'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const BackupScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.android),
                title: const Text('تحميل التطبيق لأندرويد'),
                trailing: const Icon(Icons.download),
                onTap: () => openUrl(context, AppConfig.apkUrl),
              ),
              if (AppConfig.playStoreUrl.isNotEmpty)
                ListTile(
                  leading: const _IconBox(Icons.shop),
                  title: const Text('جوجل بلاي'),
                  onTap: () => openUrl(context, AppConfig.playStoreUrl),
                ),
              if (AppConfig.appStoreUrl.isNotEmpty)
                ListTile(
                  leading: const _IconBox(Icons.apple),
                  title: const Text('آبل ستور'),
                  onTap: () => openUrl(context, AppConfig.appStoreUrl),
                ),
              ListTile(
                leading: const _IconBox(Icons.language),
                title: const Text('موقع التطبيق'),
                subtitle: const Text(AppConfig.siteUrl, textDirection: TextDirection.ltr),
                onTap: () => openUrl(context, AppConfig.siteUrl),
              ),
            ]),
            const _Group('عن التطبيق'),
            _Section(children: [
              ListTile(
                leading: const _IconBox(Icons.lightbulb_outline),
                title: const Text('اقتراح للمطوّر'),
                subtitle: const Text('فكرة أو ملاحظة تحسّن التطبيق'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () async {
                  final c = TextEditingController();
                  final text = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('اقتراح للمطوّر'),
                      content: TextField(
                        controller: c,
                        autofocus: true,
                        maxLines: 5,
                        maxLength: 1500,
                        decoration: const InputDecoration(
                            hintText: 'اكتب اقتراحك أو ملاحظتك', border: OutlineInputBorder()),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('إرسال')),
                      ],
                    ),
                  );
                  if (text == null || text.trim().length < 3) return;
                  final err = await Cloud.instance.suggest(text);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(err ?? 'وصل اقتراحك، جزاك الله خيراً')));
                },
              ),
              ListTile(
                leading: const _IconBox(Icons.new_releases_outlined),
                title: const Text('ما الجديد'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const WhatsNewScreen())),
              ),
              ListTile(
                leading: const _IconBox(Icons.privacy_tip_outlined),
                title: const Text('سياسة الخصوصية'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const PrivacyScreen())),
              ),
            ]),
            const SizedBox(height: 8),
            const _Section(children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'تطبيق «ابن الشابرة» يجمع أجوبة ومقالات وكتب ورسائل الشيخ '
                  'قايد بن غانم الشابرة حفظه الله، من اليمن، '
                  'مرتّبة على الأبواب مع البحث بالموضوع.\n\n'
                  'الإصدار ${AppConfig.version} (${AppConfig.buildNumber})',
                  style: TextStyle(height: 1.8),
                ),
              ),
            ]),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

Widget _soon(BuildContext context, IconData icon, String title, String text) => ListTile(
      leading: _IconBox(icon),
      title: Text(title),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: kGold.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('قريباً', style: TextStyle(fontSize: 12, color: kGoldChip)),
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComingSoonScreen(title: title, icon: icon, text: text))),
    );

/// A wide coloured card: the mushaf and the adhkar look alike.
class _BigCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color fg;
  final Color iconColor;
  final VoidCallback onTap;
  const _BigCard(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.onTap,
      this.fg = Colors.white,
      this.iconColor = kGold});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: iconColor, size: 34),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                fontFamily: 'Tajawal',
                                color: fg,
                                fontSize: 19,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(color: fg, fontSize: 13.5)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left, color: fg),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ReaderStats extends StatelessWidget {
  final int count;
  const _ReaderStats({required this.count});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Card(
          color: brandColor(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.auto_stories, color: kGold, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    count == 0
                        ? 'لم تقرأ أي جواب هذا الشهر بعد'
                        : 'الأجوبة التي قرأتها هذا الشهر: $count\nبارك الله فيك',
                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Group extends StatelessWidget {
  final String text;
  const _Group(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
        child: Text(text, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
      );
}

class _Section extends StatelessWidget {
  final List<Widget> children;
  const _Section({required this.children});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  const _IconBox(this.icon);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: brandColor(context),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: kGold, size: 20),
      );
}
