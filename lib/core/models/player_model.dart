import 'package:freezed_annotation/freezed_annotation.dart';

import 'card_model.dart';

part 'player_model.freezed.dart';
part 'player_model.g.dart';

/// Represents the table position of a player relative to the local player.
enum TablePosition { bottom, top, left, right }

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

    /// Whether the player is currently connected to the game session.
    @Default(true) bool isConnected,

    /// Whether it is currently this player's turn.
    @Default(false) bool isActiveTurn,

    /// Set to true when affected by an 8 (skip) card effect.
    @Default(false) bool isSkipped,
  }) = _PlayerModel;

  factory PlayerModel.fromJson(Map<String, dynamic> json) =>
      _$PlayerModelFromJson(json);
}
