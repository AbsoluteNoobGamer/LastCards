import '../models/card_model.dart';
import '../models/game_state_model.dart';

/// Display names of players skipped by the current [activeSkipCount] after an
/// Eight play — mirrors [TableScreen._skippedPlayersForCurrentTurn] for server
/// and online move logs.
List<String> skippedPlayerDisplayNamesForSkipState(GameState state) {
  final skipCount = state.activeSkipCount;
  if (skipCount <= 0) return const <String>[];
  if (state.lastPlayedThisTurn?.effectiveRank != Rank.eight) {
    return const <String>[];
  }

  final players = state.players;
  final currentIndex =
      players.indexWhere((p) => p.id == state.currentPlayerId);
  if (currentIndex < 0) return const <String>[];

  final step = state.direction == PlayDirection.clockwise ? 1 : -1;
  var cursor = currentIndex;
  final skipped = <String>[];
  for (var i = 0; i < skipCount; i++) {
    cursor = (cursor + step) % players.length;
    if (cursor < 0) cursor += players.length;
    skipped.add(players[cursor].displayName);
  }
  return skipped;
}

/// Player IDs skipped by the current [activeSkipCount] after an Eight play.
///
/// Same seat walk as [skippedPlayerDisplayNamesForSkipState], but returns IDs
/// for UI overlays (dim/pause on that player's zone).
List<String> skippedPlayerIdsForSkipState(GameState state) {
  final skipCount = state.activeSkipCount;
  if (skipCount <= 0) return const <String>[];
  if (state.lastPlayedThisTurn?.effectiveRank != Rank.eight) {
    return const <String>[];
  }

  final players = state.players;
  final currentIndex =
      players.indexWhere((p) => p.id == state.currentPlayerId);
  if (currentIndex < 0) return const <String>[];

  final step = state.direction == PlayDirection.clockwise ? 1 : -1;
  var cursor = currentIndex;
  final skipped = <String>[];
  for (var i = 0; i < skipCount; i++) {
    cursor = (cursor + step) % players.length;
    if (cursor < 0) cursor += players.length;
    skipped.add(players[cursor].id);
  }
  return skipped;
}
