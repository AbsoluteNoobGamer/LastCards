import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/features/rules/presentation/screens/rules_screen.dart';

void main() {
  Future<void> pumpRules(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: RulesScreen()),
      ),
    );
    // Bounded pumps, not pumpAndSettle: card widgets (Joker shimmer, etc.)
    // run perpetual animations that never go idle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('renders without throwing and shows core sections', (tester) async {
    await pumpRules(tester);
    expect(tester.takeException(), isNull);

    expect(find.text('RULES'), findsOneWidget);
    expect(find.text('OBJECTIVE'), findsOneWidget);
    expect(find.text('SETUP'), findsOneWidget);
    expect(find.text('YOUR TURN'), findsOneWidget);
    expect(find.text('SPECIAL CARDS'), findsOneWidget);
    expect(find.text('LAST CARDS'), findsOneWidget);
    expect(find.text('GAME MODES'), findsOneWidget);
    expect(find.text('EDGE CASES'), findsOneWidget);
  });

  testWidgets('shows all special cards with a rules explanation', (tester) async {
    await pumpRules(tester);

    for (final name in ['2', 'Black Jack', 'Red Jack', 'King', 'Ace', 'Queen', '8', 'Joker']) {
      expect(
        find.textContaining(name, findRichText: true),
        findsWidgets,
        reason: '$name should be documented in Special Cards',
      );
    }
  });

  testWidgets('quick-nav chips exist for every section and can be tapped', (tester) async {
    // Wide viewport so every chip in the horizontal nav row is actually
    // built (ListView.separated only builds what's near the viewport).
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await pumpRules(tester);

    const sections = [
      'Objective',
      'Setup',
      'Your Turn',
      'Multiple Cards',
      'Special Cards',
      'Last Cards',
      'Game Modes',
      'Edge Cases',
    ];
    for (final label in sections) {
      expect(find.text(label), findsOneWidget, reason: 'missing nav chip for $label');
    }

    // Tapping a chip scrolls to that section without throwing.
    await tester.tap(find.text('Edge Cases'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.text('EDGE CASES'), findsOneWidget);
  });

  testWidgets('back button pops the screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RulesScreen()),
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
    expect(find.text('RULES'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('RULES'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
