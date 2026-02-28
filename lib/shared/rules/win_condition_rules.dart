import '../models/game_state_model.dart';

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

  // Pick-up card deferral: chain must resolve first.
  if (state.activePenaltyCount > 0 && winner.id == state.currentPlayerId) {
    return false;
  }

  // Queen lock deferral: must be covered first.
  if (state.queenSuitLock != null && winner.id == state.currentPlayerId) {
    return false;
  }

  return true;
}
