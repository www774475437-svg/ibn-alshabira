import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Saved answers, «اقرأ لاحقاً», and the reader's own folders.
class FavoritesTab extends StatelessWidget {
  const FavoritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحفوظات'),
          bottom: const TabBar(
            labelColor: Color(0xFFC9A54C),
            unselectedLabelColor: Colors.white70,
            indicatorColor: Color(0xFFC9A54C),
            tabs: [
              Tab(icon: Icon(Icons.bookmark), text: 'المحفوظات'),
              Tab(icon: Icon(Icons.watch_later), text: 'اقرأ لاحقاً'),
              Tab(icon: Icon(Icons.folder), text: 'مجلداتي'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: repo,
          builder: (context, _) => TabBarView(
            children: [
              _List(
                items: repo.favoriteFatwas,
                empty: const EmptyState(
                  icon: Icons.bookmark_border,
                  text: 'لم تحفظ شيئاً بعد.\nاضغط علامة الحفظ في أي جواب لتجده هنا.',
                ),
              ),
              _List(
                items: repo.readLaterFatwas,
                empty: const EmptyState(
                  icon: Icons.watch_later_outlined,
                  text: 'القائمة فارغة.\nاضغط علامة الساعة في أي جواب لتقرأه لاحقاً.',
                ),
              ),
              const _Folders(),
            ],
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  final List<Fatwa> items;
  final Widget empty;
  const _List({required this.items, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return empty;
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => FatwaTile(fatwa: items[i]),
    );
  }
}

/// Asks for a folder name and creates it. Returns the name, or null.
Future<String?> askNewFolder(BuildContext context) async {
  final c = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('مجلد جديد'),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: 30,
        decoration: const InputDecoration(hintText: 'مثل: للخطبة', border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('إنشاء')),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  Repository.instance.addFolder(name);
  return name;
}

/// Bottom sheet: put this answer in (or take it out of) the reader's folders.
void showFolderSheet(BuildContext context, Fatwa fatwa) {
  final repo = Repository.instance;
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: repo,
        builder: (ctx, _) => ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('أضف الجواب إلى مجلد',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (final name in repo.folders.keys)
              CheckboxListTile(
                value: repo.folders[name]!.contains(fatwa.id),
                title: Text(name),
                secondary: const Icon(Icons.folder_outlined, color: kGold),
                onChanged: (_) => repo.toggleInFolder(name, fatwa.id),
              ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('مجلد جديد'),
              onTap: () async {
                final name = await askNewFolder(ctx);
                if (name != null) repo.toggleInFolder(name, fatwa.id);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _Folders extends StatelessWidget {
  const _Folders();

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final names = repo.folders.keys.toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (names.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(
              icon: Icons.folder_open,
              text: 'لا مجلدات بعد.\nأنشئ مجلداً باسم تختاره، ثم أضف إليه الأجوبة من زر «أضف إلى مجلد» تحت الجواب.',
            ),
          ),
        for (final name in names)
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder, color: kGold),
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${repo.folderFatwas(name).length} جواب'),
              trailing: IconButton(
                tooltip: 'حذف المجلد',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('حذف مجلد «$name»؟'),
                      content: const Text('يُحذف المجلد فقط، والأجوبة نفسها تبقى في التطبيق.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                      ],
                    ),
                  );
                  if (ok == true) repo.deleteFolder(name);
                },
              ),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => FolderScreen(name: name))),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('مجلد جديد'),
          onPressed: () => askNewFolder(context),
        ),
      ],
    );
  }
}

class FolderScreen extends StatelessWidget {
  final String name;
  const FolderScreen({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final items = repo.folderFatwas(name);
          if (items.isEmpty) {
            return const EmptyState(
                icon: Icons.folder_open, text: 'المجلد فارغ.\nأضف إليه من زر «أضف إلى مجلد» تحت أي جواب.');
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => FatwaTile(fatwa: items[i]),
          );
        },
      ),
    );
  }
}

/// All answers that carry one tag.
class TagScreen extends StatelessWidget {
  final String tag;
  const TagScreen({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: Text('#$tag')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final items = repo.byTag(tag);
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.tag, text: 'لا توجد أجوبة بهذا الوسم.');
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) => FatwaTile(fatwa: items[i]),
          );
        },
      ),
    );
  }
}
