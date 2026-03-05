import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── AI Difficulty Enum ────────────────────────────────────────────────────────

enum AiDifficulty {
  easy,
  medium,
  hard;

  String get displayName {
    switch (this) {
      case AiDifficulty.easy:
        return 'Easy';
      case AiDifficulty.medium:
        return 'Medium';
      case AiDifficulty.hard:
        return 'Hard';
    }
  }

  String get description {
    switch (this) {
      case AiDifficulty.easy:
        return 'Relaxed pace, AI plays it safe';
      case AiDifficulty.medium:
        return 'Balanced challenge, AI plays smart';
      case AiDifficulty.hard:
        return 'No mercy, AI plays to win';
    }
  }

  String get emoji {
    switch (this) {
      case AiDifficulty.easy:
        return '🟢';
      case AiDifficulty.medium:
        return '🟠';
      case AiDifficulty.hard:
        return '🔴';
    }
  }

  /// Multiplier applied to the AI base think-time delay.
  /// Easy = slower (friendlier), Hard = faster (aggressive).
  double get delayMultiplier {
    switch (this) {
      case AiDifficulty.easy:
        return 1.8;
      case AiDifficulty.medium:
        return 1.0;
      case AiDifficulty.hard:
        return 0.55;
    }
  }
}

// ── State ─────────────────────────────────────────────────────────────────────

class SinglePlayerSessionState {
  const SinglePlayerSessionState({
    this.difficulty,
    this.playerCount,
  });

  final AiDifficulty? difficulty;
  final int? playerCount;

  SinglePlayerSessionState copyWith({
    AiDifficulty? difficulty,
    int? playerCount,
    bool clearDifficulty = false,
    bool clearPlayerCount = false,
  }) {
    return SinglePlayerSessionState(
      difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
      playerCount:
          clearPlayerCount ? null : (playerCount ?? this.playerCount),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SinglePlayerSessionNotifier
    extends StateNotifier<SinglePlayerSessionState> {
  SinglePlayerSessionNotifier() : super(const SinglePlayerSessionState());

  void setDifficulty(AiDifficulty difficulty) {
    state = state.copyWith(difficulty: difficulty, clearPlayerCount: true);
  }

  void setPlayerCount(int count) {
    state = state.copyWith(playerCount: count);
  }

  void reset() {
    state = const SinglePlayerSessionState();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final singlePlayerSessionProvider = StateNotifierProvider<
    SinglePlayerSessionNotifier, SinglePlayerSessionState>(
  (_) => SinglePlayerSessionNotifier(),
);
