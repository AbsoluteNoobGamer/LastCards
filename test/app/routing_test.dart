import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/app/router/app_routes.dart';
import 'package:last_cards/app/splash_screen.dart';
import 'package:last_cards/core/providers/auth_provider.dart';
import 'package:last_cards/features/auth/presentation/widgets/auth_gate.dart';

void main() {
  test('route map contains splash, start, and game', () {
    expect(appRoutes.containsKey(AppRoutes.splash), isTrue);
    expect(appRoutes.containsKey(AppRoutes.start), isTrue);
    expect(appRoutes.containsKey(AppRoutes.game), isTrue);
  });

  test('splash route builder is non-null', () {
    final builder = appRoutes[AppRoutes.splash];
    expect(builder, isNotNull);
  });

  testWidgets('app starts on splash route', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          initialRoute: AppRoutes.splash,
          routes: appRoutes,
        ),
      ),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
    // SplashScreen schedules navigation after 2.5s — flush so the test binding
    // does not report a pending timer.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('AuthGate is the widget used for /start route', (tester) async {
    final builder = appRoutes[AppRoutes.start]!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => Stream<User?>.value(null)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => builder(context),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AuthGate), findsOneWidget);
  });
}
