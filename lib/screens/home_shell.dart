import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';

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

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  String _tab = 'home';
  String _from = 'home';
  final Set<String> _opened = {'home'};
  bool _collapsed = false;
  int _lastScroll = 0;
  late final AnimationController _slide =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520), value: 1);

  void _goTo(String id) {
    HapticFeedback.selectionClick();
    if (_collapsed) setState(() => _collapsed = false);
    if (id == _tab) return;
    setState(() {
      _from = _tab;
      _tab = id;
    });
    _slide.forward(from: 0);
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  /// Reading down a page shrinks the bar to one circle; a quick flick up
  /// brings it back (as in «منتقيات الشعر»).
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical || n.depth != 0 || n is! ScrollUpdateNotification) return false;
    final d = n.scrollDelta ?? 0;
    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = (now - _lastScroll) / 1000.0;
    _lastScroll = now;
    if (d > 1.5 && !_collapsed && n.metrics.pixels > 60) {
      setState(() => _collapsed = true);
    } else if (_collapsed && (n.metrics.pixels < 10 || (d < 0 && dt > 0 && dt < 80 && d / dt < -1.6))) {
      setState(() => _collapsed = false);
    }
    return false;
  }

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

        // Laptops and wide screens: a side panel instead of the bottom bar.
        if (MediaQuery.sizeOf(context).width >= 900) {
          return Scaffold(
            body: Row(children: [
              _SideBar(
                ids: ids,
                index: index,
                dest: dest,
                onTap: _goTo,
                onSearch: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchTab())),
              ),
              Expanded(
                child: Column(children: [
                  Expanded(
                    child: IndexedStack(
                      index: index,
                      children: [for (final id in ids) KeyedSubtree(key: ValueKey(id), child: page(id))],
                    ),
                  ),
                  const _OfflineBar(),
                ]),
              ),
            ]),
          );
        }

        final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
        final bottom = MediaQuery.paddingOf(context).bottom;
        const barH = 66.0;
        final from = ids.indexOf(_from) < 0 ? index : ids.indexOf(_from);
        return Scaffold(
          body: Stack(children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScroll,
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  // pages end above the bar, so it never covers their last lines
                  padding: EdgeInsets.only(bottom: keyboard ? 0 : barH + 14 + bottom),
                  child: Column(children: [
                    Expanded(
                      child: IndexedStack(
                        index: index,
                        children: [for (final id in ids) KeyedSubtree(key: ValueKey(id), child: page(id))],
                      ),
                    ),
                    const _OfflineBar(),
                  ]),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 10 + bottom,
              height: barH,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                offset: keyboard ? const Offset(0, 2) : Offset.zero,
                child: IgnorePointer(
                  ignoring: keyboard,
                  child: LayoutBuilder(builder: (context, box) {
                    final full = box.maxWidth - barH - 10;
                    return Stack(children: [
                      // The round search button keeps its place.
                      PositionedDirectional(
                        end: 0,
                        child: _Glass(
                          width: barH,
                          height: barH,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchTab()));
                            },
                            child: Center(child: Icon(Icons.search_rounded, size: 30, color: Pal.ink(context))),
                          ),
                        ),
                      ),
                      // The bar: full, or shrunk to one circle while reading down a page.
                      PositionedDirectional(
                        start: 0,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: _collapsed ? 0.0 : 1.0),
                          duration: const Duration(milliseconds: 460),
                          curve: Curves.easeOutBack,
                          builder: (context, t, _) {
                            final w = barH + (full - barH) * t;
                            final open = t.clamp(0.0, 1.0);
                            final cur = dest(ids[index]);
                            return _Glass(
                              width: w < barH ? barH : w,
                              height: barH,
                              child: Stack(children: [
                                if (open > 0.02)
                                  Opacity(
                                    opacity: Curves.easeIn.transform(open),
                                    child: OverflowBox(
                                      alignment: AlignmentDirectional.centerStart,
                                      minWidth: full,
                                      maxWidth: full,
                                      child: AnimatedBuilder(
                                        animation: _slide,
                                        builder: (context, _) => _items(context, full, barH, ids, index, from, dest),
                                      ),
                                    ),
                                  ),
                                if (open < 0.98)
                                  Opacity(
                                    opacity: 1 - open,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _goTo(_tab),
                                      child: Center(
                                        child: Transform.scale(
                                          scale: 1.15 - 0.15 * open,
                                          child: Icon(cur.$2, color: Pal.accent(context), size: 28),
                                        ),
                                      ),
                                    ),
                                  ),
                              ]),
                            );
                          },
                        ),
                      ),
                    ]);
                  }),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }

  /// The tabs with the pill that slides, stretches like liquid, then settles.
  Widget _items(BuildContext context, double full, double barH, List<String> ids, int index, int from,
      (IconData, IconData, String, int) Function(String) dest) {
    const pad = 5.0;
    final item = (full - pad * 2) / ids.length;
    final t = _slide.value;
    final pos = from + (index - from) * Curves.easeOutBack.transform(t);
    final stretch = math.sin(math.pi * t) * item * 0.38 * (index - from).abs().clamp(0, 1);
    final squash = 1 - math.sin(math.pi * t) * 0.14;
    final pillH = barH - pad * 2;
    return Stack(children: [
      PositionedDirectional(
        start: pad + pos * item - stretch / 2,
        top: pad + (pillH * (1 - squash)) / 2,
        width: item + stretch,
        height: pillH * squash,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Pal.soft(context),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(color: Pal.accent(context).withValues(alpha: 0.18 * math.sin(math.pi * t)), blurRadius: 16)
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(pad),
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
    ]);
  }
}

/// Frosted-glass capsule (the bar and the search circle).
class _Glass extends StatelessWidget {
  final double width, height;
  final Widget child;
  const _Glass({required this.width, required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Pal.dark(context);
    final r = BorderRadius.circular(height / 2 + 4);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .35 : .14), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: (dark ? const Color(0xFF22272D) : Colors.white).withValues(alpha: dark ? .88 : .86),
              borderRadius: r,
              border: Border.all(color: Pal.line(context).withValues(alpha: .8)),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
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
    final color = selected ? Pal.accent(context) : Pal.ink(context).withValues(alpha: .78);
    Widget icon = AnimatedScale(
      scale: selected ? 1.16 : 1,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Icon(selected ? item.$2 : item.$1, key: ValueKey(selected), color: color, size: small ? 23 : 25),
      ),
    );
    if (item.$4 > 0) icon = Badge(label: Text('${item.$4}'), child: icon);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        icon,
        const SizedBox(height: 2),
        // The whole name, made smaller when it is long («المشايخ الثقات»).
        FittedBox(
          fit: BoxFit.scaleDown,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
                fontFamily: kUiFont,
                fontSize: small ? 10 : 11.5,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: color),
            child: Text(item.$3, maxLines: 1, softWrap: false, textScaler: TextScaler.noScaling),
          ),
        ),
      ]),
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


/// The side panel on laptops: the name and logo, a search field, the tabs
/// with a gold mark on the open one, and the app download on the website.
class _SideBar extends StatelessWidget {
  final List<String> ids;
  final int index;
  final (IconData, IconData, String, int) Function(String) dest;
  final void Function(String) onTap;
  final VoidCallback onSearch;
  const _SideBar(
      {required this.ids, required this.index, required this.dest, required this.onTap, required this.onSearch});

  static const _gold = Color(0xFFF1D592);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E3B42), Color(0xFF0A2C31)],
        ),
        border: BorderDirectional(end: BorderSide(color: Color(0x66C9A253))),
      ),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFC9A253), width: 1.2),
                  image: const DecorationImage(image: AssetImage('assets/icon/icon.png'), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ابن الشابرة',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  Text('الشيخ قايد بن غانم الشابرة',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _gold, fontSize: 12)),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Material(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onSearch,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.search_rounded, color: Color(0xCCFFFFFF), size: 22),
                    SizedBox(width: 10),
                    Text('ابحث في المكتبة…', style: TextStyle(color: Color(0x99FFFFFF), fontSize: 14)),
                  ]),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Divider(color: Color(0x33C9A253), height: 1),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (var i = 0; i < ids.length; i++) _item(context, dest(ids[i]), i == index, () => onTap(ids[i])),
              ],
            ),
          ),
          if (kIsWeb)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: const Color(0xFF0E3B42),
                  minimumSize: const Size.fromHeight(46),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => openUrl(context, AppConfig.apkUrl),
                icon: const Icon(Icons.android),
                label: const Text('حمّل التطبيق لأندرويد', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _item(BuildContext context, (IconData, IconData, String, int) d, bool selected, VoidCallback tap) {
    Widget icon = Icon(selected ? d.$2 : d.$1, color: selected ? const Color(0xFF0E3B42) : const Color(0xD9FFFFFF), size: 23);
    if (d.$4 > 0) icon = Badge(label: Text('${d.$4}'), child: icon);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? _gold : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          hoverColor: const Color(0x14FFFFFF),
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              icon,
              const SizedBox(width: 14),
              Text(d.$3,
                  style: TextStyle(
                    fontFamily: kUiFont,
                    color: selected ? const Color(0xFF0E3B42) : Colors.white,
                    fontSize: 15.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  )),
            ]),
          ),
        ),
      ),
    );
  }
}
