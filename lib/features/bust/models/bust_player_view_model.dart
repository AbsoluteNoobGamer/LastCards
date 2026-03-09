import 'package:flutter/material.dart';
import 'package:last_cards/core/models/player_model.dart';

class BustPlayerViewModel {
  const BustPlayerViewModel({
    required this.id,
    required this.displayName,
    required this.cardCount,
    required this.isActive,
    this.isEliminated = false,
    this.isLocal = false,
    this.colorIndex = 0,
  });

  final String id;
  final String displayName;
  final int cardCount;
  final bool isActive;
  final bool isEliminated;
  final bool isLocal;
  final int colorIndex;

  /// 10-colour palette for the rail (color-blind friendly, distinct).
  /// Reuses the 4 PlayerStyles colors for indices 0–3 then extends.
  static const List<Color> railColors = [
    Color(0xFF4A90E2), // blue   (matches AppColors.blueAccent)
    Color(0xFFC0392B), // red    (matches AppColors.redSoft)
    Color(0xFF4AE280), // green  (matches PlayerStyles top)
    Color(0xFFB04AE2), // purple (matches PlayerStyles right)
    Color(0xFFE2A84A), // orange
    Color(0xFF4AE2D1), // teal
    Color(0xFFE24A7B), // pink
    Color(0xFF7BE24A), // lime
    Color(0xFFE2D14A), // yellow
    Color(0xFF4A68E2), // indigo
  ];

  Color get color => railColors[colorIndex % railColors.length];

  /// Factory from existing [PlayerModel] + external state.
  factory BustPlayerViewModel.fromPlayerModel(
    PlayerModel player, {
    required String currentPlayerId,
    required bool isEliminated,
    required bool isLocal,
    required int colorIndex,
  }) {
    return BustPlayerViewModel(
      id: player.id,
      displayName: player.displayName,
      cardCount: player.cardCount,
      isActive: player.id == currentPlayerId,
      isEliminated: isEliminated,
      isLocal: isLocal,
      colorIndex: colorIndex,
    );
  }
}
