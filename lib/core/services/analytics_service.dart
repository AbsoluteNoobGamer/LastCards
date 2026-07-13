import 'package:firebase_analytics/firebase_analytics.dart';

import '../analytics/analytics_events.dart';

// To verify events: Firebase Console → Analytics → DebugView
// Run app with --dart-define=FLUTTER_TEST=false in debug mode

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  void logGameStarted({required String mode, required int playerCount}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.gameStarted,
        parameters: {
          AnalyticsParams.mode: mode,
          AnalyticsParams.playerCount: playerCount,
        },
      );
    } catch (_) {}
  }

  void logGameCompleted({
    required String mode,
    required bool isWin,
    required int durationSeconds,
    required String endedBy,
  }) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.gameCompleted,
        parameters: {
          AnalyticsParams.mode: mode,
          AnalyticsParams.isWin: isWin,
          AnalyticsParams.durationSeconds: durationSeconds,
          AnalyticsParams.endedBy: endedBy,
        },
      );
    } catch (_) {}
  }

  void logGameAbandoned({
    required String mode,
    required int secondsIn,
    required int turnIndex,
    required String reason,
  }) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.gameAbandoned,
        parameters: {
          AnalyticsParams.mode: mode,
          AnalyticsParams.secondsIn: secondsIn,
          AnalyticsParams.turnIndex: turnIndex,
          AnalyticsParams.reason: reason,
        },
      );
    } catch (_) {}
  }

  void logReconnectAttempted({required String mode}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.reconnectAttempted,
        parameters: {AnalyticsParams.mode: mode},
      );
    } catch (_) {}
  }

  void logReconnectSucceeded({required String mode}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.reconnectSucceeded,
        parameters: {AnalyticsParams.mode: mode},
      );
    } catch (_) {}
  }

  void logReconnectFailed({required String mode}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.reconnectFailed,
        parameters: {AnalyticsParams.mode: mode},
      );
    } catch (_) {}
  }

  void logMatchmakingStarted({required String mode}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.matchmakingStarted,
        parameters: {AnalyticsParams.mode: mode},
      );
    } catch (_) {}
  }

  void logMatchmakingMatched({
    required String mode,
    required int waitSeconds,
    required int playerCount,
  }) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.matchmakingMatched,
        parameters: {
          AnalyticsParams.mode: mode,
          AnalyticsParams.waitSeconds: waitSeconds,
          AnalyticsParams.playerCount: playerCount,
        },
      );
    } catch (_) {}
  }

  void logMatchmakingCancelled({
    required String mode,
    required int waitSeconds,
  }) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.matchmakingCancelled,
        parameters: {
          AnalyticsParams.mode: mode,
          AnalyticsParams.waitSeconds: waitSeconds,
        },
      );
    } catch (_) {}
  }

  void logMatchmakingTimeout({required String mode}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.matchmakingTimeout,
        parameters: {AnalyticsParams.mode: mode},
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
        name: AnalyticsEvents.rankedGamePlayed,
        parameters: {
          AnalyticsParams.isWin: isWin,
          AnalyticsParams.mmrBefore: mmrBefore,
          AnalyticsParams.mmrAfter: mmrAfter,
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
        name: AnalyticsEvents.tournamentCompleted,
        parameters: {
          AnalyticsParams.result: result,
          AnalyticsParams.roundsPlayed: roundsPlayed,
        },
      );
    } catch (_) {}
  }

  void logThemeChanged({required String themeId}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.themeChanged,
        parameters: {AnalyticsParams.themeId: themeId},
      );
    } catch (_) {}
  }

  void logCardBackChanged({required String designId}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.cardBackChanged,
        parameters: {AnalyticsParams.designId: designId},
      );
    } catch (_) {}
  }

  void logLastCardsDeclared({required String mode}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.lastCardsDeclared,
        parameters: {AnalyticsParams.mode: mode},
      );
    } catch (_) {}
  }

  void logComboPlayed({required int cardCount, required int tier}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.comboPlayed,
        parameters: {
          AnalyticsParams.cardCount: cardCount,
          AnalyticsParams.tier: tier,
        },
      );
    } catch (_) {}
  }

  void logLevelUp({required int newLevel}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.levelUp,
        parameters: {AnalyticsParams.newLevel: newLevel},
      );
    } catch (_) {}
  }

  void logLeaderboardViewed({required String mode}) {
    try {
      _analytics.logEvent(
        name: AnalyticsEvents.leaderboardViewed,
        parameters: {AnalyticsParams.mode: mode},
      );
    } catch (_) {}
  }

  void logSettingsOpened() {
    try {
      _analytics.logEvent(name: AnalyticsEvents.settingsOpened);
    } catch (_) {}
  }

  void logCardStyleMenuOpened() {
    try {
      _analytics.logEvent(name: AnalyticsEvents.cardStyleMenuOpened);
    } catch (_) {}
  }
}
