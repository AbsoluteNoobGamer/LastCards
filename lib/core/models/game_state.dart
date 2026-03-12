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

    /// Cards under the discard top (2nd, 3rd, ...) for visual stacking.
    @Default([]) List<CardModel> discardPileHistory,

    /// Number of cards remaining in the draw pile.
    @Default(0) int drawPileCount,

    /// Accumulated draw penalty count (from stacked 2s and Black Jacks).
    @Default(0) int activePenaltyCount,

    /// Accumulated skips built up during a turn by playing 8s.
    @Default(0) int activeSkipCount,

    /// Active suit lock from an Ace or Joker declaration.
    Suit? suitLock,

    /// The suit of the centre pile before the first card of the turn was played.
    /// Used to validate sequence continuations originating from an Ace play.
    Suit? preTurnCentreSuit,

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

    /// Number of individual cards played by the current player this turn.
    /// Resets to 0 whenever the active player changes (at start of each new turn).
    /// Used to determine if an Ace was played alone or as part of a sequence.
    @Default(0) int cardsPlayedThisTurn,

    /// The last card played by the current player this turn (as a single play).
    /// Used to enforce rank-adjacency between consecutive individual plays within
    /// the same turn (Numerical Flow Rule). Reset to null when the turn advances.
    CardModel? lastPlayedThisTurn,

    /// True while a Joker has been committed as a play but still needs
    /// its represented card selection to be finalized in UI.
    @Default(false) bool pendingJokerResolution,
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
