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
      // Top-level card now opens a Select table / Quick match submenu (like
      // Ranked and Ranked Hardcore), so it reads as the whole casual tier.
      case OnlineGameMode.quickMatchCasual:
        return 'Casual';
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
        return 'Pick a table size, then wait for players to fill it';
      case OnlineGameMode.quickMatchCasual:
        return 'No MMR · 60s turns · standard rules — pick a table or jump in';
      case OnlineGameMode.privateGame:
        return 'Invite friends with a code — host can choose casual or hardcore';
      case OnlineGameMode.ranked:
        return 'Ranked MMR · 60s turns · standard rules — can finish on Ace or Joker';
      case OnlineGameMode.rankedHardcore:
        return 'Separate Hardcore MMR · 30s turns · can\'t finish on Ace or Joker';
    }
  }

  String get emoji {
    switch (this) {
      case OnlineGameMode.selectTableCasual:
        return '🪑';
      case OnlineGameMode.quickMatchCasual:
        return '🎮';
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
  /// (no [playerCount] in the WS message). Every tier (casual/ranked/hardcore)
  /// now routes through the same Select table / Quick match submenu, so this
  /// must always defer to the explicit [queueJoinStyle] choice rather than
  /// assuming a tier — [OnlineSessionNotifier.setMode] seeds a sensible
  /// default and the submenu overrides it once the player actually picks.
  bool get isJoinWaitingQueue {
    if (mode == OnlineGameMode.privateGame) return false;
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
    } else if (mode == OnlineGameMode.quickMatchCasual ||
        mode == OnlineGameMode.ranked ||
        mode == OnlineGameMode.rankedHardcore) {
      // Seed a default of "join waiting queue" the instant a top-level tier
      // is picked; QueueJoinStyleSheet immediately follows and overrides
      // this via setQueueJoinStyle once the player actually chooses.
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

  /// Rematch after a public match: always queue by concrete table size.
  ///
  /// Quick match (`joinWaitingQueue`) only joins tables that are already
  /// waiting — after a game ends those are usually gone, so rematch would
  /// immediately get `no_waiting_tables` and bounce to the start screen.
  /// Switching to select-table with the finished match's size opens (or
  /// joins) a real queue instead.
  void preparePublicRematch({required int playerCount}) {
    if (state.mode == null || state.mode == OnlineGameMode.privateGame) {
      return;
    }
    state = state.copyWith(
      queueJoinStyle: OnlineQueueJoinStyle.selectTable,
      playerCount: playerCount,
    );
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
