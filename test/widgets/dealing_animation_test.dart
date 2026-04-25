import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/card_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_hand_widget.dart';

class MockAudioService extends AudioService {}

void main() {
  testWidgets('Sequential Dealer Animation works and blocks early input',
      (WidgetTester tester) async {
    // 1. Setup the widget tree
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    int localHandCardCount() {
      final hand = find.byType(PlayerHandWidget);
      return tester
          .widgetList(
            find.descendant(
              of: hand,
              matching: find.byType(CardWidget),
            ),
          )
          .length;
    }

    final mockAudio = MockAudioService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioServiceProvider.overrideWith((ref) => mockAudio),
        ],
        child: const MaterialApp(
          home: TableScreen(totalPlayers: 2),
        ),
      ),
    );

    // Initial build finishes; wait until deal animation has set _isDealing
    // (one frame is not always enough on CI).
    final statusFinder = find.byKey(const ValueKey('dealer-status'));
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      if (statusFinder.evaluate().isNotEmpty) {
        final t = tester.widget(statusFinder) as Text;
        if (t.data == 'DEALING...') break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(statusFinder, findsOneWidget);
    expect((tester.widget(statusFinder) as Text).data, 'DEALING...');
    
    // Attempt invalid action: tap the draw pile. 
    final drawPile = find.byType(DrawPileWidget);
    await tester.tap(drawPile);
    await tester.pump(); 
    
    // We expect the text to still be DEALING...
    expect((tester.widget(statusFinder) as Text).data, 'DEALING...');

    // ── Phase 2: Wait for Deal to Complete ───────────────────────────
    // 14 deal steps (7 per player); local [PlayerHandWidget] reveals one card
    // at a time. Count only hand descendants — [DiscardPileWidget] can mount
    // several [CardWidget]s (stacked history), which breaks
    // `all CardWidgets - 1`.
    int lastHandCount = 0;
    int safety = 0;
    while ((tester.widget(statusFinder) as Text).data == 'DEALING...' && safety < 100) {
      await tester.pump(const Duration(milliseconds: 100));
      
      final currentHandCount = localHandCardCount();
      if (currentHandCount > lastHandCount) {
        expect(currentHandCount, lastHandCount + 1, reason: 'Hand should grow sequentially');
        lastHandCount = currentHandCount;
        debugPrint('Revealed card $currentHandCount to player');
      }
      
      safety++;
    }
    await tester.pump();
    
    // Now it should show "DEALER"
    expect((tester.widget(statusFinder) as Text).data, 'DEALER');
    expect(lastHandCount, 7, reason: 'Final hand count should be 7');

    // ── Phase 3: Post-Deal Normal Action ─────────────────────────────
    expect(localHandCardCount(), 7);
    final cards = find.byType(CardWidget);
    expect(cards, findsAtLeastNWidgets(8));
    
    // Note: We avoid pumpWidget(SizedBox()) cleanup here if the 
    // periodic turn timer and async deal loops might leak,
    // but we should ensure we pump to clear any pending animations.
    // await tester.pumpAndSettle(); // REMOVED: hangs due to periodic timer/animations
  });
}
