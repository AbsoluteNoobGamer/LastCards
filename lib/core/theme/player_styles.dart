import 'package:flutter/material.dart';
import '../models/player_model.dart';
import 'app_colors.dart';

/// Provides consistent, accessible colors and shape icons for players based on their table position.
abstract final class PlayerStyles {
  /// Returns a distinct, color-blind friendly color for the given active table position.
  static Color getColor(TablePosition pos) {
    switch (pos) {
      case TablePosition.bottom: return AppColors.blueAccent;            // Local / P1
      case TablePosition.left: return AppColors.redSoft;                 // Round-robin P2
      case TablePosition.top: return const Color(0xFF4AE280);            // Round-robin P3
      case TablePosition.right: return const Color(0xFFB04AE2);          // Round-robin P4
    }
  }

  /// Returns an accessible Material shape icon acting as a redundant cue independent of color-blindness.
  static IconData getIcon(TablePosition pos) {
    switch (pos) {
      case TablePosition.bottom: return Icons.circle;
      case TablePosition.left: return Icons.square;
      case TablePosition.top: return Icons.change_history; // Triangle
      case TablePosition.right: return Icons.star;
    }
  }
}
