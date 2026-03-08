import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../single_player/providers/single_player_session_provider.dart';

enum TournamentFormat {
  knockout,
  roundRobin,
  bestOfThree;

  String get displayName {
    switch (this) {
      case TournamentFormat.knockout:
        return 'Knockout';
      case TournamentFormat.roundRobin:
        return 'Round Robin';
      case TournamentFormat.bestOfThree:
        return 'Best of 3';
    }
  }

  String get description {
    switch (this) {
      case TournamentFormat.knockout:
        return 'Eliminated player leaves each round';
      case TournamentFormat.roundRobin:
        return 'Everyone plays everyone, most wins advances';
      case TournamentFormat.bestOfThree:
        return 'First to win 2 rounds wins the tournament';
    }
  }

  String get emoji {
    switch (this) {
      case TournamentFormat.knockout:
        return '🏆';
      case TournamentFormat.roundRobin:
        return '🔄';
      case TournamentFormat.bestOfThree:
        return '⚔️';
    }
  }

  bool get isComingSoon {
    switch (this) {
      case TournamentFormat.knockout:
        return false;
      case TournamentFormat.roundRobin:
        return true;
      case TournamentFormat.bestOfThree:
        return true;
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
    this.playerNames = const [],
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
