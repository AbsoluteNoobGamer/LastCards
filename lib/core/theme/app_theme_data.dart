import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A plain-data class describing every visual token for one Stack & Flow theme.
///
/// Pass an instance to [buildThemeData] to obtain a Flutter [ThemeData].
class AppThemeData {
  const AppThemeData({
    required this.id,
    required this.name,

    // ── Backgrounds ─────────────────────────────────────────────────
    required this.backgroundDeep,
    required this.backgroundMid,

    // ── Accent / Primary ────────────────────────────────────────────
    required this.accentPrimary,
    required this.accentLight,
    required this.accentDark,

    // ── Secondary accent ────────────────────────────────────────────
    required this.secondaryAccent,

    // ── UI surfaces ─────────────────────────────────────────────────
    required this.surfaceDark,
    required this.surfacePanel,

    // ── Text ────────────────────────────────────────────────────────
    required this.textPrimary,
    required this.textSecondary,

    // ── Card face ───────────────────────────────────────────────────
    required this.cardFace,
    required this.suitRed,
    required this.suitBlack,

    // ── Start-screen overlay gradient ───────────────────────────────
    required this.overlayTop,
    required this.overlayBottom,

    // ── Swatch preview colors (shown in the picker) ─────────────────
    required this.swatchPreview,

    // ── Progression gate ─────────────────────────────────────────────
    required this.minUnlockLevel,

    // ── Optional: one-shot trial ──────────────────────────────────────
    // When set, a player below minUnlockLevel may equip this theme for
    // this many completed games (any mode) before it auto-reverts. Null
    // means no trial is offered — the theme is simply locked.
    this.trialGames,

    // ── Optional: instant coin unlock ──────────────────────────────────
    // Coin price to permanently unlock this theme before reaching
    // minUnlockLevel. Null means it isn't coin-purchasable (e.g. themes
    // that are already free by default).
    this.coinUnlockCost,

    // ── Optional: real-money cash unlock ───────────────────────────────
    // Non-consumable IAP product ID for buying this theme outright. Must
    // match a product configured in App Store Connect / Google Play
    // Console (and, for local simulator testing, in
    // ios/Runner/Configuration.storekit). Null means it isn't
    // cash-purchasable.
    this.cashUnlockProductId,

    // ── Optional: font family override ('playfair', 'cinzel', etc.) ─
    this.headingFontFamily = 'playfair',

    // ── Optional: Joker card face overrides ─────────────────────────
    // If null, JokerCardWidget uses its built-in dark-navy / gold defaults.
    this.jokerBackgroundColors,
    this.jokerBorderColor,
    this.jokerAccentColor,
  });

  final String id;
  final String name;

  final Color backgroundDeep;
  final Color backgroundMid;

  final Color accentPrimary;
  final Color accentLight;
  final Color accentDark;
  final Color secondaryAccent;

  final Color surfaceDark;
  final Color surfacePanel;

  final Color textPrimary;
  final Color textSecondary;

  final Color cardFace;
  final Color suitRed;
  final Color suitBlack;

  final Color overlayTop;
  final Color overlayBottom;

  final List<Color> swatchPreview; // 2-3 colors for the swatch tile gradient

  /// Player level required to unlock this theme (see `PlayerLevelService`).
  final int minUnlockLevel;

  /// Number of completed games (any mode) a locked-out player may trial
  /// this theme for before it auto-reverts. Null means no trial.
  final int? trialGames;

  /// Coin price to permanently unlock this theme early. Null means it
  /// isn't coin-purchasable.
  final int? coinUnlockCost;

  /// Non-consumable IAP product ID to buy this theme outright. Null means
  /// it isn't cash-purchasable.
  final String? cashUnlockProductId;

  final String headingFontFamily;

  /// Two-stop gradient colors for the Joker card background.
  /// Null means use the default dark-navy gradient.
  final List<Color>? jokerBackgroundColors;

  /// Border color for the Joker card.
  /// Null means use [AppColors.goldDark].
  final Color? jokerBorderColor;

  /// Accent color used for the Joker emblem, shimmer, glow and label.
  /// Null means use [AppColors.goldPrimary].
  final Color? jokerAccentColor;
}

// ── Builder ──────────────────────────────────────────────────────────────────

TextStyle _heading(
  AppThemeData t, {
  required Color color,
  double? size,
}) {
  if (t.headingFontFamily == 'cinzel') {
    return GoogleFonts.cinzel(
      fontSize: size ?? 22,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      color: color,
    );
  }
  return GoogleFonts.playfairDisplay(
    fontSize: size ?? 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
    color: color,
  );
}

/// Splash / game title typography — same family as [_heading] (Playfair vs Cinzel).
TextStyle gameTitleTextStyle(
  AppThemeData t, {
  required double fontSize,
  FontWeight fontWeight = FontWeight.w600,
  double letterSpacing = 0.8,
  required Color color,
  List<Shadow>? shadows,
}) {
  if (t.headingFontFamily == 'cinzel') {
    return GoogleFonts.cinzel(
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      shadows: shadows,
    );
  }
  return GoogleFonts.playfairDisplay(
    fontSize: fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
    shadows: shadows,
  );
}

/// Converts an [AppThemeData] preset into a Flutter [ThemeData].
ThemeData buildThemeData(AppThemeData t) {
  final base = ThemeData.dark();

  return base.copyWith(
    scaffoldBackgroundColor: t.backgroundDeep,
    colorScheme: ColorScheme.dark(
      primary: t.accentPrimary,
      onPrimary: t.backgroundDeep,
      secondary: t.secondaryAccent,
      onSecondary: t.textPrimary,
      surface: t.backgroundMid,
      onSurface: t.textPrimary,
      error: const Color(0xFFC0392B),
      onError: t.textPrimary,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: _heading(t, color: t.accentPrimary, size: 36),
      headlineLarge: _heading(t, color: t.textPrimary, size: 28),
      headlineMedium: _heading(t, color: t.textPrimary, size: 22),
      labelLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        color: t.textPrimary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: t.textPrimary,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: t.textSecondary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: t.textPrimary,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.accentPrimary,
        foregroundColor: t.backgroundDeep,
        textStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.accentPrimary,
        side: BorderSide(color: t.accentPrimary, width: 1),
        textStyle: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: t.accentPrimary,
        ),
        minimumSize: const Size(88, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surfacePanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: t.accentPrimary, width: 1),
      ),
      titleTextStyle: _heading(t, color: t.textPrimary, size: 22),
      contentTextStyle: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: t.textPrimary,
      ),
    ),
    dividerColor: t.accentDark,
    iconTheme: IconThemeData(color: t.textSecondary),
    cardTheme: CardThemeData(
      color: t.surfacePanel,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surfacePanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accentPrimary,
      thumbColor: t.accentPrimary,
      overlayColor: t.accentPrimary.withValues(alpha: 0.2),
      inactiveTrackColor: t.accentDark.withValues(alpha: 0.4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? t.accentPrimary
            : t.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? t.accentPrimary.withValues(alpha: 0.4)
            : t.surfacePanel,
      ),
    ),
  );
}
