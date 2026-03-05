import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:deck_drop/app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Seed SharedPreferences so ProfileService doesn't crash during init.
    SharedPreferences.setMockInitialValues({'profile_name': 'Noob 1'});

    // Build our app wrapped in ProviderScope (same as main.dart).
    await tester.pumpWidget(
      const ProviderScope(child: StackAndFlowApp()),
    );

    // Basic check: verify it pumps without crashing.
    expect(find.byType(StackAndFlowApp), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.binding.delayed(const Duration(hours: 1));
  });
}
