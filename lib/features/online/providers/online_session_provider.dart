import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Queue join style (Select table vs Quick match) ────────────────────────────

enum OnlineQueueJoinStyle {
  /// User chose table size; sends `playerCount` in quickplay.
  selectTable,

  /// Server assigns a non-empty waiting queue for this rules tier.
  joinWaitingQueue,
}

// ── Game Mode Enum ────────────────────────────────────────────────────────────

enum OnlineGameMode {
  /// Casual online: choose table size (2–7), then quickplay with `playerCount`.
  selectTableCasual,

  /// Casual online: join an existing waiting queue; no `playerCount` from client.
  quickMatchCasual,

  privateGame,
  ranked,
  rankedHardcore;

  String get displayName {
    switch (this) {
      case OnlineGameMode.selectTableCasual:
        return 'Select table';
      case OnlineGameMode.quickMatchCasual:
        return 'Quick match';
      case OnlineGameMode.privateGame:
        return 'Private Game';
      case OnlineGameMode.ranked:
        return 'Ranked';
      case OnlineGameMode.rankedHardcore:
        return 'Ranked (Hardcore)';
    }
  }

  String get description {
    switch (this) {
      case OnlineGameMode.selectTableCasual:
        return 'Choose how many players, then find a match';
      case OnlineGameMode.quickMatchCasual:
        return 'Join a table that is already waiting for players';
      case OnlineGameMode.privateGame:
        return 'Invite friends with a code';
      case OnlineGameMode.ranked:
        return 'Compete for MMR and climb the ladder';
      case OnlineGameMode.rankedHardcore:
        return 'Stricter rules, 30s turns — separate hardcore MMR';
    }
  }

  String get emoji {
    switch (this) {
      case OnlineGameMode.selectTableCasual:
        return '🪑';
      case OnlineGameMode.quickMatchCasual:
        return '⚡';
      case OnlineGameMode.privateGame:
        return '🔒';
      case OnlineGameMode.ranked:
        return '🏆';
      case OnlineGameMode.rankedHardcore:
        return '☠️';
    }
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class OnlineSessionState {
  const OnlineSessionState({
    this.mode,
    this.queueJoinStyle,
    this.playerCount,
  });

  final OnlineGameMode? mode;

  /// How to join quickplay for [ranked] / [rankedHardcore]; also set for casual
  /// modes from [OnlineSessionNotifier.setMode]. Ignored when [mode] is private.
  final OnlineQueueJoinStyle? queueJoinStyle;

  final int? playerCount;

  /// True when this session should quickplay as "join any non-full waiting queue"
  /// (no [playerCount] in the WS message).
  bool get isJoinWaitingQueue {
    if (mode == OnlineGameMode.privateGame) return false;
    if (mode == OnlineGameMode.quickMatchCasual) return true;
    return queueJoinStyle == OnlineQueueJoinStyle.joinWaitingQueue;
  }

  OnlineSessionState copyWith({
    OnlineGameMode? mode,
    OnlineQueueJoinStyle? queueJoinStyle,
    int? playerCount,
    bool clearMode = false,
    bool clearPlayerCount = false,
    bool clearQueueJoinStyle = false,
  }) {
    return OnlineSessionState(
      mode: clearMode ? null : (mode ?? this.mode),
      queueJoinStyle: clearQueueJoinStyle
          ? null
          : (queueJoinStyle ?? this.queueJoinStyle),
      playerCount:
          clearPlayerCount ? null : (playerCount ?? this.playerCount),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class OnlineSessionNotifier extends StateNotifier<OnlineSessionState> {
  OnlineSessionNotifier() : super(const OnlineSessionState());

  void setMode(OnlineGameMode mode) {
    if (mode == OnlineGameMode.selectTableCasual) {
      state = state.copyWith(
        mode: mode,
        queueJoinStyle: OnlineQueueJoinStyle.selectTable,
        clearPlayerCount: true,
      );
    } else if (mode == OnlineGameMode.quickMatchCasual) {
      state = state.copyWith(
        mode: mode,
        queueJoinStyle: OnlineQueueJoinStyle.joinWaitingQueue,
        clearPlayerCount: true,
      );
    } else {
      state = state.copyWith(
        mode: mode,
        clearQueueJoinStyle: true,
        clearPlayerCount: true,
      );
    }
  }

  void setQueueJoinStyle(OnlineQueueJoinStyle style) {
    state = state.copyWith(
      queueJoinStyle: style,
      clearPlayerCount: true,
    );
  }

  void setPlayerCount(int count) {
    state = state.copyWith(playerCount: count);
  }

  void reset() {
    state = const OnlineSessionState();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final onlineSessionProvider =
    StateNotifierProvider<OnlineSessionNotifier, OnlineSessionState>(
  (_) => OnlineSessionNotifier(),
);
