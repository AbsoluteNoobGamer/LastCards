import '../models/game_state_model.dart';

/// Returns `true` when [playerId] can be safely confirmed as winner right now.
///
/// A player with zero cards is not confirmed while a pick-up chain is still
/// active, because that chain can legally return and force them to draw.
bool canConfirmPlayerWin({
  required GameState state,
  required String playerId,
}) {
  final candidate = state.players.where((p) => p.id == playerId).firstOrNull;
  if (candidate == null) return false;
  if (candidate.cardCount != 0 || candidate.hand.isNotEmpty) return false;

  // Pick-up card deferral: chain must fully resolve first.
  if (state.activePenaltyCount > 0) {
    return false;
  }

  // Queen lock deferral: must be covered first by the active player.
  if (state.queenSuitLock != null && playerId == state.currentPlayerId) {
    return false;
  }

  return true;
}

/// Pure win condition logic: immediate vs deferred win.
///
/// Returns `true` only if the win would be confirmed immediately.
/// Returns `false` if the win is deferred (pick-up chain still active,
/// or Queen lock not yet resolved) or if no winner exists.
bool wouldConfirmWin(GameState state) {
  final winner = state.players
      .where((p) => p.hand.isEmpty && p.cardCount == 0)
      .firstOrNull;

  if (winner == null) return false;
  return canConfirmPlayerWin(state: state, playerId: winner.id);
}
