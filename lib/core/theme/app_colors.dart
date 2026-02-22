import 'package:flutter/material.dart';

/// Color tokens from the Stack & Flow design specification.
abstract final class AppColors {
  // ── Primary backgrounds ──────────────────────────────────────────
  static const Color feltDeep = Color(0xFF0D2B1A);
  static const Color feltMid = Color(0xFF1A3D2B);
  static const Color burgundyDeep = Color(0xFF2B0D17);
  static const Color burgundyMid = Color(0xFF3D1A24);

  // ── Accent colors ────────────────────────────────────────────────
  static const Color goldPrimary = Color(0xFFC9A84C);
  static const Color goldLight = Color(0xFFE8CC7A);
  static const Color goldDark = Color(0xFF8A6D28);
  static const Color redAccent = Color(0xFF9B2335);
  static const Color redSoft = Color(0xFFC0392B);
  static const Color blueAccent = Color(0xFF4A90E2);

  // ── UI Neutrals ──────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF5EFE0);
  static const Color textSecondary = Color(0xFFB0A080);
  static const Color surfaceDark = Color(0xFF0A0A0A);
  static const Color surfacePanel = Color(0xFF1C1C1C);

  // ── Card colors ──────────────────────────────────────────────────
  static const Color cardFace = Color(0xFFFAF6ED);
  static const Color suitBlack = Color(0xFF1A1A2E); // Spades & Clubs
  static const Color suitRed = Color(0xFF9B2335); // Hearts & Diamonds

  // ── Utility ──────────────────────────────────────────────────────
  static const Color transparent = Colors.transparent;
  static const Color overlayDark = Color(0xBF000000); // rgba(0,0,0,0.75)
}
