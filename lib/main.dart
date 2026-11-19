import 'dart:async';
import 'widgets/common.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'data/repository.dart';
import 'screens/fatwa_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/splash_screen.dart';
import 'services/cloud.dart';
import 'services/day_log.dart';
import 'services/fresh_posts.dart';
import 'services/live_feed.dart';
import 'services/challenge.dart';
import 'services/tour.dart';
import 'screens/content_screens.dart';
import 'screens/challenge_screens.dart';
import 'services/notifications.dart';
import 'services/prayer.dart';
import 'services/reminders.dart';
import 'services/profiles.dart';
import 'services/progress.dart';
import 'theme.dart';
import 'services/home_widgets.dart';
import 'services/audio_center.dart';
import 'screens/audio_library.dart' show NowPlayingBar, playerNavKey;
import 'services/quiz.dart';
import 'screens/adhkar_screen.dart';
import 'screens/quiz_screens.dart' show QuizHomeScreen;
import 'screens/profile_screen.dart' show DashboardScreen;
import 'screens/tour_screens.dart' show TourScreen, TourRecordScreen;
import 'widgets/common.dart' show openFatwa, openUrl;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioCenter.init();
  playerNavKey = appNavKey;
  final prefs = await SharedPreferences.getInstance();
  appLogo.value = prefs.getInt('appLogoV2') ?? 0;
  // The site opens at once with the newest answers, then brings the rest
  // of the library in the background (unless a link to one answer was opened).
  final quick = kIsWeb && AppConfig.idFromRoute(Uri.base.fragment) == null;
  await Repository.instance.load(prefs, quick: quick);
  Repository.onSavedListsChanged = () => Cloud.instance.pushUserData();
  runApp(const IbnAlshabiraApp());
  Cloud.instance.init();
  // Daily site data first, then the channel itself (new posts within minutes).
  loadFreshPosts().whenComplete(() => LiveFeed.refresh());
  Timer.periodic(const Duration(minutes: 10), (_) => LiveFeed.refresh());
  Future<void>.delayed(const Duration(seconds: 8), () {
    if (Cloud.instance.user != null) Challenges.instance.load();
    // Invites to a challenge by one's number: looked for every 30 seconds
    // while the app is open, and at once when it comes back to the front.
    Challenges.instance.onInvite = _showInvite;
    Challenges.instance.startInvites();
    Tour.instance.load();
    AppLifecycleListener(onResume: () {
      Challenges.instance.checkInvites();
      _openFromWidget();
      HomeWidgets.push();
    });
  });
  // A kind request to rate the app on Google Play: after a week of use,
  // then after a month, then after two months (three times at most).
  Future<void>.delayed(const Duration(seconds: 40), _askRating);
  // A tapped home-screen widget opens its page.
  Future<void>.delayed(const Duration(milliseconds: 1500), _openFromWidget);
  DayLog.instance.start();
  // Reminders and the prayer widget, once the settings have loaded.
  Future<void>.delayed(const Duration(seconds: 12), () async {
    await Reminders.schedule();
    await Reminders.scheduleLessons();
    await Progress.load();
    await Profiles.instance.load(); // pages of the people one follows; «new follower» notice
    await Prayer.instance.load();
    await Prayer.instance.pushWidget();
    await Quiz.instance.load();
    await HomeWidgets.push();
  });
  if (quick) Future.delayed(const Duration(milliseconds: 400), Repository.instance.loadRest);
  // Set up the daily notification after the first frame; never blocks startup.
  DailyNotifications.init().then(
    (_) => DailyNotifications.setEnabled(
      Repository.instance.dailyNotification,
      hour: Repository.instance.notifyHour,
      minute: Repository.instance.notifyMinute,
    ),
  );
  // A notification to every reader when a new version comes out.
  Future.delayed(const Duration(seconds: 3), UpdateWatch.start);
}

final appNavKey = GlobalKey<NavigatorState>();

Future<void> _askRating() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  final p = await SharedPreferences.getInstance();
  final now = DateTime.now().millisecondsSinceEpoch;
  final first = p.getInt('firstUseAt') ?? now;
  if (!p.containsKey('firstUseAt')) await p.setInt('firstUseAt', now);
  final stage = p.getInt('rateStage') ?? 0;
  const days = [7, 30, 60];
  if (stage >= days.length || now - first < days[stage] * 86400000) return;
  final ctx = appNavKey.currentContext;
  if (ctx == null) return;
  await p.setInt('rateStage', stage + 1);
  if (!ctx.mounted) return;
  final go = await showDialog<bool>(
    context: ctx,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.star_rounded, size: 44, color: Color(0xFFC9A227)),
      title: const Text('هل أعجبك التطبيق؟'),
      content: const Text('تقييمك في جوجل بلاي يساعد غيرك على الوصول إلى أجوبة الشيخ، ولا يأخذ منك إلا دقيقة. جزاك الله خيراً.',
          textAlign: TextAlign.center, style: TextStyle(height: 1.8)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('لاحقاً')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('قيّم التطبيق')),
      ],
    ),
  );
  if (go == true && ctx.mounted) {
    openUrl(ctx, 'https://play.google.com/store/apps/details?id=com.ibnalshabira.ibn_alshabira');
  }
}

Future<void> _openFromWidget() async {
  final t = await HomeWidgets.takeLaunch();
  final nav = appNavKey.currentState;
  final ctx = appNavKey.currentContext;
  if (t == null || nav == null || ctx == null) return;
  if (t.startsWith('answer:')) {
    final f = Repository.instance.findById(t.substring(7));
    if (f != null) openFatwa(ctx, f);
    return;
  }
  final Widget page = switch (t) {
    'dhikr' => const AdhkarScreen(),
    'quiz' => const QuizHomeScreen(),
    'read' => const DashboardScreen(),
    'tour' => Tour.instance.showCard ? TourScreen(dayKey: Tour.keyOf(Tour.nextStart())) : const TourRecordScreen(),
    _ => const SizedBox.shrink(),
  };
  if (page is SizedBox) return;
  nav.push(MaterialPageRoute(builder: (_) => page));
}

void _showInvite(String code, String by, String mode) {
  final what = mode == 'duel' ? 'تحدٍّ فردي' : 'تحدٍّ جماعي';
  OnceNotifications.showNow('دعوة إلى $what ⚡', 'دعاك $by إلى $what، ادخل التطبيق وانضمّ خلال دقيقتين.');
  final ctx = appNavKey.currentContext;
  if (ctx == null) return;
  showDialog<void>(
    context: ctx,
    builder: (d) => AlertDialog(
      icon: const Icon(Icons.bolt, size: 40, color: Color(0xFFC9A227)),
      title: Text('دعوة إلى $what'),
      content: Text('دعاك $by إلى $what في الأسئلة.\nرقم الغرفة: $code', textAlign: TextAlign.center, style: const TextStyle(height: 1.8)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('لاحقاً')),
        FilledButton(
          onPressed: () {
            Navigator.pop(d);
            appNavKey.currentState?.push(MaterialPageRoute(builder: (_) => ChallengeRoom(code: code, autoJoin: true)));
          },
          child: const Text('انضمّ الآن'),
        ),
      ],
    ),
  );
}

/// Routes: "/" home, "/fatwa/<id>" a single fatwa (shareable web link).
Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? '/';
  if (name.startsWith('/i/')) {
    DayLog.instance.invitedBy(name.substring(3));
  }
  if (name.startsWith('/c/')) {
    return MaterialPageRoute(settings: settings, builder: (_) => ChallengeRoom(code: name.substring(3), autoJoin: true));
  }
  if (name.startsWith('/s/')) {
    return MaterialPageRoute(settings: settings, builder: (_) => SeriesScreen(seriesId: name.substring(3)));
  }
  final routeId = AppConfig.idFromRoute(name);
  if (routeId != null) {
    final f = Repository.instance.findById(routeId);
    if (f != null) {
      return MaterialPageRoute(settings: settings, builder: (_) => FatwaScreen(fatwa: f));
    }
  }
  return MaterialPageRoute(
    settings: const RouteSettings(name: '/'),
    builder: (_) => Repository.instance.onboarded ? const HomeShell() : const OnboardingScreen(),
  );
}

class IbnAlshabiraApp extends StatelessWidget {
  const IbnAlshabiraApp({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return ListenableBuilder(
      listenable: repo,
      builder: (context, _) => MaterialApp(
        navigatorKey: appNavKey,
        title: 'ابن الشابرة',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light, repo.fontFamily, repo.palette),
        darkTheme: buildTheme(Brightness.dark, repo.fontFamily, repo.palette),
        themeMode: repo.palette == 'black'
            ? ThemeMode.dark
            : (repo.palette == 'paper' ? ThemeMode.light : repo.effectiveThemeMode),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(repo.fontScale),
          ),
          // While a recording plays, a slim bar stays at the top of every page.
          child: ListenableBuilder(
            listenable: AudioCenter.instance,
            builder: (context, _) => AudioCenter.instance.current == null
                ? child!
                : Column(children: [
                    const NowPlayingBar(),
                    Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child!)),
                  ]),
          ),
        ),
        onGenerateRoute: onGenerateRoute,
        // A shared link to one fatwa opens it directly, with home underneath.
        onGenerateInitialRoutes: (initial) {
          if (initial.startsWith('/i/')) DayLog.instance.invitedBy(initial.substring(3));
          if (initial.startsWith('/c/')) {
            return [
              MaterialPageRoute(settings: const RouteSettings(name: '/'), builder: (_) => const HomeShell()),
              MaterialPageRoute(
                  settings: RouteSettings(name: initial),
                  builder: (_) => ChallengeRoom(code: initial.substring(3), autoJoin: true)),
            ];
          }
          if (initial.startsWith('/s/')) {
            return [
              MaterialPageRoute(settings: const RouteSettings(name: '/'), builder: (_) => const HomeShell()),
              MaterialPageRoute(settings: RouteSettings(name: initial), builder: (_) => SeriesScreen(seriesId: initial.substring(3))),
            ];
          }
          final initialId = AppConfig.idFromRoute(initial);
          if (initialId != null) {
            final f = Repository.instance.findById(initialId);
            if (f != null) {
              return [
                MaterialPageRoute(
                    settings: const RouteSettings(name: '/'), builder: (_) => const HomeShell()),
                MaterialPageRoute(
                    settings: RouteSettings(name: initial),
                    builder: (_) => FatwaScreen(fatwa: f)),
              ];
            }
          }
          return [
            MaterialPageRoute(
              settings: const RouteSettings(name: '/'),
              builder: (_) => SplashScreen(
                next: Repository.instance.onboarded ? const HomeShell() : const OnboardingScreen(),
              ),
            ),
          ];
        },
      ),
    );
  }
}
