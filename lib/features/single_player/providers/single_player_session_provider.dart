import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/ai_player_config.dart';

// AiDifficulty is defined in ai_player_config.dart and re-exported for callers
// that import this provider file.
export '../../../core/models/ai_player_config.dart' show AiDifficulty;

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
