import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Opens a sheet with [text] (the reader trims it to the sentence he wants),
/// then saves it to «فوائدي المحفوظة» or turns it into a picture to share.
Future<void> benefitSheet(BuildContext context, {required String text, required String source}) {
  final c = TextEditingController(text: text.trim());
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('فائدة من النص',
                style: TextStyle(fontFamily: kUiFont, fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('احذف ما لا تريده، واترك الجملة أو الفائدة التي تريدها.',
                style: TextStyle(fontFamily: kUiFont, fontSize: 13, color: Pal.muted(sheet))),
            const SizedBox(height: 10),
            TextField(
              controller: c,
              minLines: 4,
              maxLines: 10,
              style: const TextStyle(fontFamily: 'Amiri', fontSize: 17, height: 1.8),
            ),
            const SizedBox(height: 6),
            Text(source, style: const TextStyle(color: kGoldChip, fontSize: 13)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('احفظ في فوائدي'),
                  onPressed: () {
                    if (c.text.trim().isEmpty) return;
                    Repository.instance.addBenefit(c.text, source);
                    Navigator.pop(sheet);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('حُفظت في «فوائدي المحفوظة»')));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('صورة للمشاركة'),
                  onPressed: () {
                    if (c.text.trim().isEmpty) return;
                    Navigator.pop(sheet);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BenefitImageScreen(text: c.text.trim(), source: source)));
                  },
                ),
              ),
            ]),
          ]),
        ),
      ),
    ),
  );
}

/// «فوائدي المحفوظة»: the sentences the reader kept from books, answers
/// and articles, each with its source.
class MyBenefitsScreen extends StatelessWidget {
  const MyBenefitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('فوائدي المحفوظة')),
      body: ListenableBuilder(
        listenable: Repository.instance,
        builder: (context, _) {
          final list = Repository.instance.myBenefits;
          if (list.isEmpty) {
            return const EmptyState(
                icon: Icons.lightbulb_outline,
                text: 'لا فوائد محفوظة بعد.\nفي الكتاب أو الجواب اضغط «فائدة» واحفظ الجملة التي تعجبك.');
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final b = list[i];
              final text = '${b['t'] ?? ''}', source = '${b['s'] ?? ''}';
              final at = ((b['at'] ?? 0) as num).toInt();
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(text, style: const TextStyle(fontFamily: 'Amiri', fontSize: 17.5, height: 1.85)),
                    if (source.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('[$source]', style: const TextStyle(color: kGoldChip, fontSize: 13)),
                      ),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      IconButton(
                        tooltip: 'نسخ',
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: source.isEmpty ? text : '$text\n[$source]'));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(duration: Duration(seconds: 1), content: Text('تم النسخ')));
                        },
                      ),
                      IconButton(
                        tooltip: 'صورة للمشاركة',
                        icon: const Icon(Icons.image_outlined, size: 20),
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => BenefitImageScreen(text: text, source: source))),
                      ),
                      IconButton(
                        tooltip: 'حذف',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => Repository.instance.removeBenefit(at),
                      ),
                    ]),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A sentence as an elegant picture with the app's name, ready to share.
class BenefitImageScreen extends StatefulWidget {
  final String text, source;
  const BenefitImageScreen({super.key, required this.text, required this.source});

  @override
  State<BenefitImageScreen> createState() => _BenefitImageScreenState();
}

class _BenefitImageScreenState extends State<BenefitImageScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Share.shareXFiles(
        [XFile.fromData(data!.buffer.asUint8List(), mimeType: 'image/png', name: 'fayda.png')],
        fileNameOverrides: const ['fayda.png'],
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر صنع الصورة، حاول مرة أخرى')));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صورة الفائدة')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        RepaintBoundary(
          key: _key,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [Color(0xFF0B2230), Color(0xFF16404B), Color(0xFF235A63)],
              ),
              border: Border.all(color: kGold.withValues(alpha: .8), width: 1.4),
            ),
            child: Column(children: [
              const Icon(Icons.format_quote_rounded, color: kGold, size: 34),
              const SizedBox(height: 8),
              Text(widget.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Amiri', fontSize: 20, height: 2, color: Colors.white)),
              if (widget.source.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('[${widget.source}]',
                    textAlign: TextAlign.center, style: const TextStyle(color: kGold, fontSize: 14)),
              ],
              const SizedBox(height: 18),
              Container(height: 1, color: kGold.withValues(alpha: .35)),
              const SizedBox(height: 10),
              const Text('تطبيق ابن الشابرة  ·  ibnalshabira.com',
                  style: TextStyle(fontFamily: kUiFont, color: Colors.white70, fontSize: 13)),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy ? null : _share,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.share_rounded),
          label: const Text('مشاركة الصورة'),
        ),
      ]),
    );
  }
}
