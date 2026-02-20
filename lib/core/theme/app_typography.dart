import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography presets aligned with the design spec.
///
/// - Display / Headings → Playfair Display (serif prestige)
/// - UI Labels / Body   → Inter (clean, legible)
/// - Card Ranks         → Libre Baskerville (bold, high-contrast)
abstract final class AppTypography {
  // ── Display ─────────────────────────────────────────────────────
  static TextStyle get gameTitle => GoogleFonts.playfairDisplay(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: const Color(0xFFC9A84C), // gold-primary
      );

  static TextStyle get heading1 => GoogleFonts.playfairDisplay(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: const Color(0xFFF5EFE0),
      );

  static TextStyle get heading2 => GoogleFonts.playfairDisplay(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: const Color(0xFFF5EFE0),
      );

  // ── UI Labels ────────────────────────────────────────────────────
  static TextStyle get labelLarge => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        color: const Color(0xFFF5EFE0),
      );

  static TextStyle get labelMedium => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
        color: const Color(0xFFF5EFE0),
      );

  static TextStyle get labelSmall => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: const Color(0xFFB0A080), // text-secondary
      );

  static TextStyle get bodyText => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.2,
        color: const Color(0xFFF5EFE0),
      );

  // ── Card rank ────────────────────────────────────────────────────
  static TextStyle cardRank({
    required Color color,
    required double fontSize,
  }) =>
      GoogleFonts.libreBaskerville(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
        height: 1,
      );

  // ── Button text ──────────────────────────────────────────────────
  static TextStyle get buttonPrimary => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: const Color(0xFF0D2B1A), // dark text on gold button
      );

  static TextStyle get buttonSecondary => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: const Color(0xFFC9A84C), // gold text on transparent button
      );
}
