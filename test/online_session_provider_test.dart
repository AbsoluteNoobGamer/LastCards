import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/features/online/providers/online_session_provider.dart';

void main() {
  group('OnlineSessionNotifier.preparePublicRematch', () {
    test('switches Quick match to select-table with finished size', () {
      final notifier = OnlineSessionNotifier();
      notifier.setMode(OnlineGameMode.quickMatchCasual);
      // Mimic a completed Quick match that was assigned a 4-player table.
      notifier.setPlayerCount(4);

      expect(notifier.state.isJoinWaitingQueue, isTrue);

      notifier.preparePublicRematch(playerCount: 4);

      expect(notifier.state.queueJoinStyle, OnlineQueueJoinStyle.selectTable);
      expect(notifier.state.isJoinWaitingQueue, isFalse);
      expect(notifier.state.playerCount, 4);
      expect(notifier.state.mode, OnlineGameMode.quickMatchCasual);
    });

    test('keeps ranked mode and forces select-table for rematch', () {
      final notifier = OnlineSessionNotifier();
      notifier.setMode(OnlineGameMode.ranked);
      notifier.setPlayerCount(3);

      notifier.preparePublicRematch(playerCount: 3);

      expect(notifier.state.mode, OnlineGameMode.ranked);
      expect(notifier.state.queueJoinStyle, OnlineQueueJoinStyle.selectTable);
      expect(notifier.state.playerCount, 3);
    });

    test('does not alter private sessions', () {
      final notifier = OnlineSessionNotifier();
      notifier.setMode(OnlineGameMode.privateGame);

      notifier.preparePublicRematch(playerCount: 4);

      expect(notifier.state.mode, OnlineGameMode.privateGame);
      expect(notifier.state.queueJoinStyle, isNull);
      expect(notifier.state.playerCount, isNull);
    });
  });
}
