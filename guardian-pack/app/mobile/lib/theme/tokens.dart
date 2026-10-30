import 'package:flutter/material.dart';

/// Design tokens — the only place colours, radii and spacing are defined.
/// Flat fills only. See docs/06-app-design.md §1.
abstract final class WpColors {
  static const navy = Color(0xFF0B2A55);
  static const navyDeep = Color(0xFF071C3A);
  static const cyan = Color(0xFF3FB9D0);
  static const cyanSoft = Color(0xFFDDF3F7);
  static const red = Color(0xFFE24B4B);
  static const redSoft = Color(0xFFFBE4E4);
  static const green = Color(0xFF1E9E5A);
  static const amber = Color(0xFFD9960A);

  // light
  static const bg = Color(0xFFF4F6F9);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF14181F);
  static const muted = Color(0xFF5B6472);
  static const line = Color(0xFFE3E7ED);

  // dark
  static const bgDark = Color(0xFF0F1216);
  static const cardDark = Color(0xFF161B22);
  static const inkDark = Color(0xFFE6EDF3);
  static const mutedDark = Color(0xFF9AA4B2);
  static const lineDark = Color(0xFF2B3440);
  static const navyDark = Color(0xFF10203A);
}

abstract final class WpRadius {
  static const card = 16.0;
  static const button = 12.0;
  static const chip = 999.0;
}

abstract final class WpSpace {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

abstract final class WpMotion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const marker = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
}

/// Semantic colours that flip with the theme. Read via `context.wp`.
class WpScheme extends ThemeExtension<WpScheme> {
  const WpScheme({
    required this.bg,
    required this.card,
    required this.ink,
    required this.muted,
    required this.line,
    required this.header,
    required this.accent,
    required this.onAccent,
  });

  final Color bg, card, ink, muted, line, header;

  /// Buttons, selected states and icons that carry the brand colour. Navy on light
  /// surfaces; cyan on dark ones, where navy was blue-on-blue and unreadable.
  final Color accent, onAccent;

  static const light = WpScheme(
    bg: WpColors.bg,
    card: WpColors.card,
    ink: WpColors.ink,
    muted: WpColors.muted,
    line: WpColors.line,
    header: WpColors.navy,
    accent: WpColors.navy,
    onAccent: Colors.white,
  );

  static const dark = WpScheme(
    bg: WpColors.bgDark,
    card: WpColors.cardDark,
    ink: WpColors.inkDark,
    muted: WpColors.mutedDark,
    line: WpColors.lineDark,
    header: WpColors.navyDark,
    accent: WpColors.cyan,
    onAccent: WpColors.navyDeep,
  );

  @override
  WpScheme copyWith({Color? bg, Color? card, Color? ink, Color? muted, Color? line, Color? header, Color? accent, Color? onAccent}) =>
      WpScheme(
        bg: bg ?? this.bg,
        card: card ?? this.card,
        ink: ink ?? this.ink,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        header: header ?? this.header,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
      );

  @override
  WpScheme lerp(WpScheme? other, double t) {
    if (other == null) return this;
    return WpScheme(
      bg: Color.lerp(bg, other.bg, t)!,
      card: Color.lerp(card, other.card, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      header: Color.lerp(header, other.header, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
    );
  }
}

extension WpContext on BuildContext {
  WpScheme get wp => Theme.of(this).extension<WpScheme>()!;
  TextTheme get text => Theme.of(this).textTheme;
}
