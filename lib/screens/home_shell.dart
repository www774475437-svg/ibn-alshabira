import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

import '../services/cloud.dart';
import 'account_screens.dart';
import 'books_tab.dart';
import 'extra_screens.dart';
import 'favorites_tab.dart';
import 'home_tab.dart';
import 'more_tab.dart';
import 'ask_screen.dart';
import 'content_screens.dart';
import 'search_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _tab = 'home';
  final Set<String> _opened = {'home'};

  void _goTo(String id) => setState(() => _tab = id);

  @override
  void initState() {
    super.initState();
    _showWhatsNewOnce();
  }

  /// After an update, show «ما الجديد» once.
  Future<void> _showWhatsNewOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getString('seenVersion');
    await prefs.setString('seenVersion', AppConfig.version);
    if (seen == null || seen == AppConfig.version || !mounted) return;
    final items = whatsNew.first.$2;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ما الجديد في هذه النسخة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $t', style: const TextStyle(height: 1.7)),
                ),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        // The admin tab exists only for the developer, admins and editors.
        // Forced update (Android app only; the developer is never locked out).
        if (!kIsWeb &&
            AppConfig.buildNumber > 0 &&
            AppConfig.buildNumber < cloud.minBuild &&
            !cloud.isDeveloper) {
          return const MustUpdateScreen();
        }
        final staff = cloud.ready && cloud.isAdmin;
        // «الإدارة» exists only for the developer, the sheikh, admins and editors.
        final ids = ['home', 'books', 'saved', 'ask', if (staff) 'admin', 'scholars', 'more'];
        var index = ids.indexOf(_tab);
        if (index < 0) index = 0;
        _opened.add(ids[index]);
        Widget page(String id) {
          // Each page is built the first time it is opened, to start fast.
          if (!_opened.contains(id)) return const SizedBox.shrink();
          switch (id) {
            case 'home':
              return HomeTab(
                // Search opens as a full page over home, with a back arrow.
                onOpenSearch: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchTab())),
                onOpenMore: () => _goTo('more'),
              );
            case 'books':
              return const BooksTab();
            case 'saved':
              return const FavoritesTab();
            case 'ask':
              return const AskScreen();
            case 'admin':
              return const AdminScreen();
            case 'scholars':
              return const ScholarsScreen();
            default:
              return const MoreTab();
          }
        }

        NavigationDestination dest(String id) {
          switch (id) {
            case 'home':
              return const NavigationDestination(
                  icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية');
            case 'books':
              return const NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'الكتب');
            case 'saved':
              return const NavigationDestination(
                  icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'المحفوظات');
            case 'ask':
              return NavigationDestination(
                icon: Badge(
                  isLabelVisible: cloud.unseenReplies > 0,
                  label: Text('${cloud.unseenReplies}'),
                  child: const Icon(Icons.forum_outlined),
                ),
                selectedIcon: const Icon(Icons.forum),
                label: 'اسأل الشيخ',
              );
            case 'admin':
              return NavigationDestination(
                icon: Badge(
                  isLabelVisible: cloud.newQuestions > 0,
                  label: Text('${cloud.newQuestions}'),
                  child: const Icon(Icons.admin_panel_settings_outlined),
                ),
                selectedIcon: const Icon(Icons.admin_panel_settings),
                label: 'الإدارة',
              );
            case 'scholars':
              return const NavigationDestination(
                  icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'المشايخ الثقات');
            default:
              return const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد');
          }
        }

        return Scaffold(
          body: IndexedStack(
            index: index,
            children: [for (final id in ids) KeyedSubtree(key: ValueKey(id), child: page(id))],
          ),
          bottomNavigationBar: NavigationBarTheme(
            // Six or seven buttons: smaller labels so every name fits.
            data: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                    fontSize: ids.length > 6 ? 9.5 : 10.5,
                    height: 1.2,
                    fontWeight: states.contains(WidgetState.selected) ? FontWeight.bold : FontWeight.normal,
                  )),
            ),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => _goTo(ids[i]),
              destinations: [for (final id in ids) dest(id)],
            ),
          ),
        );
      },
    );
  }
}
