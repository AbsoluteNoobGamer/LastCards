import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../start/presentation/screens/start_screen.dart';
import '../screens/sign_in_screen.dart';

/// Shows [SignInScreen] when no user is signed in, otherwise [LastCardsStartScreen].
/// Watches [authStateProvider] and rebuilds when auth state changes.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);

    return authAsync.when(
      data: (user) {
        if (user != null) {
          return const LastCardsStartScreen();
        }
        return const SignInScreen();
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
