import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/models.dart';
import '../theme.dart';

/// Turns an answer (or the paragraphs the reader picks from it) into an
/// elegant picture with the app's logo, ready to share.
/// The wording is never editable here: only whole paragraphs are chosen.
class ShareCardScreen extends StatefulWidget {
  final Fatwa fatwa;
  const ShareCardScreen({super.key, required this.fatwa});

  @override
  State<ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<ShareCardScreen> {
  final _key = GlobalKey();
  late final List<String> _parts;
  late final Set<int> _picked;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    var parts = widget.fatwa.answer
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length == 1 && parts.first.length > 400) {
      parts = RegExp(r'[^.؟!]+[.؟!]*')
          .allMatches(parts.first)
          .map((m) => m.group(0)!.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    _parts = parts;
    // Start with as many paragraphs as fit comfortably.
    _picked = {};
    var total = 0;
    for (var i = 0; i < _parts.length; i++) {
      if (i > 0 && total + _parts[i].length > 600) break;
      _picked.add(i);
      total += _parts[i].length;
    }
  }

  String get _text => [
        for (var i = 0; i < _parts.length; i++)
          if (_picked.contains(i)) _parts[i],
      ].join('\n');

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'ibn-alshabira.png')],
        fileNameOverrides: const ['ibn-alshabira.png'],
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذّر إنشاء الصورة')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fatwa;
    final long = _text.length > 1100;
    return Scaffold(
      appBar: AppBar(title: const Text('بطاقة مصوّرة')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Center(
            child: RepaintBoundary(
              key: _key,
              child: _Card(title: f.title, text: _text, link: AppConfig.fatwaLink(f.id)),
            ),
          ),
          const SizedBox(height: 14),
          if (long)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('المقطع طويل، والأفضل أن تختار فقرات أقل لتبقى الكتابة واضحة.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.orange)),
            ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share),
            label: const Text('مشاركة الصورة', style: TextStyle(fontSize: 17)),
            onPressed: _picked.isEmpty || _busy ? null : _share,
          ),
          if (_parts.length > 1) ...[
            const SizedBox(height: 18),
            const Text('اختر الفقرات التي تظهر في البطاقة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            for (var i = 0; i < _parts.length; i++)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _picked.contains(i),
                title: Text(_parts[i], maxLines: 2, overflow: TextOverflow.ellipsis),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _picked.add(i);
                  } else {
                    _picked.remove(i);
                  }
                }),
              ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String text;
  final String link;
  const _Card({required this.title, required this.text, required this.link});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2B2416);
    return Container(
      width: 360,
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [kTealDark, kTeal],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF6EA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kGold, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ClipOval(child: Image.asset('assets/icon/icon.png', width: 34, height: 34)),
                const SizedBox(width: 8),
                const Text('ابن الشابرة',
                    style: TextStyle(
                        fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 15, color: ink)),
              ],
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    height: 1.6,
                    color: Color(0xFF8A6A1F))),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(color: kGold, height: 1),
            ),
            Text(text,
                textAlign: TextAlign.justify,
                style: const TextStyle(fontFamily: 'Amiri', fontSize: 16, height: 1.9, color: ink)),
            const SizedBox(height: 14),
            const Text('الشيخ قايد بن غانم الشابرة حفظه الله',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Amiri', fontWeight: FontWeight.bold, fontSize: 14, color: ink)),
            const SizedBox(height: 6),
            Text(link,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
