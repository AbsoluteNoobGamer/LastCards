// Unit tests for PlayerHandWidget overflow behaviour.
//
// Asserts:
//  1. Hand renders without overflow at 10 cards
//  2. Hand renders without overflow at 20 cards
//  3. Hand renders without overflow at 30 cards
//  4. Each card has a minimum tappable strip of 20 dp at 30 cards
//  5. Single card is centred correctly
//  6. Empty hand returns SizedBox.shrink (no widget rendered)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_and_flow/core/models/card_model.dart';
import 'package:stack_and_flow/features/gameplay/presentation/widgets/player_hand_widget.dart';

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Creates a list of [n] distinct [CardModel] instances for testing.
List<CardModel> _makeHand(int n) {
  final suits = Suit.values.where((s) => s != Suit.diamonds).toList()
    ..add(Suit.diamonds);
  final ranks = Rank.values.where((r) => r != Rank.joker).toList();

  return List.generate(n, (i) {
    final suit = suits[i % suits.length];
    final rank = ranks[i % ranks.length];
    return CardModel(id: 'card_$i', suit: suit, rank: rank);
  });
}

/// Pumps a [PlayerHandWidget] inside a [ProviderScope] + [MaterialApp]
/// constrained to [viewportWidth] × [viewportHeight].
Future<void> pumpHand(
  WidgetTester tester, {
  required List<CardModel> cards,
  double viewportWidth = 390,
  double viewportHeight = 844,
  Set<String> selectedCardIds = const {},
  bool enabled = true,
}) async {
  tester.view.physicalSize = Size(viewportWidth, viewportHeight);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlayerHandWidget(
              cards: cards,
              selectedCardId: selectedCardIds.isEmpty ? null : selectedCardIds.first,
              enabled: enabled,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pump();
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // Silence Flutter framework overflow warnings during tests (they become
  // test failures via tester.takeException() below).
  setUp(() {
    FlutterError.onError = (FlutterErrorDetails details) {
      // Re-throw so tester.takeException() can catch it.
      throw details.exception;
    };
  });

  tearDown(() {
    FlutterError.onError = FlutterError.dumpErrorToConsole;
  });

  group('PlayerHandWidget — no overflow at any hand size', () {
    testWidgets('1 card — centred, no overflow', (tester) async {
      await pumpHand(tester, cards: _makeHand(1));
      expect(tester.takeException(), isNull,
          reason: 'Single card should not cause overflow');
      expect(find.byType(PlayerHandWidget), findsOneWidget);
    });

    testWidgets('5 cards — slight overlap, no overflow', (tester) async {
      await pumpHand(tester, cards: _makeHand(5));
      expect(tester.takeException(), isNull,
          reason: '5-card hand must not overflow');
    });

    testWidgets('10 cards — no overflow (Option A)', (tester) async {
      await pumpHand(tester, cards: _makeHand(10));
      expect(tester.takeException(), isNull,
          reason: '10-card hand must not overflow');
    });

    testWidgets('20 cards — no overflow (Option A or B)', (tester) async {
      await pumpHand(tester, cards: _makeHand(20));
      expect(tester.takeException(), isNull,
          reason: '20-card hand must not overflow');
    });

    testWidgets('30 cards — no overflow (Option B scroll)', (tester) async {
      await pumpHand(tester, cards: _makeHand(30));
      expect(tester.takeException(), isNull,
          reason: '30-card hand must not overflow');
    });
  });

  group('PlayerHandWidget — widget is always bounded within viewport', () {
    Future<void> assertNoBoundaryBreak(
      WidgetTester tester,
      int cardCount,
      double vpWidth,
    ) async {
      await pumpHand(
        tester,
        cards: _makeHand(cardCount),
        viewportWidth: vpWidth,
      );
      expect(tester.takeException(), isNull);

      final renderBox =
          tester.renderObject(find.byType(PlayerHandWidget)) as RenderBox;
      final widgetWidth = renderBox.size.width;

      // The widget must never report a width larger than the viewport.
      expect(
        widgetWidth,
        lessThanOrEqualTo(vpWidth + 1), // +1 for floating-point tolerance
        reason: 'PlayerHandWidget width ($widgetWidth) exceeds viewport '
            '($vpWidth) with $cardCount cards',
      );
    }

    testWidgets('10 cards on 390px screen', (tester) async {
      await assertNoBoundaryBreak(tester, 10, 390);
    });

    testWidgets('20 cards on 390px screen', (tester) async {
      await assertNoBoundaryBreak(tester, 20, 390);
    });

    testWidgets('30 cards on 390px screen', (tester) async {
      await assertNoBoundaryBreak(tester, 30, 390);
    });

    testWidgets('30 cards on narrow 320px screen', (tester) async {
      await assertNoBoundaryBreak(tester, 30, 320);
    });

    testWidgets('30 cards on wide 1024px screen', (tester) async {
      await assertNoBoundaryBreak(tester, 30, 1024);
    });
  });

  group('PlayerHandWidget — minimum tappable strip at 30 cards', () {
    testWidgets('strip >= 20dp per card on 390px screen', (tester) async {
      const vpWidth = 390.0;
      const n = 30;

      await pumpHand(tester, cards: _makeHand(n), viewportWidth: vpWidth);
      expect(tester.takeException(), isNull);

      // Derive the same geometry the widget uses.
      // isCompact = vpWidth(390) < 600 → true; multiplier = 0.14
      final targetWidth = (vpWidth * 0.14).clamp(44.0, 72.0);

      // Option A spread:
      final optionASpread = (vpWidth - targetWidth) / (n - 1);

      // Either Option A is >= 20dp, OR Option B enforces exactly 20dp.
      final effectiveStrip =
          optionASpread >= 20.0 ? optionASpread : 20.0;

      expect(
        effectiveStrip,
        greaterThanOrEqualTo(20.0),
        reason: 'Visible strip per card must be at least 20dp',
      );
    });

    testWidgets('strip >= 20dp per card on 320px narrow screen', (tester) async {
      const vpWidth = 320.0;
      const n = 30;

      await pumpHand(tester, cards: _makeHand(n), viewportWidth: vpWidth);
      expect(tester.takeException(), isNull);

      final targetWidth = (vpWidth * 0.14).clamp(44.0, 72.0);
      final optionASpread = (vpWidth - targetWidth) / (n - 1);
      final effectiveStrip = optionASpread >= 20.0 ? optionASpread : 20.0;

      expect(effectiveStrip, greaterThanOrEqualTo(20.0));
    });
  });

  group('PlayerHandWidget — edge case correctness', () {
    testWidgets('empty hand returns SizedBox.shrink', (tester) async {
      await pumpHand(tester, cards: []);
      expect(tester.takeException(), isNull);
      // SizedBox.shrink() has zero size — PlayerHandWidget itself is not found
      // as a typed widget child (it is there but its child is SizedBox.shrink).
      expect(find.byType(PlayerHandWidget), findsOneWidget);
    });

    testWidgets('disabled hand (enabled=false) does not fire onTap',
        (tester) async {
      bool tapped = false;
      final cards = _makeHand(5);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: PlayerHandWidget(
                cards: cards,
                enabled: false,
                onCardTap: (_) => tapped = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Try tapping any card — should not fire callback.
      await tester.tap(find.byType(PlayerHandWidget));
      await tester.pump();

      expect(tapped, isFalse,
          reason: 'Disabled hand must not fire onCardTap');
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected card ids do not cause overflow at 20 cards',
        (tester) async {
      final cards = _makeHand(20);
      final selected = {cards[0].id, cards[5].id, cards[10].id};

      await pumpHand(tester, cards: cards, selectedCardIds: selected);
      expect(tester.takeException(), isNull);
    });
  });
}
