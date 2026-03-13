/// Server-side trophy/leaderboard recording.
///
/// Records wins and leave penalties for ranked online games.
/// No-op until auth and backend are implemented.
///
/// When ready: wire this to your leaderboard API/database using [userId].
/// Currently [playerId] is session-scoped; replace with persistent [userId].
class TrophyRecorder {
  TrophyRecorder._();
  static final TrophyRecorder instance = TrophyRecorder._();

  /// Record a win for [playerId] in ranked quickplay.
  ///
  /// Called when the game ends with a clear winner and trophies are eligible
  /// (max players joined, not private lobby).
  void recordWin(String playerId) {
    // TODO: Replace with backend call when auth exists.
    // Example: api.recordWin(userId: getUserId(playerId), mode: 'quickplay');
  }

  /// Record a leave penalty for [playerId] who disconnected during a ranked game.
  ///
  /// Called when a player leaves mid-game and trophies would have applied.
  void recordLeavePenalty(String playerId) {
    // TODO: Replace with backend call when auth exists.
    // Example: api.recordLeavePenalty(userId: getUserId(playerId), mode: 'quickplay');
  }
}
