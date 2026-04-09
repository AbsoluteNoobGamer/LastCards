import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:last_cards/features/auth/presentation/screens/sign_in_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SignInScreen shows Sign in with Apple on iOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SignInScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(SignInWithAppleButton), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('SignInScreen hides Sign in with Apple on Android', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SignInScreen()),
      ),
    );
    await tester.pump();
    expect(find.byType(SignInWithAppleButton), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
