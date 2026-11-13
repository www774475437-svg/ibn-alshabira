import 'package:flutter/material.dart';

const kGreen = Color(0xFF1F5E3B);
const kGold = Color(0xFFC9A54C);
const kPaper = Color(0xFFF4ECD8);
const kInk = Color(0xFF3B2F1E);
const kTeal = Color(0xFF2E6B73);
const kTealDark = Color(0xFF1F4E55);

/// palette: 'teal' (light, teal & gold — default), 'green' (green & gold),
/// 'black' (black & gold, always dark), 'paper' (warm paper, always light).
ThemeData buildTheme(Brightness brightness, [String fontFamily = '', String palette = 'teal']) {
  if (palette == 'black') brightness = Brightness.dark;
  if (palette == 'paper') brightness = Brightness.light;
  final dark = brightness == Brightness.dark;
  final paper = palette == 'paper';
  final teal = palette == 'teal';

  final brand = paper ? const Color(0xFF6B5326) : (teal ? kTealDark : kGreen);
  final barColor = dark ? Colors.black : brand;
  final surface = dark
      ? Colors.black
      : (paper ? kPaper : (teal ? const Color(0xFFF6FAF9) : const Color(0xFFFBF8F1)));
  final cardColor = dark ? const Color(0xFF141414) : (paper ? const Color(0xFFFBF5E6) : Colors.white);

  final scheme = ColorScheme.fromSeed(
    seedColor: paper ? const Color(0xFF8A6A2F) : (teal ? kTeal : kGreen),
    brightness: brightness,
  ).copyWith(
    primary: dark ? kGold : (teal ? kTeal : brand),
    secondary: kGold,
    surface: surface,
    onSurface: paper ? kInk : (teal && !dark ? const Color(0xFF1C3438) : null),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily.isEmpty ? null : fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: barColor,
      foregroundColor: dark ? kGold : Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: dark ? 0 : (teal ? 1.5 : 0),
      shadowColor: Colors.black.withValues(alpha: 0.18),
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: kGold.withValues(alpha: dark ? 0.35 : (teal ? 0.18 : 0.25))),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      indicatorColor: kGold.withValues(alpha: 0.25),
      elevation: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: ZoomPageTransitionsBuilder()},
    ),
  );
}

/// The dark brand color of the current palette (cards, icon boxes).
Color brandColor(BuildContext context) {
  final t = Theme.of(context);
  if (t.brightness == Brightness.dark) return const Color(0xFF1A1A1A);
  return t.appBarTheme.backgroundColor ?? kTealDark;
}

/// Kept for older call sites.
Color headerColor(BuildContext context, String palette) => brandColor(context);
