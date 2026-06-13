import 'package:firebase_analytics/firebase_analytics.dart';

// To verify events: Firebase Console → Analytics → DebugView
// Run app with --dart-define=FLUTTER_TEST=false in debug mode

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  void logGameStarted({required String mode, required int playerCount}) {
    try {
      _analytics.logEvent(
        name: 'game_started',
        parameters: {
          'mode': mode,
          'player_count': playerCount,
        },
      );
    } catch (_) {}
  }

  void logGameCompleted({
    required String mode,
    required bool isWin,
    required int durationSeconds,
  }) {
    try {
      _analytics.logEvent(
        name: 'game_completed',
        parameters: {
          'mode': mode,
          'is_win': isWin,
          'duration_seconds': durationSeconds,
        },
      );
    } catch (_) {}
  }

  void logRankedGamePlayed({
    required bool isWin,
    required int mmrBefore,
    required int mmrAfter,
  }) {
    try {
      _analytics.logEvent(
        name: 'ranked_game_played',
        parameters: {
          'is_win': isWin,
          'mmr_before': mmrBefore,
          'mmr_after': mmrAfter,
        },
      );
    } catch (_) {}
  }

  void logTournamentCompleted({
    required String result,
    required int roundsPlayed,
  }) {
    try {
      _analytics.logEvent(
        name: 'tournament_completed',
        parameters: {
          'result': result,
          'rounds_played': roundsPlayed,
        },
      );
    } catch (_) {}
  }

  void logThemeChanged({required String themeId}) {
    try {
      _analytics.logEvent(
        name: 'theme_changed',
        parameters: {'theme_id': themeId},
      );
    } catch (_) {}
  }

  void logCardBackChanged({required String designId}) {
    try {
      _analytics.logEvent(
        name: 'card_back_changed',
        parameters: {'design_id': designId},
      );
    } catch (_) {}
  }

  void logLastCardsDeclared({required String mode}) {
    try {
      _analytics.logEvent(
        name: 'last_cards_declared',
        parameters: {'mode': mode},
      );
    } catch (_) {}
  }

  void logComboPlayed({required int cardCount, required int tier}) {
    try {
      _analytics.logEvent(
        name: 'combo_played',
        parameters: {
          'card_count': cardCount,
          'tier': tier,
        },
      );
    } catch (_) {}
  }

  void logLevelUp({required int newLevel}) {
    try {
      _analytics.logEvent(
        name: 'level_up',
        parameters: {'new_level': newLevel},
      );
    } catch (_) {}
  }

  void logLeaderboardViewed({required String mode}) {
    try {
      _analytics.logEvent(
        name: 'leaderboard_viewed',
        parameters: {'mode': mode},
      );
    } catch (_) {}
  }

  void logSettingsOpened() {
    try {
      _analytics.logEvent(name: 'settings_opened');
    } catch (_) {}
  }

  void logCardStyleMenuOpened() {
    try {
      _analytics.logEvent(name: 'card_style_menu_opened');
    } catch (_) {}
  }
}
