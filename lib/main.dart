import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repository.dart';
import 'screens/fatwa_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/notifications.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await Repository.instance.load(prefs);
  runApp(const IbnAlshabiraApp());
  // Set up the daily notification after the first frame; never blocks startup.
  DailyNotifications.init().then(
    (_) => DailyNotifications.setEnabled(
      Repository.instance.dailyNotification,
      hour: Repository.instance.notifyHour,
      minute: Repository.instance.notifyMinute,
    ),
  );
}

/// Routes: "/" home, "/fatwa/<id>" a single fatwa (shareable web link).
Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? '/';
  if (name.startsWith('/fatwa/')) {
    final f = Repository.instance.findById(Uri.decodeComponent(name.substring(7)));
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
        title: 'ابن الشابرة',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: buildTheme(Brightness.light, repo.fontFamily),
        darkTheme: buildTheme(Brightness.dark, repo.fontFamily),
        themeMode: repo.themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(repo.fontScale),
          ),
          child: child!,
        ),
        onGenerateRoute: onGenerateRoute,
        // A shared link to one fatwa opens it directly, with home underneath.
        onGenerateInitialRoutes: (initial) {
          if (initial.startsWith('/fatwa/')) {
            final f = Repository.instance.findById(Uri.decodeComponent(initial.substring(7)));
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
          return [onGenerateRoute(const RouteSettings(name: '/'))!];
        },
      ),
    );
  }
}
