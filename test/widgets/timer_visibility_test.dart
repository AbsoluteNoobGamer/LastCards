import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stack_and_flow/features/gameplay/presentation/widgets/status_bar_widget.dart';
import 'package:stack_and_flow/features/gameplay/domain/entities/game_state.dart';

void main() {
  testWidgets('StatusBarWidget does not show timer', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBarWidget(
            activePlayerName: 'Test Player',
            direction: PlayDirection.clockwise,
            upcomingPlayerNames: ['Next Player'],
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
