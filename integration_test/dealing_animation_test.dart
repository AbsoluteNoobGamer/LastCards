import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:last_cards/main.dart' as app;
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Sequential Dealer Animation works and blocks early input',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    app.main();
    await tester.pumpAndSettle();

    // Navigate to the TableScreen (assuming Practice mode button is there to start)
    // Find the "Practice Mode" button on the Start Screen
    final practiceModeButton = find.text('PRACTICE MODE');
    expect(practiceModeButton, findsOneWidget);

    // Tap it to go to TableScreen
    await tester.tap(practiceModeButton);
    await tester.pump();

    // Wait for route transition
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TableScreen), findsOneWidget);

    // ── Phase 1: During Dealing ──────────────────────────────────────
    // The animation starts immediately. It does 7 cards * 2 players * 150ms = ~2.1 seconds.
    // At the very start, no cards should be visible in hands

    // Let's pump 50 milliseconds in
    await tester.pump(const Duration(milliseconds: 50));

    // Look for the dealer badge showing "DEALING..."
    expect(find.text('DEALING...'), findsOneWidget);

    // Attempt invalid action: tap the draw pile.
    // It should be disabled during dealing. We check if playing it causes state change.
    final drawPile = find.byType(DrawPileWidget);
    expect(drawPile, findsOneWidget);

    // Attempt to tap - this shouldn't crash or advance the game
    await tester.tap(drawPile);
    await tester.pump();

    // We expect the text to still be DEALING... because the animation is still running
    expect(find.text('DEALING...'), findsOneWidget);

    // ── Phase 2: Wait for Deal to Complete ───────────────────────────
    // Pump frames until the animation timer is done (around 2200ms total)
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    // Now it should show "DEALER" not "DEALING..."
    expect(find.text('DEALER'), findsOneWidget);
    expect(find.text('DEALING...'), findsNothing);

    // ── Phase 3: Post-Deal Normal Action ─────────────────────────────
    // Now cards should be tappable and the draw pile is enabled.

    // The player's hand should have exactly 7 CardWidgets rendered
    // Note: Opponent has CardBackWidgets, so we look for CardWidget (face up)
    final cards = find.byType(CardWidget);
    expect(cards, findsNWidgets(7)); // Only local player has face-up cards

    // Tap the draw pile to verify normal interaction has returned.
    await tester.tap(drawPile);
    await tester.pumpAndSettle();

    // After drawing 1 card, the hand should have 8 cards
    expect(find.byType(CardWidget), findsNWidgets(8));
  });
}
