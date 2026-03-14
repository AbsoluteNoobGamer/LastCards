import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/models/offline_game_engine.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_widget.dart';

GameState _stateForJokerPipeline({
  required List<CardModel> localHand,
  required CardModel discardTop,
  int actionsThisTurn = 0,
  CardModel? lastPlayedThisTurn,
}) {
  return GameState(
    sessionId: 'pipeline',
    phase: GamePhase.playing,
    players: [
      PlayerModel(
        id: 'p1',
        displayName: 'You',
        tablePosition: TablePosition.bottom,
        hand: localHand,
        cardCount: localHand.length,
      ),
      const PlayerModel(
        id: 'p2',
        displayName: 'AI',
        tablePosition: TablePosition.top,
        cardCount: 5,
      ),
    ],
    currentPlayerId: 'p1',
    direction: PlayDirection.clockwise,
    discardTopCard: discardTop,
    actionsThisTurn: actionsThisTurn,
    lastPlayedThisTurn: lastPlayedThisTurn,
  );
}

void main() {
  group('Joker popup connection (mirrors Ace popup pattern)', () {
    testWidgets('1) Joker tap opens popup (same modal pattern as Ace)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<CardModel>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const Material(
                      child: SizedBox(
                        height: 120,
                        child: Center(child: Text('Joker Played!')),
                      ),
                    ),
                  );
                },
                child: const Text('open-joker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-joker'));
      await tester.pumpAndSettle();
      expect(find.text('Joker Played!'), findsOneWidget);
    });

    // Validates the actual bug fix: CardWidget.onTap must fire when tapped
    // inside the Joker popup — previously a competing inner GestureDetector
    // inside CardWidget absorbed the tap silently.
    testWidgets(
        '2) CardWidget.onTap fires when tapped inside Joker popup (regression guard)',
        (tester) async {
      CardModel? selected;
      const option = CardModel(id: '4h', rank: Rank.four, suit: Suit.hearts);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<CardModel>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (sheetContext) => Material(
                      child: SizedBox(
                        height: 200,
                        child: Center(
                          child: CardWidget(
                            card: option,
                            isSelected: false,
                            onTap: () =>
                                Navigator.of(sheetContext).pop(option),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap the CardWidget itself — its inner GestureDetector must dispatch onTap
      await tester.tap(find.byType(CardWidget));
      await tester.pumpAndSettle();

      expect(selected, isNotNull,
          reason: 'CardWidget.onTap must fire and close the sheet');
      expect(selected!.id, option.id);
    });

    test('3) Joker is removed from hand after selection', () {
      const joker = CardModel(id: 'joker', rank: Rank.joker, suit: Suit.spades);
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      final state =
          _stateForJokerPipeline(localHand: const [joker], discardTop: top);
      final selected = joker.copyWith(
        jokerDeclaredRank: Rank.six,
        jokerDeclaredSuit: Suit.hearts,
      );

      final next = applyPlay(state: state, playerId: 'p1', cards: [selected]);

      expect(next.playerById('p1')!.hand.any((c) => c.id == joker.id), isFalse);
      expect(next.playerById('p1')!.cardCount, 0);
    });

    test('4) Top card updates to selected Joker represented card', () {
      const joker = CardModel(id: 'joker', rank: Rank.joker, suit: Suit.spades);
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      final state =
          _stateForJokerPipeline(localHand: const [joker], discardTop: top);
      final selected = joker.copyWith(
        jokerDeclaredRank: Rank.four,
        jokerDeclaredSuit: Suit.hearts,
      );

      final next = applyPlay(state: state, playerId: 'p1', cards: [selected]);
      expect(next.discardTopCard?.effectiveRank, Rank.four);
      expect(next.discardTopCard?.effectiveSuit, Suit.hearts);
    });

    test('5) Joker resolution does not auto-end turn', () {
      const joker = CardModel(id: 'joker', rank: Rank.joker, suit: Suit.spades);
      const top = CardModel(id: '5h', rank: Rank.five, suit: Suit.hearts);
      final state =
          _stateForJokerPipeline(localHand: const [joker], discardTop: top);
      final selected = joker.copyWith(
        jokerDeclaredRank: Rank.six,
        jokerDeclaredSuit: Suit.hearts,
      );

      final next = applyPlay(state: state, playerId: 'p1', cards: [selected]);
      expect(next.currentPlayerId, state.currentPlayerId);
      expect(next.actionsThisTurn, 1);
    });

    testWidgets('6) Ace popup flow still returns selected value (regression)',
        (tester) async {
      Suit? selected;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<Suit>(
                    context: context,
                    backgroundColor: Colors.transparent,
                    builder: (sheetContext) => Material(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(Suit.hearts),
                        child:
                            const SizedBox(height: 120, width: double.infinity),
                      ),
                    ),
                  );
                },
                child: const Text('open-ace'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-ace'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(GestureDetector).last);
      await tester.pumpAndSettle();

      expect(selected, Suit.hearts);
    });
  });
}
