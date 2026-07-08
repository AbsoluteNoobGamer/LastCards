import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_route_observer.dart';
import 'router/navigator_key.dart';
import 'start_screen_bgm_navigator_observer.dart';
import '../core/theme/app_theme_data.dart';
import '../core/providers/auth_profile_sync_provider.dart';
import '../core/providers/card_style_firestore_sync_provider.dart';
import '../core/providers/online_rejoin_listener_provider.dart';
import '../core/providers/reaction_wheel_provider.dart';
import '../core/providers/theme_provider.dart';
import '../features/settings/presentation/widgets/settings_modal.dart';
import 'router/app_routes.dart';

/// Wraps [FirebaseAnalyticsObserver] construction behind a provider so tests
/// can override it with a no-op observer instead of touching the real
/// Firebase Analytics SDK — which requires `Firebase.initializeApp()` to
/// have run, never true in the test sandbox. Production behavior is
/// unchanged: this returns the exact same observer as before.
final analyticsNavigatorObserverProvider = Provider<NavigatorObserver>((ref) {
  return FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance);
});

class StackAndFlowApp extends ConsumerStatefulWidget {
  const StackAndFlowApp({super.key});

  @override
  ConsumerState<StackAndFlowApp> createState() => _StackAndFlowAppState();
}

class _StackAndFlowAppState extends ConsumerState<StackAndFlowApp> {
  @override
  void initState() {
    super.initState();
    // Load the persisted theme index from SharedPreferences on start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(themeProvider.notifier).loadFromPrefs();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(onlineRejoinListenerProvider);
    ref.watch(authProfileSyncProvider);
    ref.watch(cardStyleFirestoreSyncProvider);
    ref.watch(reactionWheelProvider);
    final themeState = ref.watch(themeProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);
    final analyticsObserver = ref.watch(analyticsNavigatorObserverProvider);
    return MaterialApp(
      title: 'Last Cards',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: buildThemeData(themeState.theme),
      initialRoute: AppRoutes.splash,
      routes: appRoutes,
      navigatorObservers: [
        appRouteObserver,
        startScreenBgmNavigatorObserver,
        analyticsObserver,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            disableAnimations: mq.disableAnimations || reduceMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
