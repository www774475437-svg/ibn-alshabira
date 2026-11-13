import 'package:flutter/material.dart';

const kGreen = Color(0xFF1F5E3B);
const kGold = Color(0xFFC9A54C);
const kPaper = Color(0xFFF4ECD8);
const kInk = Color(0xFF3B2F1E);

/// palette: 'green' (green & gold), 'black' (black & gold, always dark),
/// 'paper' (warm paper, always light).
ThemeData buildTheme(Brightness brightness, [String fontFamily = '', String palette = 'green']) {
  if (palette == 'black') brightness = Brightness.dark;
  if (palette == 'paper') brightness = Brightness.light;
  final dark = brightness == Brightness.dark;
  final paper = palette == 'paper';
  final black = palette == 'black';

  final barColor = black || dark ? Colors.black : (paper ? const Color(0xFF6B5326) : kGreen);
  final surface = dark ? Colors.black : (paper ? kPaper : const Color(0xFFFBF8F1));
  final cardColor = dark ? const Color(0xFF141414) : (paper ? const Color(0xFFFBF5E6) : Colors.white);

  final scheme = ColorScheme.fromSeed(
    seedColor: paper ? const Color(0xFF8A6A2F) : kGreen,
    brightness: brightness,
  ).copyWith(
    primary: dark ? kGold : (paper ? const Color(0xFF6B5326) : kGreen),
    secondary: kGold,
    surface: surface,
    onSurface: paper ? kInk : null,
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
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kGold.withValues(alpha: dark ? 0.35 : 0.25)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Header color used on the home page for each palette.
Color headerColor(BuildContext context, String palette) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (dark || palette == 'black') return const Color(0xFF0E0E0E);
  if (palette == 'paper') return const Color(0xFF6B5326);
  return kGreen;
}
