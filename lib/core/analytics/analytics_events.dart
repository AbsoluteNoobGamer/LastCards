/// Analytics event name and parameter key taxonomy.
///
/// Single source of truth for every Firebase Analytics event name and
/// parameter key used by [AnalyticsService] — see docs/analytics-plan.md
/// §3 (Phase 1) for the conventions these must follow: snake_case, ≤ 40
/// character names, kept in sync with `test/core/analytics/
/// analytics_events_test.dart`.
abstract final class AnalyticsEvents {
  static const String gameStarted = 'game_started';
  static const String gameCompleted = 'game_completed';
  static const String rankedGamePlayed = 'ranked_game_played';
  static const String tournamentCompleted = 'tournament_completed';
  static const String themeChanged = 'theme_changed';
  static const String cardBackChanged = 'card_back_changed';
  static const String lastCardsDeclared = 'last_cards_declared';
  static const String comboPlayed = 'combo_played';
  static const String levelUp = 'level_up';
  static const String leaderboardViewed = 'leaderboard_viewed';
  static const String settingsOpened = 'settings_opened';
  static const String cardStyleMenuOpened = 'card_style_menu_opened';
  static const String gameAbandoned = 'game_abandoned';
  static const String reconnectAttempted = 'reconnect_attempted';
  static const String reconnectSucceeded = 'reconnect_succeeded';
  static const String reconnectFailed = 'reconnect_failed';
  static const String matchmakingStarted = 'matchmaking_started';
  static const String matchmakingMatched = 'matchmaking_matched';
  static const String matchmakingCancelled = 'matchmaking_cancelled';
}

abstract final class AnalyticsParams {
  static const String mode = 'mode';
  static const String playerCount = 'player_count';
  static const String isWin = 'is_win';
  static const String durationSeconds = 'duration_seconds';
  static const String mmrBefore = 'mmr_before';
  static const String mmrAfter = 'mmr_after';
  static const String result = 'result';
  static const String roundsPlayed = 'rounds_played';
  static const String themeId = 'theme_id';
  static const String designId = 'design_id';
  static const String cardCount = 'card_count';
  static const String tier = 'tier';
  static const String newLevel = 'new_level';
  static const String endedBy = 'ended_by';
  static const String secondsIn = 'seconds_in';
  static const String turnIndex = 'turn_index';
  static const String reason = 'reason';
  static const String waitSeconds = 'wait_seconds';
}
