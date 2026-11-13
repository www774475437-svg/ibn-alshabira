import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'book_reader_screen.dart';

/// «عن الشيخ»
class AboutSheikhScreen extends StatelessWidget {
  const AboutSheikhScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('عن الشيخ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ClipOval(child: Image.asset('assets/icon/icon.png', width: 110, height: 110)),
          ),
          const SizedBox(height: 16),
          const Text('الشيخ قائد بن غانم الشابرة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const Text('حفظه الله',
              textAlign: TextAlign.center, style: TextStyle(color: kGoldChip, fontSize: 16)),
          const SizedBox(height: 20),
          const _AboutText(),
          const SizedBox(height: 12),
          for (final b in repo.books.where((b) => b.title.contains('ترجمة')))
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book, color: kGold),
                title: const Text('اقرأ ترجمة الشيخ كاملة'),
                subtitle: Text(b.title),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => kIsWeb
                    ? openUrl(context, b.previewUrl)
                    : Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => BookReaderScreen(book: b))),
              ),
            ),
          const SizedBox(height: 12),
          for (final l in repo.sheikhLinks)
            Card(
              child: ListTile(
                leading: Icon(platformIcon(l.platform), color: kGold),
                title: Text(l.name),
                subtitle: l.url.isEmpty ? const Text('يُضاف قريباً') : null,
                enabled: l.url.isNotEmpty,
                onTap: () => openUrl(context, l.url),
              ),
            ),
        ],
      ),
    );
  }
}

/// QR code of the website, to print or share in groups.
class QrScreen extends StatelessWidget {
  const QrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رمز الموقع (QR)')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text('صوّر هذا الرمز بكاميرا الجوال ليفتح موقع «ابن الشابرة»',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.7)),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: kGold, width: 3),
              ),
              child: QrImageView(
                data: AppConfig.siteUrl,
                size: 240,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: kGreen),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle, color: kGreen),
                embeddedImage: const AssetImage('assets/icon/icon.png'),
                embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(52, 52)),
                errorCorrectionLevel: QrErrorCorrectLevel.H,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(AppConfig.siteUrl,
              textAlign: TextAlign.center, textDirection: TextDirection.ltr),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('انشر رابط التطبيق والموقع'),
            onPressed: () => Share.share(shareAppText()),
          ),
        ],
      ),
    );
  }
}

String shareAppText() => '📚 تطبيق «ابن الشابرة»\n'
    'أجوبة ومقالات وكتب الشيخ قائد بن غانم الشابرة حفظه الله\n\n'
    '🌐 الموقع:\n${AppConfig.siteUrl}\n\n'
    '📱 تحميل التطبيق لأندرويد:\n${AppConfig.apkUrl}';

/// Backup: export saved items/settings as text, import by pasting.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    void toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    return Scaffold(
      appBar: AppBar(title: const Text('النسخة الاحتياطية')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'احفظ محفوظاتك وقائمة «اقرأ لاحقاً» وإعداداتك، ثم أرجعها إذا غيّرت جوالك.',
            style: TextStyle(fontSize: 16, height: 1.8),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.upload),
            label: const Text('حفظ نسخة احتياطية (مشاركة أو إرسال)'),
            onPressed: () => Share.share(repo.exportBackup(), subject: 'نسخة ابن الشابرة الاحتياطية'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('نسخ النسخة الاحتياطية'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: repo.exportBackup()));
              toast('تم النسخ، احفظه في الملاحظات أو أرسله لنفسك');
            },
          ),
          const Divider(height: 40),
          const Text('للاسترجاع: انسخ نص النسخة الاحتياطية، ثم اضغط:',
              style: TextStyle(fontSize: 16)),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.download),
            label: const Text('استرجاع من النص المنسوخ'),
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              final ok = repo.importBackup(data?.text ?? '');
              toast(ok ? 'تم الاسترجاع بنجاح ✅' : 'النص المنسوخ ليس نسخة احتياطية صحيحة');
            },
          ),
        ],
      ),
    );
  }
}

/// Placeholder for features that need the online account (coming next).
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String text;
  const ComingSoonScreen({super.key, required this.title, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(icon, size: 72, color: kGold),
          const SizedBox(height: 16),
          const Text('عند التوفر بإذن الله',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.8)),
        ],
      ),
    );
  }
}


class _AboutText extends StatelessWidget {
  const _AboutText();

  static const _default = 'من محافظة إب باليمن، ومن طلاب الشيخ يحيى بن علي الحجوري.\n\n'
      'يجمع هذا التطبيق أجوبته ومقالاته وكتبه ورسائله الدعوية، '
      'مرتّبة على الأبواب ليسهل الرجوع إليها.';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Cloud.instance,
        builder: (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              Cloud.instance.aboutText.isEmpty ? _default : Cloud.instance.aboutText,
              style: const TextStyle(fontSize: 16, height: 1.9),
            ),
          ),
        ),
      );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سياسة الخصوصية')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          SelectableText(
            'تطبيق «ابن الشابرة» تطبيق علمي دعوي مجاني، لا إعلانات فيه، ولا تُباع بيانات مستخدميه ولا تُشارك مع أحد.\n\n'
            '• دون تسجيل: تُحفظ المحفوظات والإعدادات وسجل القراءة في جوالك فقط.\n\n'
            '• عند التسجيل: يُحفظ البريد والاسم (وصورة حساب جوجل إن دخلت به) لتعريف حسابك، '
            'وتُحفظ محفوظاتك وقائمة «اقرأ لاحقاً» على حسابك لترجع إليك في أي جوال.\n\n'
            '• «اسأل الشيخ»: يُحفظ نص سؤالك ليراه الشيخ والمشرفون ويردّوا عليه. '
            'وإذا نُشر الجواب في التطبيق فإنه يُنشر دون اسمك أو بريدك.\n\n'
            '• الإحصائيات: يُحسب عدد مرات فتح كل جواب، وتصويت «هل أفادك الجواب؟»، '
            'والكلمات التي لا توجد لها نتيجة في البحث، دون ربطها بحسابك.\n\n'
            '• تُحفظ البيانات في خدمة Firebase من جوجل.\n\n'
            '• لحذف حسابك وبياناته، راسل المطوّر من «تواصل مع المطوّر».',
            style: TextStyle(fontSize: 16, height: 1.9),
          ),
        ],
      ),
    );
  }
}

/// «ما الجديد»: what each version added, newest first.
const whatsNew = <(String, List<String>)>[
  (
    '1.9.0',
    [
      'البحث داخل الجواب: زر العدسة أعلى الجواب يظلّل الكلمة التي تبحث عنها.',
      'تقدّمك في كل باب: كم قرأت من أجوبته، وزر «ما لم أقرأه».',
      'عند اختيار «لم يفدني» يمكنك ذكر السبب ليصل إلى المشرفين.',
      'صفحة «ما الجديد».',
    ]
  ),
  (
    '1.8',
    [
      'الموقع صار مثل التطبيق: التسجيل، «اسأل الشيخ»، ولوحة الإدارة.',
      'خط جديد واضح للعناوين.',
      'خانة «الإدارة» في الشريط السفلي للمشرفين.',
      'تقييم الجواب مرة واحدة، وعدّ المشاهدات بدقة.',
      'وقت صدور التحديث الجديد.',
    ]
  ),
  (
    '1.7',
    [
      'صلاحيات المشرف والمحرّر، والمسودات، وسجل التعديلات.',
      'تثبيت الأجوبة في الرئيسية، وتعديل الأبواب و«عن الشيخ».',
      'تحسينات «اسأل الشيخ»: اختيار الباب، والأجوبة المشابهة.',
    ]
  ),
];

class WhatsNewScreen extends StatelessWidget {
  const WhatsNewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ما الجديد')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (version, items) in whatsNew)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('النسخة $version',
                        style: const TextStyle(
                            fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 17, color: kGoldChip)),
                    const SizedBox(height: 8),
                    for (final t in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 8, left: 8),
                              child: Icon(Icons.circle, size: 7, color: kGold),
                            ),
                            Expanded(child: Text(t, style: const TextStyle(height: 1.7))),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown instead of the app when this build is older than the minimum
/// the developer allows.
class MustUpdateScreen extends StatelessWidget {
  const MustUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.system_update, size: 72, color: kGold),
              const SizedBox(height: 16),
              const Text('يلزم تحديث التطبيق',
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('هذه النسخة قديمة ولم تعد تعمل. حمّل النسخة الجديدة لتواصل استعمال التطبيق.',
                  textAlign: TextAlign.center, style: TextStyle(height: 1.8, fontSize: 16)),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                icon: const Icon(Icons.download),
                label: const Text('تحميل النسخة الجديدة', style: TextStyle(fontSize: 17)),
                onPressed: () => openUrl(context, AppConfig.apkUrl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
