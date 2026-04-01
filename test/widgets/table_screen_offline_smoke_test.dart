import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/offline_game_state.dart';
import 'package:last_cards/core/models/player_model.dart';
import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/discard_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';

class _MockAudioService extends AudioService {}

void main() {
  CardModel c(String id, Rank rank, Suit suit) =>
      CardModel(id: id, rank: rank, suit: suit);

  testWidgets(
    'TableScreen offline with debugSkipDealAnimation shows table chrome immediately',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Seeded state with short names avoids MarqueeName overflow from random
      // AI display names in tests (Row overflow is treated as a test failure).
      final localHand = [
        c('L0', Rank.four, Suit.hearts),
        c('L1', Rank.five, Suit.diamonds),
        c('L2', Rank.six, Suit.clubs),
        c('L3', Rank.seven, Suit.spades),
        c('L4', Rank.eight, Suit.hearts),
        c('L5', Rank.nine, Suit.diamonds),
        c('L6', Rank.ten, Suit.clubs),
      ];
      final p2Hand = [
        c('P0', Rank.two, Suit.hearts),
        c('P1', Rank.three, Suit.diamonds),
        c('P2', Rank.four, Suit.clubs),
        c('P3', Rank.king, Suit.spades),
        c('P4', Rank.queen, Suit.hearts),
        c('P5', Rank.jack, Suit.diamonds),
        c('P6', Rank.ace, Suit.clubs),
      ];
      final drawPile = [
        c('D0', Rank.two, Suit.hearts),
        c('D1', Rank.three, Suit.diamonds),
        c('D2', Rank.four, Suit.clubs),
      ];

      final playedThisTurn = c('played', Rank.six, Suit.spades);
      final initialState = GameState(
        sessionId: 'offline-smoke',
        phase: GamePhase.playing,
        players: [
          PlayerModel(
            id: OfflineGameState.localId,
            displayName: 'You',
            tablePosition: TablePosition.bottom,
            hand: localHand,
            cardCount: 7,
          ),
          PlayerModel(
            id: 'player-2',
            displayName: 'A',
            tablePosition: TablePosition.top,
            hand: p2Hand,
            cardCount: 7,
          ),
        ],
        currentPlayerId: OfflineGameState.localId,
        direction: PlayDirection.clockwise,
        discardTopCard: c('disc', Rank.six, Suit.spades),
        drawPileCount: drawPile.length,
        actionsThisTurn: 1,
        cardsPlayedThisTurn: 1,
        lastPlayedThisTurn: playedThisTurn,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioServiceProvider.overrideWith((ref) => _MockAudioService()),
          ],
          child: MaterialApp(
            home: TableScreen(
              totalPlayers: 2,
              debugInitialOfflineState: initialState,
              debugInitialDrawPile: drawPile,
              debugSkipDealAnimation: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final statusFinder = find.byKey(const ValueKey('dealer-status'));
      expect(statusFinder, findsOneWidget);
      expect(
        (tester.widget(statusFinder) as Text).data,
        'DEALER',
        reason: 'Deal animation is skipped; status should not stay on DEALING...',
      );
      expect(find.byType(DrawPileWidget), findsOneWidget);
      expect(find.byType(DiscardPileWidget), findsOneWidget);
      expect(find.text('End Turn'), findsOneWidget);
    },
  );
}
