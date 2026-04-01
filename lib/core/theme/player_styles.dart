import 'package:flutter/material.dart';
import '../models/player_model.dart';
import 'app_colors.dart';

/// Provides consistent, accessible colors and shape icons for players based on their table position.
abstract final class PlayerStyles {
  /// Returns a distinct, color-blind friendly color for the given active table position.
  static Color getColor(TablePosition pos) {
    switch (pos) {
      case TablePosition.bottom:
        return AppColors.blueAccent; // Local / P1
      case TablePosition.left:
      case TablePosition.farLeft:
        return AppColors.redSoft; // P2
      case TablePosition.top:
      case TablePosition.topLeft:
      case TablePosition.topRight:
        return const Color(0xFF4AE280); // P3
      case TablePosition.right:
      case TablePosition.farRight:
        return const Color(0xFFB04AE2); // P4
      case TablePosition.bottomLeft:
      case TablePosition.bottomRight:
        return const Color(0xFFE29C4A); // Extended positions
    }
  }

  /// Returns an accessible Material shape icon acting as a redundant cue independent of color-blindness.
  static IconData getIcon(TablePosition pos) {
    switch (pos) {
      case TablePosition.bottom:
        return Icons.circle;
      case TablePosition.left:
      case TablePosition.farLeft:
        return Icons.square;
      case TablePosition.top:
      case TablePosition.topLeft:
      case TablePosition.topRight:
        return Icons.change_history; // Triangle
      case TablePosition.right:
      case TablePosition.farRight:
        return Icons.star;
      case TablePosition.bottomLeft:
      case TablePosition.bottomRight:
        return Icons.hexagon;
    }
  }
}
