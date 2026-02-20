import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Root [ThemeData] for Stack & Flow's dark felt aesthetic.
abstract final class AppTheme {
  static ThemeData get darkTheme {
    final base = ThemeData.dark();

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.feltDeep,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.goldPrimary,
        onPrimary: AppColors.feltDeep,
        secondary: AppColors.redAccent,
        onSecondary: AppColors.textPrimary,
        surface: AppColors.feltMid,
        onSurface: AppColors.textPrimary,
        error: AppColors.redSoft,
        onError: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: AppTypography.gameTitle,
        headlineLarge: AppTypography.heading1,
        headlineMedium: AppTypography.heading2,
        labelLarge: AppTypography.labelLarge,
        labelMedium: AppTypography.labelMedium,
        labelSmall: AppTypography.labelSmall,
        bodyMedium: AppTypography.bodyText,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.goldPrimary,
          foregroundColor: AppColors.feltDeep,
          textStyle: AppTypography.buttonPrimary,
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.goldPrimary,
          side: const BorderSide(color: AppColors.goldPrimary, width: 1),
          textStyle: AppTypography.buttonSecondary,
          minimumSize: const Size(88, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.surfacePanel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.goldPrimary, width: 1),
        ),
        titleTextStyle: AppTypography.heading2,
        contentTextStyle: AppTypography.bodyText,
      ),
      dividerColor: AppColors.goldDark,
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      cardTheme: CardTheme(
        color: AppColors.surfacePanel,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
