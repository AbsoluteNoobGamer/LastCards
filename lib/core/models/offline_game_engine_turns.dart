part of 'offline_game_engine.dart';

// ── Turn advancement ──────────────────────────────────────────────────────────

/// Returns the next player's ID, honouring direction and optional skip.
String nextPlayerId({
  required GameState state,
}) {
  final players = state.players;
  final currentIndex = players.indexWhere((p) => p.id == state.currentPlayerId);
  if (currentIndex < 0) return state.currentPlayerId;

  // In a 2-player game, playing a King (Reverse) acts as a Skip.
  // The player gets another turn immediately.
  final lastCard = state.lastPlayedThisTurn;
  final isKingPlayed = lastCard != null && lastCard.effectiveRank == Rank.king;
  if (players.length == 2 && isKingPlayed) {
    return state.currentPlayerId;
  }

  final step = state.direction == PlayDirection.clockwise ? 1 : -1;
  int next = currentIndex;
  final advances = 1 + state.activeSkipCount;

  for (int i = 0; i < advances; i++) {
    next = (next + step) % players.length;
    if (next < 0) next += players.length;
  }

  return players[next].id;
}
