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

  String get displayName => switch (this) {
        TournamentType.vsAi => 'Single Player',
        TournamentType.localMultiplayer => 'Online',
      };

  String get description => switch (this) {
        TournamentType.vsAi =>
          'Compete against AI opponents across multiple rounds',
        TournamentType.localMultiplayer =>
          'Play tournament against real players online',
      };

  String get emoji => switch (this) {
        TournamentType.vsAi => '👤',
        TournamentType.localMultiplayer => '🌐',
      };
}

/// Sub-mode chosen after picking Single Player or Online.
/// Determines whether the session runs a standard knockout tournament
/// or a Bust-mode elimination game.
enum GameSubMode {
  knockout,
  bust;

  String get displayName => switch (this) {
        GameSubMode.knockout => 'Knockout Tournament',
        GameSubMode.bust => 'Bust Mode',
      };

  String get description => switch (this) {
        GameSubMode.knockout =>
          'Eliminated player leaves each round — last one wins',
        GameSubMode.bust =>
          'Last player holding cards loses — up to 10 players',
      };

  String get emoji => switch (this) {
        GameSubMode.knockout => '🏆',
        GameSubMode.bust => '💥',
      };
}

class TournamentSessionState {
  const TournamentSessionState({
    this.type,
    this.subMode,
    this.difficulty,
    this.playerNames = const [],
    this.playerCount,
    this.format,
  });

  final TournamentType? type;

  /// Knockout or Bust — chosen in [TournamentSubModeSheet] after picking type.
  final GameSubMode? subMode;

  final AiDifficulty? difficulty;
  final List<String> playerNames;
  final int? playerCount;
  final TournamentFormat? format;

  TournamentSessionState copyWith({
    TournamentType? type,
    GameSubMode? subMode,
    AiDifficulty? difficulty,
    List<String>? playerNames,
    int? playerCount,
    TournamentFormat? format,
    bool clearDifficulty = false,
    bool clearSubMode = false,
  }) {
    return TournamentSessionState(
      type: type ?? this.type,
      subMode: clearSubMode ? null : (subMode ?? this.subMode),
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
      state = state.copyWith(type: type, clearDifficulty: true, clearSubMode: true);
    }
  }

  void setSubMode(GameSubMode subMode) {
    state = state.copyWith(subMode: subMode);
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
