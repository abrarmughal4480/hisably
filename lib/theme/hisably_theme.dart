import 'package:flutter/material.dart';

/// Hisably design tokens — FINAL design system (approved 22 Oct 2026).
/// Premium Dark only. Black background, layered greys, one blue accent,
/// semantic green/red/amber. Typography: Sora for amounts/display,
/// Manrope for headings, Inter for body, Noto Nastaliq Urdu for Urdu.
class HisablyColors {
  static const background = Color(0xFF000000);
  static const secondaryBg = Color(0xFF0A0A0A);
  static const card = Color(0xFF111111);
  static const elevated = Color(0xFF1A1A1A);
  static const input = Color(0xFF202020);
  static const border = Color(0xFF2A2A2A);
  static const pressed = Color(0xFF262626);
  static const disabled = Color(0xFF404040);

  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA3A3A3);
  static const textTertiary = Color(0xFF737373);

  static const accent = Color(0xFF3B82F6);
  static const accentDeep = Color(0xFF1D4ED8);
  static const income = Color(0xFF22C55E);
  static const expense = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);
  static const savings = Color(0xFFA78BFA);
  static const transfer = Color(0xFF06B6D4);
  static const logoGreen = Color(0xFF22C55E);
  static const logoGreenDeep = Color(0xFF16A34A);

  // Legacy aliases (older screens reference these names; values re-mapped
  // to the final palette so every screen follows the same system).
  static const primary = accent;
  static const primaryDeep = accentDeep;
  static const primaryTint = Color(0xFF16233B);
  static const orange = expense;
  static const orangeDark = expense;
  static const orangeTint = Color(0xFF2A1512);
  static const pink = warning;
  static const pinkDark = warning;
  static const pinkTint = Color(0xFF2A2110);
  static const darkBackground = background;
  static const darkCard = card;
  static const darkBorder = border;
  static const darkTextSecondary = textSecondary;
}

class HisablyFonts {
  static const body = 'Inter';
  static const heading = 'Manrope';
  static const display = 'Sora';
  static const urdu = 'NotoNastaliqUrdu';

  /// In Urdu mode everything renders in Nastaliq.
  static String bodyFor(String lang) => lang == 'ur' ? urdu : body;
  static String headingFor(String lang) => lang == 'ur' ? urdu : heading;
  static String displayFor(String lang) => lang == 'ur' ? urdu : display;
}

class HisablyTheme {
  static ThemeData app({String lang = 'en'}) {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark);
    final bodyFont = HisablyFonts.bodyFor(lang);
    return base.copyWith(
      scaffoldBackgroundColor: HisablyColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: HisablyColors.accent,
        brightness: Brightness.dark,
        primary: HisablyColors.accent,
        surface: HisablyColors.card,
        error: HisablyColors.expense,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: bodyFont,
        bodyColor: HisablyColors.text,
        displayColor: HisablyColors.text,
      ),
      cardTheme: CardThemeData(
        color: HisablyColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HisablyColors.border),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HisablyColors.background,
        foregroundColor: HisablyColors.text,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HisablyColors.input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HisablyColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HisablyColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HisablyColors.accent, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: HisablyColors.elevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: HisablyColors.elevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: HisablyColors.elevated,
        contentTextStyle: TextStyle(color: HisablyColors.text),
      ),
    );
  }
}

/// Amount/display text style (Sora).
TextStyle amountStyle(String lang,
    {double size = 16, FontWeight weight = FontWeight.w700, Color? color}) {
  return TextStyle(
    fontFamily: HisablyFonts.displayFor(lang),
    fontSize: size,
    fontWeight: weight,
    letterSpacing: -0.3,
    color: color,
  );
}

/// Heading text style (Manrope).
TextStyle headingStyle(String lang,
    {double size = 15, FontWeight weight = FontWeight.w700, Color? color}) {
  return TextStyle(
    fontFamily: HisablyFonts.headingFor(lang),
    fontSize: size,
    fontWeight: weight,
    letterSpacing: -0.2,
    color: color,
  );
}
