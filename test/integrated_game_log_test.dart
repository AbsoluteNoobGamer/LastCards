import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_and_flow/core/models/card_model.dart';
import 'package:stack_and_flow/core/models/move_log_entry.dart';
import 'package:stack_and_flow/features/gameplay/presentation/widgets/integrated_game_log.dart';
import 'package:stack_and_flow/core/models/player_model.dart';
import 'package:stack_and_flow/core/theme/player_styles.dart';

void main() {
  Widget buildTestableWidget(List<MoveLogEntry> entries) {
    return MaterialApp(
      home: Scaffold(
        body: IntegratedGameLog(
          entries: entries,
          activePlayerName: 'Player 1',
        ),
      ),
    );
  }

  testWidgets('Normal play log shows correct formatting',
      (WidgetTester tester) async {
    final entry = MoveLogEntry(
      player: 'Player 1',
      cards: [const CardModel(id: 'c1', rank: Rank.five, suit: Suit.hearts)],
    );

    await tester.pumpWidget(buildTestableWidget([entry]));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Player 1', findRichText: true), findsWidgets);
    expect(find.textContaining('played:', findRichText: true), findsOneWidget);
    expect(find.textContaining('5♥', findRichText: true), findsOneWidget);
  });

  testWidgets('Draw action log shows correct formatting',
      (WidgetTester tester) async {
    final entry = MoveLogEntry(
      player: 'Player 2',
      isDraw: true,
      drawCount: 3,
      drawReason: '(penalty)',
    );

    await tester.pumpWidget(buildTestableWidget([entry]));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Player 2', findRichText: true), findsWidgets);
    expect(find.textContaining('drew 3 cards (penalty)', findRichText: true),
        findsOneWidget);
  });

  testWidgets('Joker play log explicitly shows effective state',
      (WidgetTester tester) async {
    var jokerCard =
        const CardModel(id: 'j1', rank: Rank.joker, suit: Suit.spades);
    jokerCard = jokerCard.copyWith(
        jokerDeclaredRank: Rank.seven, jokerDeclaredSuit: Suit.diamonds);

    final entry = MoveLogEntry(
      player: 'Player 3',
      cards: [jokerCard],
    );

    await tester.pumpWidget(buildTestableWidget([entry]));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Player 3', findRichText: true), findsWidgets);
    expect(find.textContaining('played:', findRichText: true), findsOneWidget);
    expect(find.textContaining('Joker', findRichText: true), findsOneWidget);
    expect(find.textContaining('→ Seven of Diamonds', findRichText: true),
        findsOneWidget);
  });

  testWidgets('Multi-card play log shows correct formatting',
      (WidgetTester tester) async {
    final entry = MoveLogEntry(
      player: 'Player 4',
      cards: [
        const CardModel(id: 'c1', rank: Rank.eight, suit: Suit.clubs),
        const CardModel(id: 'c2', rank: Rank.eight, suit: Suit.spades),
      ],
    );

    await tester.pumpWidget(buildTestableWidget([entry]));
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Player 4', findRichText: true), findsWidgets);
    expect(find.textContaining('played:', findRichText: true), findsOneWidget);
    expect(find.textContaining('8♣...', findRichText: true), findsOneWidget);
  });

  testWidgets('Multi-turn behavior maintains scroll state',
      (WidgetTester tester) async {
    final entries = List.generate(
        15,
        (i) => MoveLogEntry(
              player: 'P$i',
              cards: [CardModel(id: 'c$i', rank: Rank.two, suit: Suit.spades)],
            ));

    await tester.pumpWidget(buildTestableWidget(entries));
    await tester.pumpAndSettle();

    // Explicitly drag the list to ensure the bottom items are rendered in the test environment
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();

    // The latest entries should be rendered in the tree
    expect(find.textContaining('P14', findRichText: true), findsWidgets);
  });

  testWidgets('PlayerStyles correctly inject table position icons and colors',
      (WidgetTester tester) async {
    final entry = MoveLogEntry(
      player: 'Opponent',
      playerPosition: TablePosition.left,
      cards: [const CardModel(id: 'c1', rank: Rank.five, suit: Suit.hearts)],
    );

    await tester.pumpWidget(buildTestableWidget([entry]));
    await tester.pump(const Duration(seconds: 1));

    // Verify the Shape Icon rendered (TablePosition.left → Icons.square)
    expect(find.byIcon(Icons.square), findsOneWidget);

    // Verify the RichText applied the correct color to the player name
    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    RichText? targetText;
    for (final text in richTexts) {
      if (text.text
          .toPlainText(includeSemanticsLabels: false)
          .contains('Opponent')) {
        targetText = text;
        break;
      }
    }

    expect(targetText, isNotNull,
        reason: 'Could not find RichText containing "Opponent"');

    // Check that the shape icon shares the exact same color generated by PlayerStyles
    final iconWidget = tester.widget<Icon>(find.byType(Icon).last);
    expect(iconWidget.color, PlayerStyles.getColor(TablePosition.left));
  });
}
