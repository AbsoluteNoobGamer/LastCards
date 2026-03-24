import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'card_model.dart';
import 'player_model.dart';

part 'game_state.freezed.dart';
part 'game_state.g.dart';

Set<String> _stringSetFromJson(Object? json) {
  if (json == null) return {};
  return (json as List<dynamic>).map((e) => e as String).toSet();
}

List<String> _stringSetToJson(Set<String> set) => set.toList();

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

    /// Cards under the discard top (2nd, 3rd, ...) for visual stacking.
    @Default([]) List<CardModel> discardPileHistory,

    /// Number of cards remaining in the draw pile.
    @Default(0) int drawPileCount,

    /// Accumulated draw penalty count (from stacked 2s and Black Jacks).
    @Default(0) int activePenaltyCount,

    /// True while the pick-up "chain" is conceptually active for matching: a
    /// penalty card (2 or Jack) was last relevant, so penalty-on-penalty free
    /// matching may apply. Stays true after a Red Jack zeros [activePenaltyCount]
    /// until someone draws or a non-penalty card ends the chain (see engine).
    @Default(false) bool penaltyChainLive,

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

    /// Player IDs that pressed "Last Cards" (visible to all players).
    @JsonKey(fromJson: _stringSetFromJson, toJson: _stringSetToJson)
    @Default({})
    Set<String> lastCardsDeclaredBy,
  }) = _GameState;

  factory GameState.fromJson(Map<String, dynamic> json) =>
      _$GameStateFromJson(json);
}

extension GameStateX on GameState {
  PlayerModel? get localPlayer => players.isEmpty ? null : players.first;

  PlayerModel? playerById(String id) =>
      players.firstWhereOrNull((p) => p.id == id);

  bool get isLocalPlayerTurn =>
      localPlayer != null && currentPlayerId == localPlayer!.id;

  bool get hasActivePenalty => activePenaltyCount > 0;

  /// True when either a draw penalty is pending or the pick-up chain is still
  /// live for penalty-on-penalty matching (e.g. after a Red Jack cancels count).
  bool get isPenaltyChainActive => activePenaltyCount > 0 || penaltyChainLive;

  bool get hasQueenLock => queenSuitLock != null;
}
