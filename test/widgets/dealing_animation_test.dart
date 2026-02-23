import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stack_and_flow/features/gameplay/presentation/screens/table_screen.dart';
import 'package:stack_and_flow/features/gameplay/presentation/widgets/card_widget.dart';
import 'package:stack_and_flow/features/gameplay/presentation/widgets/draw_pile_widget.dart';
import 'package:stack_and_flow/core/services/audio_service.dart';

class MockAudioService extends AudioService {
  @override
  Future<void> startBgm() async {}
  @override
  Future<void> playClick() async {}
  @override
  Future<void> stopBgm() async {}
}

void main() {
  testWidgets('Sequential Dealer Animation works and blocks early input',
      (WidgetTester tester) async {
    // 1. Setup the widget tree
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    
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

    // Initial build finishes
    await tester.pump();

    // ── Phase 1: During Dealing ──────────────────────────────────────
    // Wait for the postFrameCallback to fire
    await tester.pump(const Duration(milliseconds: 50));

    final statusFinder = find.byKey(const ValueKey('dealer-status'));
    expect(statusFinder, findsOneWidget);
    expect((tester.widget(statusFinder) as Text).data, 'DEALING...');
    
    // Attempt invalid action: tap the draw pile. 
    final drawPile = find.byType(DrawPileWidget);
    await tester.tap(drawPile);
    await tester.pump(); 
    
    // We expect the text to still be DEALING...
    expect((tester.widget(statusFinder) as Text).data, 'DEALING...');

    // ── Phase 2: Wait for Deal to Complete ───────────────────────────
    // 14 cards * (150ms + 50ms) = 2.8s. We pump 100ms at a time.
    int safety = 0;
    while ((tester.widget(statusFinder) as Text).data == 'DEALING...' && safety < 100) {
      await tester.pump(const Duration(milliseconds: 100));
      safety++;
    }
    await tester.pump();
    
    // Now it should show "DEALER"
    expect((tester.widget(statusFinder) as Text).data, 'DEALER');

    // ── Phase 3: Post-Deal Normal Action ─────────────────────────────
    final cards = find.byType(CardWidget);
    expect(cards, findsAtLeastNWidgets(8)); // 7 hand + 1 discard top
    
    // Note: We avoid pumpWidget(SizedBox()) cleanup here if the 
    // periodic turn timer and async deal loops might leak,
    // but we should ensure we pump to clear any pending animations.
    await tester.pumpAndSettle();
  });
}
