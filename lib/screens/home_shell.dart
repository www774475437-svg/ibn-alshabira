import 'package:flutter/material.dart';

import '../services/cloud.dart';
import 'account_screens.dart';
import 'books_tab.dart';
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
  Widget build(BuildContext context) {
    final cloud = Cloud.instance;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        // The admin tab exists only for the developer, admins and editors.
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
