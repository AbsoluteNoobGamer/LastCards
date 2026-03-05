import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:deck_drop/features/gameplay/presentation/widgets/floating_action_bar_widget.dart';
import 'package:deck_drop/features/gameplay/domain/entities/game_state.dart';

void main() {
  testWidgets('FloatingActionBarWidget does not show timer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FloatingActionBarWidget(
            activePlayerName: 'Test Player',
            direction: PlayDirection.clockwise,
            canEndTurn: true,
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
