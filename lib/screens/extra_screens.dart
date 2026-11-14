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
          const Text('الشيخ قايد بن غانم الشابرة',
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
            onPressed: () {
              Cloud.instance.countAppShare();
              Share.share(shareAppText());
            },
          ),
        ],
      ),
    );
  }
}

String shareAppText() => '📚 تطبيق «ابن الشابرة»\n'
    'أجوبة ومقالات وكتب الشيخ قايد بن غانم الشابرة حفظه الله\n\n'
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

  static const _default = 'من اليمن، ومن طلاب الشيخ يحيى بن علي الحجوري.\n\n'
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
    '3.5.0',
    [
      '«بحث الفتاوى من كتب الثقات» في تطبيق أندرويد: اكتب سؤالك كما تريد، فيُقسَّم إلى مسائله، ويُبحث لكل مسألة عند ابن عثيمين ثم من بعده.',
      'خلاصة مختصرة لكلام الشيخ في كل مسألة، مبنية على نصوصه المنقولة وحدها، وتحتها النص بالكتاب والصفحة.',
      'زر «إبلاغ عن خطأ في التلخيص»، وللمشرفين زرّان لإيقاف الذكاء أو الخلاصة.',
    ],
  ),
  (
    '3.4.0',
    [
      'المصحف: إصلاح سقوط نص الآيات التي تبدأ بعلامة ربع الحزب ۞.',
      'المصحف: اسم الجزء والسورة أعلى الصفحة، ورقم الصفحة في إطار ذهبي أسفلها.',
      '«المشايخ الثقات»: اثنا عشر عالماً مع ترجمة كل واحد وقائمة مؤلفاته، وكل كتاب يُفتح في «تراث».',
      '«بحث الفتاوى من كتب الثقات»: زر أخضر في صفحة البحث، يبحث في كتب ابن عثيمين ثم ابن باز ثم الفوزان ثم ابن تيمية ثم ابن القيم، ويعرض كلام الشيخ بنصّه مع الكتاب والصفحة.',
    ],
  ),
  (
    '3.3.0',
    [
      'الموقع صار على عنوانه الخاص: ibnalshabira.com',
      'شاشات ترحيب جديدة.',
      'زر «حفظ» واضح لاسمك أو كنيتك في صفحة الحساب.',
      'بطاقة «المصحف» ذهبية في «المزيد»، وخيار «داكن بعد المغرب» صار داخل قائمة «المظهر».',
      'مربعات الأذكار تُظهر كم أتممت اليوم.',
      'اسحب الرئيسية للأسفل لجلب الجديد.',
      'للمشرفين: إضافة باب جديد أثناء المراجعة، واختيار رمز لكل باب من مجموعة كبيرة.',
      'شاشة تحميل بالشعار عند فتح الموقع.',
    ],
  ),
  (
    '3.2.0',
    [
      'المصحف بخط مصحف المدينة ونصّه الرسمي: علامات الوقف والتشكيل في مواضعها الصحيحة.',
      'داخل المصحف: زر إعدادات (صفحة ليلية، ختمة بوِرد يومي)، و«القراءة فقط» بضغطتين على الصفحة، ومشاركة الآية.',
      'الشريط السفلي: الرئيسية، الكتب، المحفوظات، اسأل الشيخ، المشايخ الثقات، المزيد (و«الإدارة» للمشرفين).',
      'المصحف والأذكار بطاقتان في «المزيد» بعد بطاقة قراءتك.',
      'الأذكار بشكل جديد: أربعة مربعات (الصباح، المساء، النوم، بعد الصلاة) ثم الفهرس.',
      'المرئيات لا تختفي: تبقى آخر قائمة محفوظة إذا تعذّر جلب الجديد.',
      'الموقع يفتح أسرع: تظهر أحدث الأجوبة فوراً وتُحمَّل بقية المكتبة في الخلفية.',
      'زر «أرسل التطبيق لصديق» في «المزيد».',
    ],
  ),
  (
    '3.1.0',
    [
      'الآيات المذكورة في الجواب تُفتح في المصحف على موضعها.',
      '«الأكثر بحثاً هذا الأسبوع» في الرئيسية.',
      'زر صغير «أكمل من حيث توقفت» في النصوص الطويلة، وشريط يبيّن كم قرأت.',
      'الوضع الليلي التلقائي بعد المغرب (اختياري من الإعدادات).',
    ]
  ),
  (
    '3.0.0',
    [
      'المصحف: بالرسم العثماني، صفحة صفحة كالمصحف الورقي، مع الفهرس والبحث.',
      'اضغط مطولاً على أي آية: التفسير الميسر، وعلامات ملوّنة تحفظ وقتها.',
      'الأذكار: «حصن المسلم» كاملاً بترتيبه، مع عدّاد التسبيح.',
      'شريط سفلي جديد: الرئيسية، المصحف، المحفوظات، الكتب، المزيد.',
      'البحث يُفتح من خانة البحث أعلى الرئيسية.',
      'روابط قصيرة للأجوبة، ورمز QR في البطاقة المصوّرة.',
    ]
  ),
  (
    '2.1.0',
    [
      'البحث صار أدق: الكلمة التي تبحث عنها فقط، وما كان في العنوان أو السؤال يأتي أولاً.',
      '«بحث بالمعنى» زر اختياري في صفحة البحث، مع تصفية: أجوبة أو مقالات.',
      'البطاقة المصوّرة تحمل السؤال والجواب كاملين في صور مرقّمة.',
      'صفحة «قراءتي»: كم قرأت وكم بقي في كل باب.',
      'اسمك أو كنيتك اختيارياً مع أسئلتك للشيخ.',
    ]
  ),
  (
    '2.0.0',
    [
      'اكتب سؤالك بكلامك العادي، فيعرض لك التطبيق أقرب كلام الشيخ إليه بنصّه.',
      'البحث الصوتي: اضغط الميكروفون وقل سؤالك.',
      '«اقرأ لي»: يقرأ لك الجواب بصوت الهاتف.',
      'الوِرد اليومي من الأجوبة مع عدد أيامك المتتالية.',
      'ملاحظاتك الخاصة على أي جواب.',
      'التاريخ الهجري، و«أُضيف حديثاً» في الرئيسية.',
      'زر «الخط الكبير» في الإعدادات.',
      'منشورات الشيخ الجديدة تصل كل يوم دون تحديث التطبيق.',
      'صندوق «اقتراح للمطوّر» في صفحة المزيد.',
    ]
  ),
  (
    '1.14.0',
    [
      'كل منشورات قناة الشيخ على تيليجرام (قرابة 4900) صارت أجوبة ومقالات في الأبواب.',
      'بابان جديدان: «المنهج والردود» و«المواعظ والرقائق».',
      'الجواب يُفتح من أوله دائماً.',
      'تحسين فتح الموقع على أجهزة سامسونج والآيفون.',
    ]
  ),
  (
    '1.13.0',
    [
      'أجوبة الشيخ ومقالاته من قناته على تيليجرام صارت داخل الأبواب، كل سؤال مع جوابه.',
      'عرض جديد للجواب: السؤال في إطار، ثم الجواب بفقرات واضحة، مع الباب ووقت القراءة والمصدر.',
      'المرئيات تعمل داخل التطبيق والموقع، مع زر أحمر للمشاهدة على يوتيوب.',
    ]
  ),
  (
    '1.12.0',
    [
      'منشورات قناة الشيخ على تيليجرام داخل التطبيق، مع البحث فيها.',
      'المكتبة الصوتية لدروس الشيخ، تكمل من حيث توقفت.',
      'البحث بالمعنى: من بحث بـ«الحواجب» يجد أجوبة «النمص».',
      'تنبيه عند وصول جواب سؤالك، وللمشرفين عند وصول سؤال جديد.',
    ]
  ),
  (
    '1.11.0',
    [
      'أبواب فرعية داخل كل باب (مثل: الأذان، الجمعة).',
      'مسارات التعلّم: أجوبة مرتبة تتابعها خطوة خطوة.',
      'خطة قراءة لكتب الشيخ: تختار الكتاب وعدد الصفحات كل يوم.',
      'زر «اسأل عن هذا الجواب» تحت كل جواب.',
      'زر «استمع للجواب» عند وجود تسجيل صوتي.',
    ]
  ),
  (
    '1.10.0',
    [
      'بطاقة مصوّرة للجواب جاهزة للنشر.',
      'مجلدات للمحفوظات بأسماء تختارها.',
      'وسوم تحت الأجوبة تجمع ما يتعلق بموضوع واحد.',
    ]
  ),
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


/// «قراءتي»: the reader's own numbers, to know where they have reached.
class MyReadingScreen extends StatelessWidget {
  const MyReadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final read = repo.everRead;
    final total = repo.fatwas.length;
    final done = repo.fatwas.where((f) => read.contains(f.id)).length;
    Widget box(String value, String label) => Expanded(
          child: Card(
            margin: const EdgeInsets.all(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              child: Column(children: [
                Text(value,
                    style: const TextStyle(fontFamily: 'Tajawal', fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('قراءتي')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            box('$done', 'قرأت في المجموع'),
            box('${repo.readThisMonth}', 'هذا الشهر'),
            box('${repo.readToday}', 'اليوم'),
          ]),
          Row(children: [
            box('${repo.streak}', 'أيام متتالية'),
            box(total == 0 ? '0%' : '${(done * 100 / total).toStringAsFixed(1)}%', 'من المكتبة كلها'),
            box('${total - done}', 'لم تقرأه بعد'),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
            child: Text('تقدّمك في كل باب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          for (final c in repo.chapters)
            if (repo.countInChapter(c.id) > 0)
              Builder(builder: (context) {
                final all = repo.byChapter(c.id);
                final n = all.where((f) => read.contains(f.id)).length;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          Icon(chapterIcon(c.icon), size: 18, color: kGold),
                          const SizedBox(width: 6),
                          Expanded(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                          Text('$n من ${all.length}', style: const TextStyle(color: Colors.grey)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(value: n / all.length, minHeight: 7),
                        ),
                      ],
                    ),
                  ),
                );
              }),
        ],
      ),
    );
  }
}
