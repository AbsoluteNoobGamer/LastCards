import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/analytics/analytics_events.dart';

/// Kept in sync by hand with [AnalyticsEvents] / [AnalyticsParams] — Dart
/// has no reflection available in Flutter tests to auto-discover them.
const _eventNames = <String>[
  AnalyticsEvents.gameStarted,
  AnalyticsEvents.gameCompleted,
  AnalyticsEvents.rankedGamePlayed,
  AnalyticsEvents.tournamentCompleted,
  AnalyticsEvents.themeChanged,
  AnalyticsEvents.cardBackChanged,
  AnalyticsEvents.lastCardsDeclared,
  AnalyticsEvents.comboPlayed,
  AnalyticsEvents.levelUp,
  AnalyticsEvents.leaderboardViewed,
  AnalyticsEvents.settingsOpened,
  AnalyticsEvents.cardStyleMenuOpened,
  AnalyticsEvents.gameAbandoned,
  AnalyticsEvents.reconnectAttempted,
  AnalyticsEvents.reconnectSucceeded,
  AnalyticsEvents.reconnectFailed,
  AnalyticsEvents.matchmakingStarted,
  AnalyticsEvents.matchmakingMatched,
  AnalyticsEvents.matchmakingCancelled,
];

const _paramKeys = <String>[
  AnalyticsParams.mode,
  AnalyticsParams.playerCount,
  AnalyticsParams.isWin,
  AnalyticsParams.durationSeconds,
  AnalyticsParams.mmrBefore,
  AnalyticsParams.mmrAfter,
  AnalyticsParams.result,
  AnalyticsParams.roundsPlayed,
  AnalyticsParams.themeId,
  AnalyticsParams.designId,
  AnalyticsParams.cardCount,
  AnalyticsParams.tier,
  AnalyticsParams.newLevel,
  AnalyticsParams.endedBy,
  AnalyticsParams.secondsIn,
  AnalyticsParams.turnIndex,
  AnalyticsParams.reason,
  AnalyticsParams.waitSeconds,
];

final _snakeCase = RegExp(r'^[a-z][a-z0-9_]*$');

void main() {
  test('event names are snake_case and within 40 characters', () {
    for (final name in _eventNames) {
      expect(_snakeCase.hasMatch(name), isTrue, reason: '"$name" is not snake_case');
      expect(name.length, lessThanOrEqualTo(40), reason: '"$name" exceeds 40 characters');
    }
  });

  test('param keys are snake_case and within 40 characters', () {
    for (final key in _paramKeys) {
      expect(_snakeCase.hasMatch(key), isTrue, reason: '"$key" is not snake_case');
      expect(key.length, lessThanOrEqualTo(40), reason: '"$key" exceeds 40 characters');
    }
  });

  test('event names have no duplicates', () {
    expect(_eventNames.toSet().length, _eventNames.length);
  });

  test('param keys have no duplicates', () {
    expect(_paramKeys.toSet().length, _paramKeys.length);
  });
}
