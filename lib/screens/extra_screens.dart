import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

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
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'من محافظة إب باليمن، ومن طلاب الشيخ يحيى بن علي الحجوري.\n\n'
                'يجمع هذا التطبيق أجوبته ومقالاته وكتبه ورسائله الدعوية، '
                'مرتّبة على الأبواب ليسهل الرجوع إليها.\n\n'
                'وسيُضاف هنا تعريف أوسع بالشيخ وطلبه للعلم ومؤلفاته قريباً بإذن الله.',
                style: TextStyle(fontSize: 16, height: 1.9),
              ),
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
