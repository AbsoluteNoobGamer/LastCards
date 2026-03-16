import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../start/presentation/screens/start_screen.dart';
import '../screens/sign_in_screen.dart';

/// Duration to wait after receiving null on cold start before treating as signed out.
/// Allows Firebase Auth time to restore persisted session.
const _kAuthRestoreGracePeriod = Duration(milliseconds: 600);

/// Shows [SignInScreen] when no user is signed in, otherwise [LastCardsStartScreen].
/// Watches [authStateProvider] and rebuilds when auth state changes.
/// On cold start, adds a grace period when null is received so Firebase can
/// restore persisted credentials before showing the sign-in screen.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  Timer? _gracePeriodTimer;
  bool _gracePeriodElapsed = false;
  /// True once we've seen a non-null user this session. After that, we trust
  /// null as "signed out" and skip the grace period (avoids delay on sign out).
  bool _hasSeenUserThisSession = false;

  @override
  void dispose() {
    _gracePeriodTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);

    return authAsync.when(
      data: (user) {
        if (user != null) {
          _gracePeriodTimer?.cancel();
          _gracePeriodTimer = null;
          _gracePeriodElapsed = false;
          _hasSeenUserThisSession = true;
          return const LastCardsStartScreen();
        }
        // User is null.
        if (_hasSeenUserThisSession) {
          // We've seen a user before (e.g. user signed out) — show sign-in immediately.
          return const SignInScreen();
        }
        if (_gracePeriodElapsed) {
          return const SignInScreen();
        }
        // Cold start: first null before any user. Start grace period if not yet started.
        _gracePeriodTimer ??= Timer(_kAuthRestoreGracePeriod, () {
          _gracePeriodTimer = null;
          if (mounted) {
            setState(() => _gracePeriodElapsed = true);
          }
        });
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => const SignInScreen(),
    );
  }
}
