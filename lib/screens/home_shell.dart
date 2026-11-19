import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../theme.dart';

import '../services/cloud.dart';
import '../services/net.dart';
import 'account_screens.dart';
import 'books_tab.dart';
import 'extra_screens.dart';
import 'favorites_tab.dart';
import 'home_tab.dart';
import 'more_tab.dart';
import 'ask_screen.dart';
import 'trusted_screens.dart';
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
              return const TrustedScholarsScreen();
            default:
              return const MoreTab();
          }
        }

        (IconData, IconData, String, int) dest(String id) {
          switch (id) {
            case 'home':
              return (Icons.home_outlined, Icons.home_rounded, 'الرئيسية', 0);
            case 'books':
              return (Icons.menu_book_outlined, Icons.menu_book_rounded, 'الكتب', 0);
            case 'saved':
              return (Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'المحفوظات', 0);
            case 'ask':
              return (Icons.forum_outlined, Icons.forum_rounded, 'اسأل الشيخ', cloud.unseenReplies);
            case 'admin':
              return (Icons.admin_panel_settings_outlined, Icons.admin_panel_settings, 'الإدارة', cloud.newQuestions);
            case 'scholars':
              return (Icons.groups_outlined, Icons.groups_rounded, 'المشايخ الثقات', 0);
            default:
              return (Icons.grid_view_outlined, Icons.grid_view_rounded, 'المزيد', 0);
          }
        }

        return Scaffold(
          body: Column(children: [
            Expanded(
              child: IndexedStack(
                index: index,
                children: [for (final id in ids) KeyedSubtree(key: ValueKey(id), child: page(id))],
              ),
            ),
            const _OfflineBar(),
          ]),
          // A floating rounded bar, and the search as its own round button.
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Row(children: [
                Expanded(
                  child: _Pill(
                    child: Row(children: [
                      for (var i = 0; i < ids.length; i++)
                        Expanded(
                          child: _NavItem(
                            item: dest(ids[i]),
                            selected: i == index,
                            small: ids.length > 6,
                            onTap: () => _goTo(ids[i]),
                          ),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                _Pill(
                  round: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchTab())),
                    child: const SizedBox(
                      width: 58,
                      height: 58,
                      child: Icon(Icons.search_rounded, size: 28),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// The glass look of the bottom bar and the search button.
class _Pill extends StatelessWidget {
  final Widget child;
  final bool round;
  const _Pill({required this.child, this.round = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final shape = round
        ? CircleBorder(side: BorderSide(color: t.colorScheme.onSurface.withValues(alpha: dark ? .16 : .10)))
        : StadiumBorder(side: BorderSide(color: t.colorScheme.onSurface.withValues(alpha: dark ? .16 : .10)));
    return Material(
      color: dark ? const Color(0xFF1C1F24) : t.cardTheme.color ?? Colors.white,
      elevation: dark ? 0 : 6,
      shadowColor: Colors.black.withValues(alpha: .18),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _NavItem extends StatelessWidget {
  final (IconData, IconData, String, int) item;
  final bool selected, small;
  final VoidCallback onTap;
  const _NavItem({required this.item, required this.selected, required this.small, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    final on = dark ? kGold : t.colorScheme.primary;
    final off = t.colorScheme.onSurface.withValues(alpha: .72);
    Widget icon = Icon(selected ? item.$2 : item.$1, size: small ? 22 : 24, color: selected ? on : off);
    if (item.$4 > 0) icon = Badge(label: Text('${item.$4}'), child: icon);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
      child: Material(
        color: selected ? on.withValues(alpha: dark ? .16 : .12) : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 50,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              icon,
              const SizedBox(height: 2),
              // The whole name, made smaller when it is long («المشايخ الثقات»).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.$3,
                  maxLines: 1,
                  softWrap: false,
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                      fontSize: small ? 9.5 : 10.5,
                      height: 1.1,
                      color: selected ? on : off,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// «أنت بلا إنترنت»: a small strip above the buttons while the internet is off.
class _OfflineBar extends StatefulWidget {
  const _OfflineBar();

  @override
  State<_OfflineBar> createState() => _OfflineBarState();
}

class _OfflineBarState extends State<_OfflineBar> {
  @override
  void initState() {
    super.initState();
    Net.instance.start();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Net.instance,
        builder: (context, _) => AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: !Net.instance.offline
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: const Color(0xFF3A3A3A),
                  child: InkWell(
                    onTap: Net.instance.check,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Row(children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('أنت بلا إنترنت — تقرأ المحفوظ في جهازك',
                              style: TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                        Icon(Icons.refresh, color: Colors.white70, size: 18),
                      ]),
                    ),
                  ),
                ),
        ),
      );
}
