import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repository.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await Repository.instance.load(prefs);
  runApp(const IbnAlshabiraApp());
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
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: repo.themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(repo.fontScale),
          ),
          child: child!,
        ),
        home: repo.onboarded ? const HomeShell() : const OnboardingScreen(),
      ),
    );
  }
}
