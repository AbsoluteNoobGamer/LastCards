/// Immutable snapshot of Bust mode round progress.
///
/// One [BustRoundState] is created when a new round begins and replaced
/// (not mutated) each time [BustRoundManager] advances state.
class BustRoundState {
  const BustRoundState({
    required this.roundNumber,
    required this.activePlayerIds,
    required this.eliminatedIds,
    required this.turnsThisRound,
    required this.penaltyPoints,
    required this.playerOrder,
  });

  /// 1-based round counter (1 = first round with 10 players, etc.)
  final int roundNumber;

  /// Players still competing — ordered by play order for this round.
  final List<String> activePlayerIds;

  /// All players eliminated across all previous rounds.
  final List<String> eliminatedIds;

  /// How many turns each active player has taken in the current round.
  /// A round ends when every active player has taken exactly 2 turns.
  final Map<String, int> turnsThisRound;

  /// Running cumulative penalty points per player (cards remaining at each
  /// round end are added here). Never decreases.
  final Map<String, int> penaltyPoints;

  /// Fixed play order for the current round (set at round start).
  final List<String> playerOrder;

  // ── Derived helpers ─────────────────────────────────────────────────────────

  /// Total turns per round = 2 full rotations × active player count.
  int get turnsPerRound => activePlayerIds.length * 2;

  /// Turns already taken across the whole current round.
  int get turnsTakenThisRound =>
      turnsThisRound.values.fold(0, (a, b) => a + b);

  /// Which rotation we are currently in (1 or 2).
  int get currentRotation {
    final taken = turnsTakenThisRound;
    if (taken < activePlayerIds.length) return 1;
    return 2;
  }

  /// The last round (two survivors): race to empty hand — no turn-cap ending.
  bool get isFinalShowdown => activePlayerIds.length == 2;

  /// True when every active player has taken 2 turns.
  ///
  /// In the [isFinalShowdown], the round never completes from turn count; it
  /// ends when someone empties their hand ([BustRoundManager.finalizeRound]).
  bool get isRoundComplete =>
      !isFinalShowdown &&
      activePlayerIds.every((id) => (turnsThisRound[id] ?? 0) >= 2);

  BustRoundState copyWith({
    int? roundNumber,
    List<String>? activePlayerIds,
    List<String>? eliminatedIds,
    Map<String, int>? turnsThisRound,
    Map<String, int>? penaltyPoints,
    List<String>? playerOrder,
  }) {
    return BustRoundState(
      roundNumber: roundNumber ?? this.roundNumber,
      activePlayerIds: activePlayerIds ?? this.activePlayerIds,
      eliminatedIds: eliminatedIds ?? this.eliminatedIds,
      turnsThisRound: turnsThisRound ?? this.turnsThisRound,
      penaltyPoints: penaltyPoints ?? this.penaltyPoints,
      playerOrder: playerOrder ?? this.playerOrder,
    );
  }
}

/// The local human player's performance in a single round.
///
/// Accumulated across rounds and shown on [BustWinnerScreen] as a personal
/// journey summary when the local player is eliminated.
class BustLocalRoundStat {
  const BustLocalRoundStat({
    required this.roundNumber,
    required this.survived,
    required this.cardsRemaining,
    required this.cardsDealt,
  });

  /// 1-based round number.
  final int roundNumber;

  /// True if the local player was NOT eliminated at the end of this round.
  final bool survived;

  /// Cards still in hand when the round ended.
  final int cardsRemaining;

  /// Cards dealt at the start of this round (for drop calculation).
  final int cardsDealt;

  /// Cards successfully played/shed during this round.
  int get cardsShed => (cardsDealt - cardsRemaining).clamp(0, cardsDealt);
}

/// A single player's final placement record, carried across all rounds so
/// [BustWinnerScreen] can show a complete leaderboard for all participants.
class BustEliminationRecord {
  const BustEliminationRecord({
    required this.playerName,
    required this.roundEliminated,
    required this.cardsAtElimination,
    required this.isLocal,
  });

  /// Display name of the player.
  final String playerName;

  /// The 1-based round number in which this player was eliminated.
  final int roundEliminated;

  /// Cards remaining in hand when eliminated — used for tie-breaking within
  /// the same round (fewer = higher placement).
  final int cardsAtElimination;

  /// True when this record belongs to the local human player.
  final bool isLocal;
}

/// The outcome of a completed round — who gets eliminated and the final
/// standings used by [BustEliminationScreen].
class BustRoundResult {
  const BustRoundResult({
    required this.roundNumber,
    required this.standingsThisRound,
    required this.cumulativePenalties,
    required this.eliminatedThisRound,
    required this.survivorIds,
    required this.isGameOver,
    this.winnerId,
  });

  final int roundNumber;

  /// Ordered list of (playerId, cardsRemaining) for this round — best first.
  final List<({String playerId, String playerName, int cardsThisRound, int totalPenalty})> standingsThisRound;

  /// Full cumulative penalty map after this round.
  final Map<String, int> cumulativePenalties;

  /// Players eliminated after this round (1 or 2 depending on survivor count).
  final List<String> eliminatedThisRound;

  /// Players continuing to the next round.
  final List<String> survivorIds;

  /// True when the game is finished (only 1 survivor).
  final bool isGameOver;

  /// Set only when [isGameOver] is true.
  final String? winnerId;
}
