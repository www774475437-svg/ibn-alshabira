import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
  static const _perPage = 620;
  late final List<List<(bool, String)>> _pages; // (isQuestion, paragraph)
  late final List<GlobalKey> _keys;
  bool _busy = false;

  /// Cuts a long paragraph at spaces so that nothing is dropped.
  static List<String> _pieces(String t) {
    final out = <String>[];
    var rest = t.trim();
    while (rest.length > _perPage) {
      var cut = rest.lastIndexOf(RegExp(r'[.،؛؟!]\s'), _perPage);
      if (cut < _perPage ~/ 2) cut = rest.lastIndexOf(' ', _perPage);
      if (cut < _perPage ~/ 3) cut = _perPage - 1;
      out.add(rest.substring(0, cut + 1).trim());
      rest = rest.substring(cut + 1).trim();
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
  }

  @override
  void initState() {
    super.initState();
    final f = widget.fatwa;
    final units = <(bool, String)>[
      for (final p in f.question.split('\n'))
        for (final x in _pieces(p)) (true, x),
      for (final p in f.answer.split('\n'))
        for (final x in _pieces(p)) (false, x),
    ];
    // The whole question and answer, on as many numbered pictures as needed.
    final pages = <List<(bool, String)>>[[]];
    var size = 0;
    for (final u in units) {
      if (size > 0 && size + u.$2.length > _perPage) {
        pages.add([]);
        size = 0;
      }
      pages.last.add(u);
      size += u.$2.length;
    }
    _pages = pages.where((p) => p.isNotEmpty).toList();
    _keys = [for (final _ in _pages) GlobalKey()];
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = <XFile>[];
      for (var i = 0; i < _keys.length; i++) {
        final boundary = _keys[i].currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        files.add(XFile.fromData(data!.buffer.asUint8List(),
            mimeType: 'image/png', name: 'ibn-alshabira-${i + 1}.png'));
      }
      await Share.shareXFiles(files,
          fileNameOverrides: [for (var i = 0; i < files.length; i++) 'ibn-alshabira-${i + 1}.png']);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذّر إنشاء الصورة')));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fatwa;
    final n = _pages.length;
    return Scaffold(
      appBar: AppBar(title: Text(n == 1 ? 'بطاقة مصوّرة' : 'بطاقات مصوّرة ($n)')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.share),
            label: Text(n == 1 ? 'مشاركة الصورة' : 'مشاركة الصور ($n)', style: const TextStyle(fontSize: 17)),
            onPressed: _busy ? null : _share,
          ),
        ),
      ),
      // A Column (not a lazy list) so every picture exists when sharing.
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            if (n > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('الجواب كامل في $n صور مرقّمة، لا يُحذف منه شيء.',
                    style: const TextStyle(color: Colors.grey)),
              ),
            for (var i = 0; i < n; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: RepaintBoundary(
                  key: _keys[i],
                  child: _Card(
                    title: f.title,
                    parts: _pages[i],
                    page: i + 1,
                    pages: n,
                    hasQuestion: f.question.isNotEmpty,
                    link: AppConfig.fatwaLink(f.id),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final List<(bool, String)> parts;
  final int page, pages;
  final bool hasQuestion;
  final String link;
  const _Card(
      {required this.title,
      required this.parts,
      required this.page,
      required this.pages,
      required this.hasQuestion,
      required this.link});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2B2416);
    const body = TextStyle(fontFamily: 'Amiri', fontSize: 16.5, height: 1.9, color: ink);
    final q = [for (final p in parts) if (p.$1) p.$2];
    final a = [for (final p in parts) if (!p.$1) p.$2];
    return Container(
      width: 360,
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [kTealDark, kTeal],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF6EA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: kGold, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Small, tidy header: the text is what matters.
            Row(
              children: [
                ClipOval(child: Image.asset('assets/icon/icon.png', width: 20, height: 20)),
                const SizedBox(width: 6),
                const Text('ابن الشابرة',
                    style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 11, color: ink)),
                const Spacer(),
                if (pages > 1)
                  Text('$page / $pages',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF8A6A1F))),
              ],
            ),
            const SizedBox(height: 10),
            if (page == 1 && !hasQuestion) ...[
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Tajawal',
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      height: 1.6,
                      color: Color(0xFF8A6A1F))),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: kGold, height: 1),
              ),
            ],
            if (q.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: BoxDecoration(
                  color: kGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('السؤال',
                        style: TextStyle(
                            fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8A6A1F))),
                    for (final t in q) Text(t, textAlign: TextAlign.justify, style: body),
                  ],
                ),
              ),
            if (a.isNotEmpty && hasQuestion && (q.isNotEmpty || page == 1))
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('الجواب',
                    style: TextStyle(
                        fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF8A6A1F))),
              ),
            for (final t in a)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t, textAlign: TextAlign.justify, style: body),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text('الشيخ قايد بن غانم الشابرة حفظه الله',
                      style: TextStyle(fontFamily: 'Amiri', fontWeight: FontWeight.bold, fontSize: 13, color: ink)),
                ),
                // Scan to open the answer (no written link on the picture).
                if (page == pages)
                  QrImageView(data: link, size: 52, padding: EdgeInsets.zero, backgroundColor: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
