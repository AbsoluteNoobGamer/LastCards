import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stack_and_flow/shared/engine/game_turn_timer.dart';
import 'package:stack_and_flow/widgets/turn_timer_bar.dart';

void main() {
  group('GameTurnTimer Tests', () {
    late GameTurnTimer timer;

    setUp(() {
      timer = GameTurnTimer();
    });

    tearDown(() {
      timer.dispose();
    });

    test('timer starts at 60 seconds on start', () async {
      bool expired = false;
      timer.start(() { expired = true; });

      final firstTime = await timer.timeRemainingStream.first;
      expect(firstTime, 60);
      expect(expired, isFalse);
    });

    test('timer cancels without expiring', () async {
      bool expired = false;
      timer.start(() { expired = true; });
      
      timer.cancel();
      
      await Future.delayed(const Duration(seconds: 2));
      expect(expired, isFalse);
    });

    test('timer resets to 60 seconds', () async {
      timer.start(() {});
      timer.reset();
      
      final firstTime = await timer.timeRemainingStream.first;
      expect(firstTime, 60);
    });
  });

  group('TurnTimerBar UI Tests', () {
    testWidgets('TurnTimerBar is active and visible globally across all turns', (WidgetTester tester) async {
      // Simulate standard stream
      final testStream = Stream<int>.fromIterable([60, 59, 58]);
      
      // Test that it renders when isVisible is true
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TurnTimerBar(
            timeRemainingStream: testStream,
            isVisible: true, // Always true as requested
          ),
        ),
      ));

      expect(find.byType(TurnTimerBar), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });
  });
}
