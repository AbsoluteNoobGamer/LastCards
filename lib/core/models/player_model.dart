import 'package:freezed_annotation/freezed_annotation.dart';

import 'card_model.dart';

part 'player_model.freezed.dart';
part 'player_model.g.dart';

/// Represents the table position of a player relative to the local player.
///
/// The first four values cover the standard 2–4 player game.
/// Additional values support Bust mode (up to 10 players).
enum TablePosition {
  bottom,
  top,
  left,
  right,
  bottomLeft,
  topLeft,
  topRight,
  bottomRight,
  farLeft,
  farRight,
}

@freezed
class PlayerModel with _$PlayerModel {
  const factory PlayerModel({
    required String id,
    required String displayName,
    required TablePosition tablePosition,

    /// Cards in hand — populated only for the local player.
    /// For opponents, this is always empty (server sends count only).
    @Default([]) List<CardModel> hand,

    /// Number of cards the player holds. Always accurate for all players.
    @Default(0) int cardCount,

    /// Set when this player's turn begins: their hand could be emptied in one
    /// legal turn (Last Cards rule). Server-authoritative for online opponents.
    @Default(false) bool lastCardsHandWasClearableAtTurnStart,
  }) = _PlayerModel;

  factory PlayerModel.fromJson(Map<String, dynamic> json) =>
      _$PlayerModelFromJson(json);
}
