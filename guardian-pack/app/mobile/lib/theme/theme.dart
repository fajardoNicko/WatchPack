import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// One typeface (Inter, bundled), five sizes, two weights. Tabular figures so
/// times and speeds don't jiggle as they update.
TextTheme _textTheme(Color ink, Color muted) {
  const tabular = [FontFeature.tabularFigures()];
  TextStyle s(double size, FontWeight w, {Color? c, double? h, double ls = 0}) => TextStyle(
        fontFamily: 'Inter',
        fontSize: size,
        fontWeight: w,
        color: c ?? ink,
        height: h,
        letterSpacing: ls,
        fontFeatures: tabular,
      );
  return TextTheme(
    headlineMedium: s(28, FontWeight.w600, h: 1.15, ls: -0.4),
    titleLarge: s(22, FontWeight.w600, h: 1.2, ls: -0.2),
    titleMedium: s(17, FontWeight.w600, h: 1.3),
    titleSmall: s(15, FontWeight.w600, h: 1.3),
    bodyLarge: s(17, FontWeight.w400, h: 1.4),
    bodyMedium: s(15, FontWeight.w400, h: 1.45),
    bodySmall: s(13, FontWeight.w400, h: 1.4, c: muted),
    labelLarge: s(15, FontWeight.w600, h: 1.2),
    labelMedium: s(13, FontWeight.w500, h: 1.2),
    labelSmall: s(11, FontWeight.w500, h: 1.2, c: muted, ls: 0.2),
  );
}

ThemeData _build(Brightness b) {
  final wp = b == Brightness.light ? WpScheme.light : WpScheme.dark;
  final text = _textTheme(wp.ink, wp.muted);
  final scheme = ColorScheme(
    brightness: b,
    primary: WpColors.navy,
    onPrimary: Colors.white,
    secondary: WpColors.cyan,
    onSecondary: WpColors.navyDeep,
    error: WpColors.red,
    onError: Colors.white,
    surface: wp.card,
    onSurface: wp.ink,
    outline: wp.line,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: wp.bg,
    fontFamily: 'Inter',
    textTheme: text,
    splashFactory: InkSparkle.splashFactory,
    extensions: [wp],
    appBarTheme: AppBarTheme(
      backgroundColor: wp.header,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleMedium!.copyWith(color: Colors.white),
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    cardTheme: CardThemeData(
      color: wp.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WpRadius.card)),
    ),
    dividerTheme: DividerThemeData(color: wp.line, thickness: 1, space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: wp.header,
      indicatorColor: Colors.white.withValues(alpha: 0.12),
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall!.copyWith(color: Colors.white70)),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? WpColors.cyan : Colors.white70, size: 24),
      ),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: WpColors.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WpRadius.button)),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: wp.ink,
        side: BorderSide(color: wp.line),
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(WpRadius.button)),
        textStyle: text.labelLarge,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? WpColors.navy : wp.line,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: wp.ink,
      textColor: wp.ink,
      contentPadding: const EdgeInsets.symmetric(horizontal: WpSpace.l),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

final ThemeData wpLightTheme = _build(Brightness.light);
final ThemeData wpDarkTheme = _build(Brightness.dark);
