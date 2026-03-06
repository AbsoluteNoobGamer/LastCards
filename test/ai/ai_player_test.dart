import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/card_model.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/core/models/offline_game_engine.dart';
import 'package:last_cards/core/models/player_model.dart';

CardModel c(Rank r, Suit s, String id) => CardModel(id: id, rank: r, suit: s);

GameState buildState({
  required CardModel discardTop,
  required List<CardModel> aiHand,
  List<CardModel> p1Hand = const [],
  int activePenalty = 0,
  PlayDirection direction = PlayDirection.clockwise,
  int p1Count = 5,
}) {
  return GameState(
    sessionId: 'ai-test',
    phase: GamePhase.playing,
    players: [
      PlayerModel(
        id: 'p1',
        displayName: 'P1',
        tablePosition: TablePosition.bottom,
        hand: p1Hand,
        cardCount: p1Hand.isEmpty ? p1Count : p1Hand.length,
      ),
      PlayerModel(
        id: 'ai',
        displayName: 'AI',
        tablePosition: TablePosition.top,
        hand: aiHand,
        cardCount: aiHand.length,
      ),
    ],
    currentPlayerId: 'ai',
    direction: direction,
    discardTopCard: discardTop,
    drawPileCount: 30,
    activePenaltyCount: activePenalty,
    lastUpdatedAt: 0,
  );
}

void main() {
  group('AI decision-making regressions', () {
    test('Ace suit selection chooses the suit with most cards in AI hand', () {
      final state = buildState(
        discardTop: c(Rank.nine, Suit.clubs, 'd1'),
        aiHand: [
          c(Rank.ace, Suit.spades, 'a1'),
          c(Rank.three, Suit.hearts, 'h3'),
          c(Rank.six, Suit.hearts, 'h6'),
          c(Rank.four, Suit.diamonds, 'd4'),
        ],
      );

      final result = aiTakeTurn(
        state: state,
        aiPlayerId: 'ai',
        cardFactory: (_) => [],
      );

      expect(result.playedCards.first.effectiveRank, Rank.ace);
      expect(result.state.suitLock, Suit.hearts);
    });

    test('Ace never selects Spades by default when better options exist', () {
      final state = buildState(
        discardTop: c(Rank.nine, Suit.clubs, 'd2'),
        aiHand: [
          c(Rank.ace, Suit.spades, 'a2'),
          c(Rank.two, Suit.diamonds, 'd2a'),
          c(Rank.five, Suit.diamonds, 'd5'),
          c(Rank.seven, Suit.hearts, 'h7'),
        ],
      );

      final result = aiTakeTurn(
        state: state,
        aiPlayerId: 'ai',
        cardFactory: (_) => [],
      );

      expect(result.playedCards.first.effectiveRank, Rank.ace);
      expect(result.state.suitLock, isNot(Suit.spades));
      expect(result.state.suitLock, Suit.diamonds);
    });

    test('Joker never declares Black Jack rank unless hand is empty after it', () {
      final state = buildState(
        discardTop: c(Rank.jack, Suit.clubs, 'd3'),
        aiHand: [
          c(Rank.joker, Suit.spades, 'jkr1'),
          c(Rank.five, Suit.hearts, 'h5'),
        ],
        activePenalty: 5,
      );

      final result = aiTakeTurn(
        state: state,
        aiPlayerId: 'ai',
        cardFactory: (_) => [],
      );

      final playedJoker = result.playedCards.first;
      final isDeclaredBlackJack = playedJoker.jokerDeclaredRank == Rank.jack &&
          (playedJoker.jokerDeclaredSuit == Suit.spades ||
              playedJoker.jokerDeclaredSuit == Suit.clubs);
      expect(playedJoker.isJoker, isTrue);
      expect(isDeclaredBlackJack, isFalse);
    });

    test('Joker declares suit AI holds most cards in', () {
      final state = buildState(
        discardTop: c(Rank.ten, Suit.spades, 'd4'),
        aiHand: [
          c(Rank.joker, Suit.hearts, 'jkr2'),
          c(Rank.two, Suit.hearts, 'h2'),
          c(Rank.three, Suit.hearts, 'h3b'),
          c(Rank.four, Suit.hearts, 'h4'),
        ],
      );

      final result = aiTakeTurn(
        state: state,
        aiPlayerId: 'ai',
        cardFactory: (_) => [],
      );

      final played = result.playedCards.first;
      expect(played.isJoker, isTrue);
      expect(played.jokerDeclaredSuit, Suit.hearts);
    });

    test('AI plays its last card immediately when it is valid', () {
      final last = c(Rank.five, Suit.hearts, 'lh5');
      final state = buildState(
        discardTop: c(Rank.nine, Suit.hearts, 'd5'),
        aiHand: [last],
      );

      final result = aiTakeTurn(
        state: state,
        aiPlayerId: 'ai',
        cardFactory: (_) => [],
      );

      final aiAfter = result.state.players.firstWhere((p) => p.id == 'ai');
      expect(result.playedCards.length, 1);
      expect(result.playedCards.first.id, last.id);
      expect(aiAfter.hand, isEmpty);
    });

    test('AI plays Black Jack only when many cards or a draw chain is active', () {
      final lowHandState = buildState(
        discardTop: c(Rank.jack, Suit.hearts, 'd6'),
        aiHand: [
          c(Rank.jack, Suit.spades, 'bj_low'),
          c(Rank.jack, Suit.diamonds, 'rj_low'),
          c(Rank.six, Suit.hearts, 'h6_low'),
        ],
      );

      final lowHandResult = aiTakeTurn(
        state: lowHandState,
        aiPlayerId: 'ai',
        cardFactory: (_) => [],
      );
      expect(lowHandResult.playedCards.first.id, isNot('bj_low'));

      final chainState = buildState(
        discardTop: c(Rank.two, Suit.clubs, 'd7'),
        aiHand: [
          c(Rank.jack, Suit.spades, 'bj_chain'),
          c(Rank.five, Suit.hearts, 'h5_chain'),
          c(Rank.seven, Suit.diamonds, 'd7_chain'),
        ],
        activePenalty: 2,
      );

      final chainResult = aiTakeTurn(
        state: chainState,
        aiPlayerId: 'ai',
        cardFactory: (_) => [],
      );
      expect(chainResult.playedCards.first.id, 'bj_chain');
    });
  });
}
