import 'package:last_cards/core/models/offline_game_state.dart';

/// Maps [TableScreen] / [OfflineGameState.buildWithDeck] seat IDs to the IDs
/// used by [TournamentEngine] for the same seats.
///
/// Offline games use `player-local`, `player-2` … `player-7`. The offline
/// tournament engine uses `player-local` plus `tournament-ai-2` … (stable
/// bracket IDs). Without this mapping, [TournamentEngine.recordPlayerFinished]
/// ignores AI finishes (`player-2` ∉ `_activePlayerIds`), so rounds never
/// complete in the engine and the coordinator cannot show Elimination / next round.
String resolveTournamentTableIdToEnginePlayerId({
  required String reportedId,
  required List<String> activePlayerIds,
}) {
  if (activePlayerIds.contains(reportedId)) {
    return reportedId;
  }

  const localId = OfflineGameState.localId;
  if (reportedId == localId) {
    return reportedId;
  }

  const prefix = 'player-';
  if (reportedId.startsWith(prefix)) {
    final n = int.tryParse(reportedId.substring(prefix.length));
    if (n != null && n >= 2) {
      final opponents =
          activePlayerIds.where((id) => id != localId).toList(growable: false);
      final idx = n - 2;
      if (idx >= 0 && idx < opponents.length) {
        return opponents[idx];
      }
    }
  }

  return reportedId;
}
