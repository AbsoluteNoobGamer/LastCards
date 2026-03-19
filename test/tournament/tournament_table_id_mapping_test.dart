import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/tournament/tournament_table_id_mapping.dart';

void main() {
  group('resolveTournamentTableIdToEnginePlayerId', () {
    test('passes through ids already in activePlayerIds', () {
      const active = ['player-local', 'tournament-ai-2', 'tournament-ai-3'];
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'tournament-ai-2',
          activePlayerIds: active,
        ),
        'tournament-ai-2',
      );
    });

    test('maps player-2.. to engine opponent order (same as name map)', () {
      const active = [
        OfflineGameState.localId,
        'tournament-ai-2',
        'tournament-ai-3',
        'tournament-ai-4',
      ];
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: OfflineGameState.localId,
          activePlayerIds: active,
        ),
        OfflineGameState.localId,
      );
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'player-2',
          activePlayerIds: active,
        ),
        'tournament-ai-2',
      );
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'player-3',
          activePlayerIds: active,
        ),
        'tournament-ai-3',
      );
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'player-4',
          activePlayerIds: active,
        ),
        'tournament-ai-4',
      );
    });

    test('3-player bracket: player-3 maps to last AI', () {
      const active = [
        OfflineGameState.localId,
        'tournament-ai-2',
        'tournament-ai-3',
      ];
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'player-3',
          activePlayerIds: active,
        ),
        'tournament-ai-3',
      );
    });

    test('2-player final: player-2 maps to sole remaining opponent (any id)', () {
      const active = [
        OfflineGameState.localId,
        'tournament-ai-3',
      ];
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'player-2',
          activePlayerIds: active,
        ),
        'tournament-ai-3',
      );
    });

    test(
        'regression: shrunk active list cannot map player-3 (coordinator must snapshot)',
        () {
      const shrunkWrong = [
        OfflineGameState.localId,
        'tournament-ai-2',
      ];
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'player-3',
          activePlayerIds: shrunkWrong,
        ),
        'player-3',
      );
      const fullRound = [
        OfflineGameState.localId,
        'tournament-ai-2',
        'tournament-ai-3',
      ];
      expect(
        resolveTournamentTableIdToEnginePlayerId(
          reportedId: 'player-3',
          activePlayerIds: fullRound,
        ),
        'tournament-ai-3',
      );
    });
  });
}
