import 'package:flutter/material.dart';

const kGreen = Color(0xFF1F5E3B);
const kGold = Color(0xFFC9A54C);

ThemeData buildTheme(Brightness brightness, [String fontFamily = '']) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kGreen,
    brightness: brightness,
  ).copyWith(
    primary: dark ? kGold : kGreen,
    secondary: kGold,
    surface: dark ? Colors.black : const Color(0xFFFBF8F1),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily.isEmpty ? null : fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: dark ? Colors.black : kGreen,
      foregroundColor: dark ? kGold : Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF141414) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kGold.withValues(alpha: dark ? 0.35 : 0.25)),
      ),
    ),
  );
}
