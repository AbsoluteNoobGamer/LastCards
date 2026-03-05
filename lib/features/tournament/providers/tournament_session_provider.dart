import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../single_player/providers/single_player_session_provider.dart';

enum TournamentType {
  vsAi,
  localMultiplayer;

  String get displayName {
    switch (this) {
      case TournamentType.vsAi:
        return 'vs AI';
      case TournamentType.localMultiplayer:
        return 'Local Multiplayer';
    }
  }

  String get description {
    switch (this) {
      case TournamentType.vsAi:
        return 'Compete against AI opponents across multiple rounds';
      case TournamentType.localMultiplayer:
        return 'Pass and play tournament with friends';
    }
  }

  String get emoji {
    switch (this) {
      case TournamentType.vsAi:
        return '🤖';
      case TournamentType.localMultiplayer:
        return '👥';
    }
  }
}

class TournamentSessionState {
  const TournamentSessionState({
    this.type,
    this.difficulty,
    this.playerNames = const ['Noob 1', 'Noob 2', 'Noob 3', 'Noob 4'],
    this.playerCount,
  });

  final TournamentType? type;
  final AiDifficulty? difficulty;
  final List<String> playerNames;
  final int? playerCount;

  TournamentSessionState copyWith({
    TournamentType? type,
    AiDifficulty? difficulty,
    List<String>? playerNames,
    int? playerCount,
    bool clearDifficulty = false,
  }) {
    return TournamentSessionState(
      type: type ?? this.type,
      difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
      playerNames: playerNames ?? this.playerNames,
      playerCount: playerCount ?? this.playerCount,
    );
  }
}

class TournamentSessionNotifier extends StateNotifier<TournamentSessionState> {
  TournamentSessionNotifier() : super(const TournamentSessionState());

  void setType(TournamentType type) {
    if (state.type != type) {
      state = state.copyWith(type: type, clearDifficulty: true);
    }
  }

  void setDifficulty(AiDifficulty difficulty) {
    state = state.copyWith(difficulty: difficulty);
  }

  void setPlayerNames(List<String> names) {
    state = state.copyWith(playerNames: names);
  }

  void setPlayerCount(int count) {
    state = state.copyWith(playerCount: count);
  }

  void reset() {
    state = const TournamentSessionState();
  }
}

final tournamentSessionProvider = StateNotifierProvider<
    TournamentSessionNotifier, TournamentSessionState>((ref) {
  return TournamentSessionNotifier();
});
