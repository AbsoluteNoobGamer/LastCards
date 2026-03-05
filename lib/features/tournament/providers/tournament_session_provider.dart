import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../single_player/providers/single_player_session_provider.dart';

enum TournamentFormat {
  standard,
  knockouts;

  String get displayName {
    switch (this) {
      case TournamentFormat.standard:
        return 'Standard';
      case TournamentFormat.knockouts:
        return 'Knockouts';
    }
  }

  String get description {
    switch (this) {
      case TournamentFormat.standard:
        return 'First to empty their hand wins the round';
      case TournamentFormat.knockouts:
        return 'Elimination format, last one standing is knocked out each round';
    }
  }

  String get emoji {
    switch (this) {
      case TournamentFormat.standard:
        return '🃏';
      case TournamentFormat.knockouts:
        return '💥';
    }
  }
}

enum TournamentType {
  vsAi,
  localMultiplayer;

  String get displayName {
    switch (this) {
      case TournamentType.vsAi:
        return 'Single Player';
      case TournamentType.localMultiplayer:
        return 'Online';
    }
  }

  String get description {
    switch (this) {
      case TournamentType.vsAi:
        return 'Compete against AI opponents across multiple rounds';
      case TournamentType.localMultiplayer:
        return 'Play tournament against real players online';
    }
  }

  String get emoji {
    switch (this) {
      case TournamentType.vsAi:
        return '👤';
      case TournamentType.localMultiplayer:
        return '🌐';
    }
  }
}

class TournamentSessionState {
  const TournamentSessionState({
    this.type,
    this.difficulty,
    this.playerNames = const ['Noob 1', 'Noob 2', 'Noob 3', 'Noob 4'],
    this.playerCount,
    this.format,
  });

  final TournamentType? type;
  final AiDifficulty? difficulty;
  final List<String> playerNames;
  final int? playerCount;
  final TournamentFormat? format;

  TournamentSessionState copyWith({
    TournamentType? type,
    AiDifficulty? difficulty,
    List<String>? playerNames,
    int? playerCount,
    TournamentFormat? format,
    bool clearDifficulty = false,
  }) {
    return TournamentSessionState(
      type: type ?? this.type,
      difficulty: clearDifficulty ? null : (difficulty ?? this.difficulty),
      playerNames: playerNames ?? this.playerNames,
      playerCount: playerCount ?? this.playerCount,
      format: format ?? this.format,
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

  void setFormat(TournamentFormat format) {
    state = state.copyWith(format: format);
  }

  void reset() {
    state = const TournamentSessionState();
  }
}

final tournamentSessionProvider = StateNotifierProvider<
    TournamentSessionNotifier, TournamentSessionState>((ref) {
  return TournamentSessionNotifier();
});
