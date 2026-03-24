import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:last_cards/core/models/game_state.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/floating_action_bar_widget.dart';

void main() {
  testWidgets('FloatingActionBarWidget does not show timer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FloatingActionBarWidget(
              activePlayerName: 'Test Player',
              direction: PlayDirection.clockwise,
              canEndTurn: true,
              localHandSize: 0,
            ),
          ),
        ),
      ),
    );

    // Verify timer text (00:XX ⏳) is NOT found
    expect(find.textContaining('⏳'), findsNothing);
    expect(find.textContaining('00:'), findsNothing);
    
    // Verify End Turn button IS found
    expect(find.text('End Turn'), findsOneWidget);
  });
}
