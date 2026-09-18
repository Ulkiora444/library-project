import 'package:flutter/material.dart';

import 'app_localizations.dart';

enum ReaderThemeChoice { paper, sepia, night }

extension ReaderThemeChoicePresentation on ReaderThemeChoice {
  String label(AppLocalizations l10n) => switch (this) {
    ReaderThemeChoice.paper => l10n.paperTheme,
    ReaderThemeChoice.sepia => l10n.sepiaTheme,
    ReaderThemeChoice.night => l10n.nightTheme,
  };

  IconData get icon => switch (this) {
    ReaderThemeChoice.paper => Icons.menu_book_rounded,
    ReaderThemeChoice.sepia => Icons.auto_stories_rounded,
    ReaderThemeChoice.night => Icons.dark_mode_rounded,
  };

  ReaderPalette get palette => switch (this) {
    ReaderThemeChoice.paper => const ReaderPalette(
      brightness: Brightness.light,
      appBackground: Color(0xFFF3EEE2),
      panelBackground: Color(0xFFFFFCF5),
      pageBackground: Color(0xFFFFFDF8),
      titleColor: Color(0xFF1F1A16),
      bodyColor: Color(0xFF332A24),
      mutedColor: Color(0xFF7D6A5E),
      accent: Color(0xFF8D5A2B),
      divider: Color(0x1F4A3526),
      quoteBackground: Color(0xFFF6EFE1),
      codeBackground: Color(0xFFF2EADF),
      shadow: Color(0x14000000),
    ),
    ReaderThemeChoice.sepia => const ReaderPalette(
      brightness: Brightness.light,
      appBackground: Color(0xFFE8D8BE),
      panelBackground: Color(0xFFF4E7D0),
      pageBackground: Color(0xFFF9F0DE),
      titleColor: Color(0xFF34261A),
      bodyColor: Color(0xFF48372A),
      mutedColor: Color(0xFF886A4E),
      accent: Color(0xFFAF5E2C),
      divider: Color(0x2648372A),
      quoteBackground: Color(0xFFF0DFC2),
      codeBackground: Color(0xFFECDABD),
      shadow: Color(0x19000000),
    ),
    ReaderThemeChoice.night => const ReaderPalette(
      brightness: Brightness.dark,
      appBackground: Color(0xFF11161A),
      panelBackground: Color(0xFF182027),
      pageBackground: Color(0xFF1D2730),
      titleColor: Color(0xFFF5F2EA),
      bodyColor: Color(0xFFE3DDD1),
      mutedColor: Color(0xFFA7B1B7),
      accent: Color(0xFF7BC4D6),
      divider: Color(0x26FFFFFF),
      quoteBackground: Color(0xFF22303A),
      codeBackground: Color(0xFF202B33),
      shadow: Color(0x28000000),
    ),
  };
}

class ReaderPalette {
  const ReaderPalette({
    required this.brightness,
    required this.appBackground,
    required this.panelBackground,
    required this.pageBackground,
    required this.titleColor,
    required this.bodyColor,
    required this.mutedColor,
    required this.accent,
    required this.divider,
    required this.quoteBackground,
    required this.codeBackground,
    required this.shadow,
  });

  final Brightness brightness;
  final Color appBackground;
  final Color panelBackground;
  final Color pageBackground;
  final Color titleColor;
  final Color bodyColor;
  final Color mutedColor;
  final Color accent;
  final Color divider;
  final Color quoteBackground;
  final Color codeBackground;
  final Color shadow;
}

ThemeData buildAppTheme(ReaderThemeChoice choice) {
  final palette = choice.palette;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: palette.brightness,
  ).copyWith(
    primary: palette.accent,
    secondary: palette.accent,
    surface: palette.panelBackground,
    onSurface: palette.bodyColor,
    onPrimary: palette.brightness == Brightness.dark
        ? const Color(0xFF081217)
        : Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: palette.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.appBackground,
    canvasColor: palette.panelBackground,
    splashFactory: InkSparkle.splashFactory,
    textTheme: ThemeData(useMaterial3: true, brightness: palette.brightness)
        .textTheme
        .apply(bodyColor: palette.bodyColor, displayColor: palette.titleColor),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.panelBackground.withValues(alpha: 0.92),
      foregroundColor: palette.titleColor,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: palette.titleColor,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: palette.panelBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.panelBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dividerTheme: DividerThemeData(
      color: palette.divider,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.panelBackground,
      contentTextStyle: TextStyle(color: palette.bodyColor),
      actionTextColor: palette.accent,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
