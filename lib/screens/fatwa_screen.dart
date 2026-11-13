import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

class FatwaScreen extends StatefulWidget {
  final Fatwa fatwa;
  const FatwaScreen({super.key, required this.fatwa});

  @override
  State<FatwaScreen> createState() => _FatwaScreenState();
}

class _FatwaScreenState extends State<FatwaScreen> {
  // Pinch-to-zoom: raw pointers (a Listener) so normal scrolling is untouched.
  final Map<int, Offset> _pointers = {};
  double? _startDistance;
  double _startScale = 1.0;
  double _scale = Repository.instance.readingScale;

  Fatwa get fatwa => widget.fatwa;

  double _distance() {
    final p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _startDistance = _distance();
      _startScale = _scale;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _startDistance != null && _startDistance! > 0) {
      final next = (_startScale * _distance() / _startDistance!).clamp(0.8, 2.2);
      if ((next - _scale).abs() > 0.01) setState(() => _scale = next);
    }
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2 && _startDistance != null) {
      _startDistance = null;
      Repository.instance.saveReadingScale(_scale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) {
        final fav = repo.isFavorite(fatwa.id);
        final later = repo.isReadLater(fatwa.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(fatwa.typeLabel),
            actions: [
              IconButton(
                tooltip: later ? 'إزالة من «اقرأ لاحقاً»' : 'اقرأ لاحقاً',
                icon: Icon(later ? Icons.watch_later : Icons.watch_later_outlined),
                onPressed: () {
                  repo.toggleReadLater(fatwa.id);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(later ? 'أُزيل من «اقرأ لاحقاً»' : 'أُضيف إلى «اقرأ لاحقاً»'),
                  ));
                },
              ),
              IconButton(
                tooltip: fav ? 'إزالة من المحفوظات' : 'حفظ',
                icon: Icon(fav ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => repo.toggleFavorite(fatwa.id),
              ),
            ],
          ),
          body: Listener(
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onUp,
            child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text('باب ${repo.chapterName(fatwa.chapter)}',
                  style: const TextStyle(color: kGoldChip, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SelectableText(fatwa.title,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.5)),
              const SizedBox(height: 16),
              if (fatwa.question.isNotEmpty) ...[
                _Block(label: 'السؤال', text: fatwa.question, highlight: true, scale: _scale),
                const SizedBox(height: 14),
              ],
              _Block(
                label: fatwa.question.isNotEmpty ? 'الجواب' : null,
                text: fatwa.answer,
                scale: _scale,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('قرّب إصبعيك أو باعدهما لتصغير الخط أو تكبيره',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              if (fatwa.tags.isNotEmpty) ...[
                const SizedBox(height: 18),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final t in fatwa.tags) Chip(label: Text('#$t'))],
                ),
              ],
              if (fatwa.date.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('تاريخ النشر: ${fatwa.date}', style: const TextStyle(color: Colors.grey)),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('نسخ'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fatwa.shareText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم النسخ')),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('مشاركة'),
                      onPressed: () => Share.share(fatwa.shareText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.link),
                label: const Text('نسخ رابط الجواب'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: AppConfig.fatwaLink(fatwa.id)));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الرابط')),
                  );
                },
              ),
              if (fatwa.source.isNotEmpty) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('عرض المصدر في تليجرام'),
                  onPressed: () => openUrl(context, fatwa.source),
                ),
              ],
              ..._related(context, repo),
            ],
          ),
          ),
        );
      },
    );
  }

  List<Widget> _related(BuildContext context, Repository repo) {
    final items = repo.related(fatwa);
    if (items.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      const Divider(),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('أجوبة ذات صلة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      for (final f in items)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.article_outlined, color: kGold),
            title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('باب ${repo.chapterName(f.chapter)}'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => openFatwa(context, f),
          ),
        ),
    ];
  }
}

/// Quran verses ﴿…﴾ in green with the Amiri font, hadith «…» in gold.
List<TextSpan> highlightSpans(String text, TextStyle base) {
  final spans = <TextSpan>[];
  final re = RegExp(r'﴿[^﴾]*﴾|«[^»]*»');
  var last = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    final part = m.group(0)!;
    final isVerse = part.startsWith('﴿');
    spans.add(TextSpan(
      text: part,
      style: isVerse
          ? const TextStyle(color: Color(0xFF2E7D4F), fontFamily: 'Amiri', fontWeight: FontWeight.bold)
          : const TextStyle(color: kGoldChip, fontWeight: FontWeight.w600),
    ));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

class _Block extends StatelessWidget {
  final String? label;
  final String text;
  final bool highlight;
  final double scale;
  const _Block({this.label, required this.text, this.highlight = false, this.scale = 1.0});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(fontSize: 17 * scale, height: 1.9, color: scheme.onSurface);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? kGold.withValues(alpha: 0.10) : null,
        borderRadius: BorderRadius.circular(14),
        border: highlight ? null : Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
          ],
          SelectableText.rich(TextSpan(style: base, children: highlightSpans(text, base))),
        ],
      ),
    );
  }
}
