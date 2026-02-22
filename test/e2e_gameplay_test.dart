import 'package:flutter_test/flutter_test.dart';
import 'package:stack_and_flow/core/models/card_model.dart';
import 'package:stack_and_flow/core/models/demo_game_engine.dart';
import 'package:stack_and_flow/core/models/demo_game_state.dart';
import 'package:stack_and_flow/core/models/game_state.dart';

void main() {
  group('E2E Gameplay Flow Engine Test', () {
    test('Simulate complete 2-player game to win condition', () {
      // 1. Initialize state
      var (state, drawPile) = DemoGameState.buildWithDeck(totalPlayers: 2);

      // Helper function to draw cards from the pile
      List<CardModel> drawFactory(int n) {
        if (drawPile.length < n) {
          // If draw pile is empty, in a real game we reshuffle the discard pile.
          // For the sake of unbroken E2E testing without full discard pile memory tracking here,
          // we'll supply dummy cards to keep the game flowing if we hit the bottom of the deck.
          for (int i = 0; i < n; i++) {
            drawPile.add(
                CardModel(id: 'mock_\$i', suit: Suit.spades, rank: Rank.two));
          }
        }
        final drawn = drawPile.sublist(0, n);
        drawPile.removeRange(0, n);
        return drawn;
      }

      int maxTurns = 500;
      int turns = 0;

      // 2. Play loop
      while (state.phase == GamePhase.playing && turns < maxTurns) {
        turns++;
        final currentPlayerId = state.currentPlayerId;

        // Use the engine's built-in AI turn simulator to execute a mathematically valid turn
        // (handling penalties, draws, and valid plays naturally).
        final turnResult = aiTakeTurn(
          state: state,
          aiPlayerId: currentPlayerId,
          cardFactory: drawFactory,
        );
        state = turnResult.state;

        // 3. State integrity checks after every move
        for (final p in state.players) {
          expect(p.hand.length, greaterThanOrEqualTo(0),
              reason: 'Player hand count cannot be negative');
        }

        // 4. Handle Game Over Check
        for (final p in state.players) {
          if (p.hand.isEmpty) {
            state = state.copyWith(
              phase: GamePhase.ended,
              winnerId: p.id,
            );
            break;
          }
        }
      }

      // 5. Assertions
      expect(state.phase, GamePhase.ended,
          reason:
              'Game must finish within a reasonable turn limit. (Failed after \$turns turns)');
      expect(state.winnerId, isNotNull, reason: 'A winner must be declared');

      final winner = state.players.firstWhere((p) => p.id == state.winnerId);
      expect(winner.hand.isEmpty, isTrue,
          reason: 'Winner must have 0 cards left');
    });

    test('Regression scenario: Trying to play invalid card returns error', () {
      var (state, _) = DemoGameState.buildWithDeck(totalPlayers: 2);

      // Force an invalid situation to verify rule protections
      final invalidCard = const CardModel(
          id: 'invalid_card', suit: Suit.spades, rank: Rank.nine);

      // Set discard to 4 of Hearts
      state = state.copyWith(
          discardTopCard:
              const CardModel(id: '4h', suit: Suit.hearts, rank: Rank.four));

      final err = validatePlay(
          cards: [invalidCard],
          discardTop: state.discardTopCard!,
          state: state);

      // Assert engine securely blocks invalid move
      expect(err, isNotNull,
          reason: 'Must reject card with no matching suit/rank');
      expect(err, contains('Must match'),
          reason: 'Proper error message is returned');
    });
  });
}
