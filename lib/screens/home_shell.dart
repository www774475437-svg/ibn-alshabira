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
import 'search_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _tab = 'home';

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
        final ids = ['home', 'search', 'books', if (staff) 'admin', 'saved', 'more'];
        var index = ids.indexOf(_tab);
        if (index < 0) index = 0;
        return Scaffold(
          body: IndexedStack(
            index: index,
            children: [
              HomeTab(onOpenSearch: () => _goTo('search'), onOpenMore: () => _goTo('more')),
              const SearchTab(),
              const BooksTab(),
              if (staff) const AdminScreen(),
              const FavoritesTab(),
              const MoreTab(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _goTo(ids[i]),
            destinations: [
              const NavigationDestination(
                  icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
              const NavigationDestination(icon: Icon(Icons.search), label: 'البحث'),
              const NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'الكتب'),
              if (staff)
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: cloud.newQuestions > 0,
                    label: Text('${cloud.newQuestions}'),
                    child: const Icon(Icons.admin_panel_settings_outlined),
                  ),
                  selectedIcon: const Icon(Icons.admin_panel_settings),
                  label: 'الإدارة',
                ),
              const NavigationDestination(
                  icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'المحفوظات'),
              const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'المزيد'),
            ],
          ),
        );
      },
    );
  }
}
