import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/shared/rules/win_condition_rules.dart';

import 'models/bust_round_state.dart';

/// Manages round-level state for a Bust game session.
///
/// Responsibilities:
/// - Tracks how many turns each active player has taken this round
/// - Detects round completion (every active player has taken 2 turns)
/// - Calculates per-round card-count penalties and cumulative totals
/// - Determines which 1–2 players are eliminated at round end
///
/// [BustRoundManager] is stateful and held by [BustGameScreenState].
class BustRoundManager {
  BustRoundManager({
    required List<String> initialActivePlayerIds,
    required String firstPlayerId,
  }) : _state = BustRoundState(
          roundNumber: 1,
          activePlayerIds: List.unmodifiable(initialActivePlayerIds),
          eliminatedIds: const [],
          turnsThisRound: {for (final id in initialActivePlayerIds) id: 0},
          penaltyPoints: {for (final id in initialActivePlayerIds) id: 0},
          playerOrder: List.unmodifiable(
            _buildPlayerOrder(initialActivePlayerIds, firstPlayerId),
          ),
        );

  /// Constructs a manager for a subsequent round, restoring accumulated
  /// penalty points and the eliminated player list from a previous round.
  BustRoundManager.resumed({
    required List<String> survivorIds,
    required String firstPlayerId,
    required Map<String, int> penaltyPoints,
    required List<String> eliminatedIds,
    required int roundNumber,
  }) : _state = BustRoundState(
          roundNumber: roundNumber,
          activePlayerIds: List.unmodifiable(survivorIds),
          eliminatedIds: List.unmodifiable(eliminatedIds),
          turnsThisRound: {for (final id in survivorIds) id: 0},
          penaltyPoints: Map.unmodifiable(penaltyPoints),
          playerOrder: List.unmodifiable(
            _buildPlayerOrder(survivorIds, firstPlayerId),
          ),
        );

  BustRoundState _state;

  BustRoundState get state => _state;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Records that [playerId] has completed a turn.
  ///
  /// Call this once at the end of each player's turn (after their card play or
  /// draw, and after [endTurn] advances [GameState.currentPlayerId]).
  ///
  /// Returns the updated [BustRoundState]. Does nothing if the round is already
  /// complete or if [playerId] is not an active player.
  BustRoundState recordTurn(String playerId) {
    // Final showdown: no turn-cap — [isRoundComplete] is always false there.
    if (_state.isRoundComplete) return _state;
    if (!_state.activePlayerIds.contains(playerId)) return _state;

    final updated = Map<String, int>.from(_state.turnsThisRound);
    updated[playerId] = (updated[playerId] ?? 0) + 1;
    _state = _state.copyWith(turnsThisRound: updated);
    return _state;
  }

  /// Finalises the current round: adds card-count penalties, selects eliminated
  /// players, and prepares state for the next round (or signals game over).
  ///
  /// [gameState] must reflect the live [GameState] at round end so card counts
  /// are accurate. [playerNames] maps IDs to display names for the result.
  ///
  /// Returns a [BustRoundResult] describing eliminations and standings.
  /// After calling this, use [startNextRound] to reset turn tracking.
  BustRoundResult finalizeRound(
    GameState gameState,
    Map<String, String> playerNames,
  ) {
    // 1. Compute cards-remaining penalty for each active player
    final roundPenalties = <String, int>{};
    for (final id in _state.activePlayerIds) {
      final player = gameState.playerById(id);
      roundPenalties[id] = player?.hand.length ?? 0;
    }

    // 2. Add to cumulative penalties
    final newCumulative = Map<String, int>.from(_state.penaltyPoints);
    for (final id in _state.activePlayerIds) {
      newCumulative[id] = (newCumulative[id] ?? 0) + (roundPenalties[id] ?? 0);
    }

    final activeCount = _state.activePlayerIds.length;

    List<String> eliminatedThisRound;
    List<String> survivors;

    if (activeCount == 2) {
      // Final showdown: winner is whoever legally confirmed an empty hand first.
      String? raceWinner;
      for (final id in _state.activePlayerIds) {
        if (canConfirmPlayerWin(state: gameState, playerId: id)) {
          raceWinner = id;
          break;
        }
      }
      if (raceWinner != null) {
        eliminatedThisRound =
            _state.activePlayerIds.where((id) => id != raceWinner).toList();
        survivors = [raceWinner];
      } else {
        // Fallback if invoked without a confirmed empty-hand win.
        final sorted = List<String>.from(_state.activePlayerIds)
          ..sort((a, b) =>
              (newCumulative[b] ?? 0).compareTo(newCumulative[a] ?? 0));
        eliminatedThisRound = sorted.take(1).toList();
        survivors = sorted.skip(1).toList();
      }
    } else {
      // 3+. Sort by cumulative penalty (highest = worst), eliminate bottom 2.
      final sorted = List<String>.from(_state.activePlayerIds)
        ..sort((a, b) =>
            (newCumulative[b] ?? 0).compareTo(newCumulative[a] ?? 0));
      const eliminateCount = 2;
      eliminatedThisRound = sorted.take(eliminateCount).toList();
      survivors = sorted.skip(eliminateCount).toList();
    }

    // Standings: best first (winner / fewest effective penalty).
    final standingsOrder = [...survivors.reversed, ...eliminatedThisRound.reversed];
    final standings = standingsOrder.map((id) {
      return (
        playerId: id,
        playerName: playerNames[id] ?? id,
        cardsThisRound: roundPenalties[id] ?? 0,
        totalPenalty: newCumulative[id] ?? 0,
      );
    }).toList();

    final isGameOver = survivors.length <= 1;
    final winnerId = isGameOver && survivors.isNotEmpty ? survivors.first : null;

    // 6. Persist new penalties into state (next-round state set via startNextRound)
    _state = _state.copyWith(penaltyPoints: newCumulative);

    return BustRoundResult(
      roundNumber: _state.roundNumber,
      standingsThisRound: standings,
      cumulativePenalties: newCumulative,
      eliminatedThisRound: eliminatedThisRound,
      survivorIds: survivors,
      isGameOver: isGameOver,
      winnerId: winnerId,
    );
  }

  /// 1v1 bust finale: first active player with a legally confirmed empty hand.
  String? checkFinalShowdownWinner(GameState gameState) {
    if (!_state.isFinalShowdown) return null;
    for (final id in _state.activePlayerIds) {
      if (canConfirmPlayerWin(state: gameState, playerId: id)) {
        return id;
      }
    }
    return null;
  }

  /// Resets turn tracking and advances to the next round for [survivors].
  ///
  /// Call this after [finalizeRound] when the game is continuing.
  void startNextRound({
    required List<String> survivors,
    required String firstPlayerId,
    required List<String> allEliminated,
  }) {
    _state = BustRoundState(
      roundNumber: _state.roundNumber + 1,
      activePlayerIds: List.unmodifiable(survivors),
      eliminatedIds: List.unmodifiable(allEliminated),
      turnsThisRound: {for (final id in survivors) id: 0},
      penaltyPoints: _state.penaltyPoints,
      playerOrder: List.unmodifiable(
        _buildPlayerOrder(survivors, firstPlayerId),
      ),
    );
  }

  // ── Internal helpers ────────────────────────────────────────────────────────

  /// Builds a play-order list starting from [firstId] and cycling through
  /// [playerIds] in their original order.
  static List<String> _buildPlayerOrder(
      List<String> playerIds, String firstId) {
    final startIdx = playerIds.indexOf(firstId);
    if (startIdx < 0) return List<String>.from(playerIds);
    return [
      ...playerIds.sublist(startIdx),
      ...playerIds.sublist(0, startIdx),
    ];
  }
}
