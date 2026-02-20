import 'package:freezed_annotation/freezed_annotation.dart';

import 'card_model.dart';
import 'player_model.dart';

part 'game_state.freezed.dart';
part 'game_state.g.dart';

/// Phase of a game session.
enum GamePhase { lobby, playing, ended }

/// Direction of play around the table.
enum PlayDirection { clockwise, counterClockwise }

@freezed
class GameState with _$GameState {
  const factory GameState({
    required String sessionId,
    required GamePhase phase,
    required List<PlayerModel> players,
    required String currentPlayerId,
    required PlayDirection direction,

    /// Top card of the discard pile (null only before first card is turned).
    CardModel? discardTopCard,

    /// Second-from-top card for visual stacking effect on the discard pile.
    CardModel? discardSecondCard,

    /// Number of cards remaining in the draw pile.
    @Default(0) int drawPileCount,

    /// Accumulated draw penalty count (from stacked 2s and Black Jacks).
    @Default(0) int activePenaltyCount,

    /// Active suit lock from an Ace or Joker declaration.
    Suit? suitLock,

    /// Active suit from a Queen — the next player MUST follow this suit.
    Suit? queenSuitLock,

    /// ID of the player who has won (null if game not yet ended).
    String? winnerId,

    /// Server timestamp of the last state update (for stale detection).
    @Default(0) int lastUpdatedAt,

    /// Number of valid actions (plays) taken by the current player this turn.
    /// Resets to 0 whenever the active player changes.
    /// Used to enforce that a player must play or draw before ending their turn.
    @Default(0) int actionsThisTurn,
  }) = _GameState;

  factory GameState.fromJson(Map<String, dynamic> json) =>
      _$GameStateFromJson(json);
}

extension GameStateX on GameState {
  PlayerModel? get localPlayer => players.isEmpty ? null : players.first;

  PlayerModel? playerById(String id) {
    try {
      return players.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  bool get isLocalPlayerTurn =>
      localPlayer != null && currentPlayerId == localPlayer!.id;

  bool get hasActivePenalty => activePenaltyCount > 0;

  bool get hasQueenLock => queenSuitLock != null;
}
