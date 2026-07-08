import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/app/app.dart';
import 'package:last_cards/app/router/app_routes.dart';
import 'package:last_cards/app/splash_screen.dart';
import 'package:last_cards/core/providers/auth_profile_sync_provider.dart';
import 'package:last_cards/core/providers/auth_provider.dart';
import 'package:last_cards/core/providers/card_style_firestore_sync_provider.dart';
import 'package:last_cards/core/providers/user_profile_provider.dart';
import 'package:last_cards/core/services/audio_service.dart';
import 'package:last_cards/core/services/firestore_profile_service.dart';
import 'package:last_cards/features/auth/presentation/widgets/auth_gate.dart';
import 'package:last_cards/features/gameplay/presentation/screens/table_screen.dart';
import 'package:last_cards/features/lobby/presentation/screens/lobby_screen.dart';
import 'package:last_cards/features/start/presentation/screens/start_screen.dart';

class _MockAudioService extends AudioService {}

User _signedInUser() => MockUser(
      uid: 'routing-test-uid',
      email: 'routing@test.com',
      displayName: 'Router',
      isEmailVerified: true,
    );

/// Mirrors [main] SharedPreferences seeding so profile/theme init stays hermetic.
void _seedPrefs() {
  SharedPreferences.setMockInitialValues({'profile_name': 'Player'});
}

List<Override> _routingOverrides({User? user}) {
  final displayName = user?.displayName ?? 'Player';
  return [
    authStateProvider.overrideWith(
      (ref) => Stream<User?>.value(user),
    ),
    authProfileSyncProvider.overrideWith((ref) {}),
    cardStyleFirestoreSyncProvider.overrideWith((ref) {}),
    firestoreUserProfileSnapshotsProvider.overrideWith(
      (ref) => Stream<FirestoreUserProfile?>.value(null),
    ),
    userProfileProvider.overrideWith(
      (ref) => Stream.value(
        UserProfile(displayName: displayName, profileLastChangedAt: null),
      ),
    ),
    audioServiceProvider.overrideWith((ref) => _MockAudioService()),
  ];
}

Future<void> _pumpNamedRoute(
  WidgetTester tester,
  String route, {
  User? signedInUser,
}) async {
  final builder = appRoutes[route];
  expect(builder, isNotNull, reason: 'Route $route should be registered');

  await tester.pumpWidget(
    ProviderScope(
      overrides: _routingOverrides(user: signedInUser),
      child: MaterialApp(
        home: Builder(builder: builder!),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpLastCardsApp(
  WidgetTester tester, {
  User? signedInUser,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _routingOverrides(user: signedInUser),
      child: const LastCardsApp(),
    ),
  );
  await tester.pump();
}

Future<void> _flushSplashTimer(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUp(_seedPrefs);

  /// Default flutter_test surface is 800x600 — shorter than any real phone,
  /// which makes some full-screen layouts (e.g. SplashScreen) overflow in a
  /// way that never happens on an actual device. Use a realistic portrait
  /// phone size instead.
  Future<void> useRealisticPhoneViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'LastCardsApp bootstrap reaches AppRoutes.start with start screen',
    (tester) async {
      await useRealisticPhoneViewport(tester);
      await _pumpLastCardsApp(tester, signedInUser: _signedInUser());

      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump();

      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(LastCardsStartScreen), findsOneWidget);

      await _flushSplashTimer(tester);
    },
  );

  testWidgets('route start resolves to AuthGate', (tester) async {
    await _pumpNamedRoute(tester, AppRoutes.start);
    expect(find.byType(AuthGate), findsOneWidget);
  });

  testWidgets(
    'route start shows LastCardsStartScreen when signed in',
    (tester) async {
      await _pumpNamedRoute(
        tester,
        AppRoutes.start,
        signedInUser: _signedInUser(),
      );
      expect(find.byType(LastCardsStartScreen), findsOneWidget);
    },
  );

  testWidgets('route lobby is not registered in appRoutes', (tester) async {
    expect(appRoutes.containsKey('/lobby'), isFalse);
    expect(appRoutes[AppRoutes.start], isNotNull);
    expect(appRoutes[AppRoutes.game], isNotNull);
  });

  testWidgets('route game resolves to TableScreen', (tester) async {
    final builder = appRoutes[AppRoutes.game]!;
    late Widget built;
    await tester.pumpWidget(
      ProviderScope(
        overrides: _routingOverrides(),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              built = builder(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(built, isA<TableScreen>());
  });

  testWidgets('unknown route string does not crash the app', (tester) async {
    await useRealisticPhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _routingOverrides(),
        child: MaterialApp(
          initialRoute: AppRoutes.splash,
          routes: appRoutes,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SplashScreen), findsOneWidget);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(
      () => navigator.pushNamed('/does-not-exist'),
      throwsA(
        isA<AssertionError>().having(
          (e) => e.toString(),
          'message',
          contains('Could not find a generator for route'),
        ),
      ),
    );

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(LobbyScreen), findsNothing);

    await _flushSplashTimer(tester);
  });
}
