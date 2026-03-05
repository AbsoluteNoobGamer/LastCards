import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Game Mode Enum ────────────────────────────────────────────────────────────

enum OnlineGameMode {
  quickMatch,
  privateGame,
  tournament;

  String get displayName {
    switch (this) {
      case OnlineGameMode.quickMatch:
        return 'Quick Match';
      case OnlineGameMode.privateGame:
        return 'Private Game';
      case OnlineGameMode.tournament:
        return 'Knockouts';
    }
  }

  String get description {
    switch (this) {
      case OnlineGameMode.quickMatch:
        return 'Jump straight into a game';
      case OnlineGameMode.privateGame:
        return 'Invite friends with a code';
      case OnlineGameMode.tournament:
        return 'Elimination format, last one standing wins';
    }
  }

  String get emoji {
    switch (this) {
      case OnlineGameMode.quickMatch:
        return '⚡';
      case OnlineGameMode.privateGame:
        return '🔒';
      case OnlineGameMode.tournament:
        return '💥';
    }
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class OnlineSessionState {
  const OnlineSessionState({
    this.mode,
    this.playerCount,
  });

  final OnlineGameMode? mode;
  final int? playerCount;

  OnlineSessionState copyWith({
    OnlineGameMode? mode,
    int? playerCount,
    bool clearMode = false,
    bool clearPlayerCount = false,
  }) {
    return OnlineSessionState(
      mode: clearMode ? null : (mode ?? this.mode),
      playerCount:
          clearPlayerCount ? null : (playerCount ?? this.playerCount),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class OnlineSessionNotifier extends StateNotifier<OnlineSessionState> {
  OnlineSessionNotifier() : super(const OnlineSessionState());

  void setMode(OnlineGameMode mode) {
    state = state.copyWith(mode: mode, clearPlayerCount: true);
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
