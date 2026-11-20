import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

const kGreen = Color(0xFF1F5E3B);
const kGold = Color(0xFFC9A54C);
const kPaper = Color(0xFFF4ECD8);
const kInk = Color(0xFF3B2F1E);
const kTeal = Color(0xFF2E6B73);
const kTealDark = Color(0xFF1F4E55);

/// The quiet UI font of buttons, bars and titles (the reading text keeps the
/// font the reader chose in the settings).
const kUiFont = 'Tajawal';

/// Soft colours of the current palette, in the spirit of «منتقيات الشعر»:
/// a calm background, cards a shade deeper with a thin line, one accent.
class Pal {
  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
  static Color bg(BuildContext c) => Theme.of(c).scaffoldBackgroundColor;
  static Color card(BuildContext c) => Theme.of(c).cardTheme.color ?? Colors.white;
  static Color line(BuildContext c) => dark(c) ? const Color(0xFF2C3238) : _lineOf(Theme.of(c).colorScheme.primary);
  static Color ink(BuildContext c) => Theme.of(c).colorScheme.onSurface;
  static Color muted(BuildContext c) => Theme.of(c).colorScheme.onSurface.withValues(alpha: .62);
  static Color accent(BuildContext c) => dark(c) ? kGold : Theme.of(c).colorScheme.primary;
  static Color soft(BuildContext c) =>
      dark(c) ? const Color(0xFF262B31) : Color.lerp(card(c), Theme.of(c).colorScheme.primary, .10)!;
  static Color _lineOf(Color p) => Color.lerp(const Color(0xFFE3E3DE), p, .10)!;
}

/// palette: 'teal' (light, teal & gold — default), 'green' (green & gold),
/// 'black' (black & gold, always dark), 'paper' (warm paper, always light).
ThemeData buildTheme(Brightness brightness, [String fontFamily = '', String palette = 'teal']) {
  if (palette == 'black') brightness = Brightness.dark;
  if (palette == 'paper') brightness = Brightness.light;
  final dark = brightness == Brightness.dark;
  final paper = palette == 'paper';
  final teal = palette == 'teal';

  final brand = paper ? const Color(0xFF6B5326) : (teal ? kTealDark : kGreen);
  final accent = dark ? kGold : (teal ? kTeal : brand);
  final surface = dark
      ? (palette == 'black' ? Colors.black : const Color(0xFF111417))
      : (paper ? const Color(0xFFF6EFDF) : (teal ? const Color(0xFFF5F8F7) : const Color(0xFFF8F6F0)));
  final cardColor = dark
      ? (palette == 'black' ? const Color(0xFF151515) : const Color(0xFF1B1F23))
      : (paper ? const Color(0xFFEFE6D1) : (teal ? const Color(0xFFECF2F1) : const Color(0xFFF0EDE4)));
  final ink = dark ? const Color(0xFFECE8E1) : (paper ? kInk : (teal ? const Color(0xFF1C3438) : const Color(0xFF1E2A22)));
  final line = dark ? const Color(0xFF2C3238) : Color.lerp(const Color(0xFFE0DED7), accent, .12)!;
  final ui = TextStyle(fontFamily: kUiFont, color: ink);

  final scheme = ColorScheme.fromSeed(
    seedColor: paper ? const Color(0xFF8A6A2F) : (teal ? kTeal : kGreen),
    brightness: brightness,
  ).copyWith(
    primary: accent,
    secondary: kGold,
    surface: surface,
    onSurface: ink,
    surfaceContainerLowest: cardColor,
    surfaceContainerLow: cardColor,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily.isEmpty ? null : fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    extensions: [BrandColors(brand: dark ? const Color(0xFF1E2329) : brand)],
    // Bars blend with the page: no coloured band, a bold title at the start.
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: ui.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
      toolbarTextStyle: ui,
      iconTheme: IconThemeData(color: ink),
      actionsIconTheme: IconThemeData(color: ink.withValues(alpha: .86)),
    ),
    // Soft rounded cards a shade deeper than the page, with a thin line.
    cardTheme: CardThemeData(
      elevation: 0,
      color: cardColor,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: line)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? const Color(0xF0202328) : const Color(0xF7FFFFFF),
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: .25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: line)),
      textStyle: ui.copyWith(fontSize: 15.5, fontWeight: FontWeight.w500),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
    ),
    dialogTheme: DialogThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: dark ? const Color(0xFF1C1F24) : surface,
      titleTextStyle: ui.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: dark ? const Color(0xFF1C1F24) : surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      iconColor: accent,
      titleTextStyle: ui.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
      subtitleTextStyle: ui.copyWith(fontSize: 13.5, color: ink.withValues(alpha: .62)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: cardColor,
      selectedColor: accent.withValues(alpha: dark ? .22 : .14),
      labelStyle: ui.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
      shape: StadiumBorder(side: BorderSide(color: line)),
      side: BorderSide(color: line),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cardColor,
      hintStyle: ui.copyWith(color: ink.withValues(alpha: .5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(color: accent, width: 1.6),
      ),
    ),
    dividerTheme: DividerThemeData(color: line, space: 1),
    tabBarTheme: TabBarThemeData(
      labelStyle: ui.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
      unselectedLabelStyle: ui.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      labelColor: accent,
      unselectedLabelColor: ink.withValues(alpha: .6),
      indicatorColor: accent,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cardColor,
      indicatorColor: kGold.withValues(alpha: 0.25),
      elevation: 3,
    ),
    // Strong, rounded buttons with the UI font.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 50),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        backgroundColor: dark ? kGold : accent,
        foregroundColor: dark ? Colors.black : Colors.white,
        textStyle: const TextStyle(fontFamily: kUiFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 50),
        elevation: 0,
        backgroundColor: Color.lerp(cardColor, accent, .14),
        foregroundColor: accent,
        textStyle: const TextStyle(fontFamily: kUiFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 50),
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: .45), width: 1.4),
        textStyle: const TextStyle(fontFamily: kUiFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: kUiFont, fontSize: 15.5, fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: ink)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? kGold : accent,
      foregroundColor: dark ? Colors.black : Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2B3036) : const Color(0xFF22403F),
      contentTextStyle: const TextStyle(fontFamily: kUiFont, color: Colors.white, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    // Smooth side slide between pages, like «منتقيات الشعر» on every phone.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

/// The dark brand colour of the palette, for the coloured cards (gold on it).
class BrandColors extends ThemeExtension<BrandColors> {
  final Color brand;
  const BrandColors({required this.brand});
  @override
  BrandColors copyWith({Color? brand}) => BrandColors(brand: brand ?? this.brand);
  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) =>
      other is BrandColors ? BrandColors(brand: Color.lerp(brand, other.brand, t)!) : this;
}

/// The dark brand color of the current palette (cards, icon boxes).
Color brandColor(BuildContext context) => Theme.of(context).extension<BrandColors>()?.brand ?? kTealDark;

/// Kept for older call sites.
Color headerColor(BuildContext context, String palette) => brandColor(context);
