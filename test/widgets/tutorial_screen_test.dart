import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/features/rules/presentation/screens/rules_screen.dart';
import 'package:last_cards/features/tutorial/presentation/screens/tutorial_screen.dart';
import 'package:last_cards/features/tutorial/presentation/widgets/tutorial_slides.dart';

void main() {
  Future<void> pumpTutorial(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: TutorialScreen()),
      ),
    );
    // Bounded pumps, not pumpAndSettle: each slide's LoopingDemo loops
    // forever and never goes idle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> tapBack(WidgetTester tester) async {
    await tester.tap(find.text('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders without throwing and shows the welcome slide', (tester) async {
    await pumpTutorial(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('HOW TO PLAY'), findsOneWidget);
    expect(find.text('How to play'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('progress dots count matches the slide count', (tester) async {
    await pumpTutorial(tester);

    // The welcome slide's own content (an Icon) has no AnimatedContainer of
    // its own, so every AnimatedContainer on screen at this point is a dot.
    expect(find.byType(AnimatedContainer), findsNWidgets(tutorialSlides.length));
  });

  testWidgets('Next advances the slideshow, Back returns to the previous slide',
      (tester) async {
    await pumpTutorial(tester);
    expect(find.text('How to play'), findsOneWidget);

    await tapNext(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('How to play'), findsNothing);
    expect(find.text('Your turn'), findsOneWidget);

    await tapBack(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Your turn'), findsNothing);
    expect(find.text('How to play'), findsOneWidget);
  });

  testWidgets('Skip pops the screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TutorialScreen()),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('HOW TO PLAY'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('HOW TO PLAY'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('final slide offers "Read the full rules", which opens the Rules screen',
      (tester) async {
    await pumpTutorial(tester);

    for (var i = 0; i < tutorialSlides.length - 1; i++) {
      await tapNext(tester);
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Read the full rules'), findsOneWidget);
    expect(find.text('Start playing'), findsOneWidget);

    await tester.tap(find.text('Read the full rules'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('RULES'), findsOneWidget);
    expect(find.byType(RulesScreen), findsOneWidget);
  });
}
