import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'ask_screen.dart';

class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const _Group('حسابات الشيخ'),
            _Section(children: [
              for (final l in repo.sheikhLinks)
                ListTile(
                  leading: _IconBox(platformIcon(l.platform)),
                  title: Text(l.name),
                  subtitle: l.url.isEmpty ? const Text('يُضاف قريباً') : null,
                  trailing: const Icon(Icons.chevron_left),
                  enabled: l.url.isNotEmpty,
                  onTap: () => openUrl(context, l.url),
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
              ListTile(
                leading: const _IconBox(Icons.dark_mode_outlined),
                title: const Text('المظهر'),
                trailing: DropdownButton<ThemeMode>(
                  value: repo.themeMode,
                  underline: const SizedBox(),
                  onChanged: (m) => repo.setThemeMode(m ?? ThemeMode.system),
                  items: const [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('تلقائي')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('فاتح')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('داكن')),
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
            const _Group('عن التطبيق'),
            const _Section(children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'تطبيق «ابن الشابرة» يجمع فتاوى ومقالات وكتب ورسائل الشيخ '
                  'قائد بن غانم الشابرة حفظه الله، من محافظة إب باليمن، '
                  'مرتّبة على الأبواب مع البحث بالموضوع.\n\nالإصدار 1.0.0',
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
          color: kGreen,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: kGold, size: 20),
      );
}
