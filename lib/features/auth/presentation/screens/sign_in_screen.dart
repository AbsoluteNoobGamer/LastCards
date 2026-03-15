import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/auth_provider.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/providers/theme_provider.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/StackandFlowBackground.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.overlayTop,
                theme.overlayBottom,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFFFFE566),
                          Color(0xFFC9A84C),
                          Color(0xFFFFE566),
                        ],
                      ).createShader(bounds),
                      child: Text(
                        'Last Cards',
                        style: GoogleFonts.cinzel(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 5.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in to play Ranked and keep your progress',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: theme.accentPrimary.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 48),
                    _SignInButton(
                      label: 'Sign in with Google',
                      icon: Icons.g_mobiledata_rounded,
                      onPressed: () {
                        ref.read(authServiceProvider).signInWithGoogle().then(
                          (result) {
                            if (!context.mounted) return;
                            switch (result) {
                              case GoogleSignInSuccess():
                                break; // AuthGate will navigate
                              case GoogleSignInCancelled():
                                break; // User closed picker, no message
                              case GoogleSignInFailure(:final message):
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(message),
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _SignInButton(
                      label: 'Continue as Guest',
                      icon: Icons.person_outline_rounded,
                      subtitle: 'Same account on this device',
                      onPressed: () {
                        ref
                            .read(authServiceProvider)
                            .signInAnonymously()
                            .catchError((e) {
                          if (!context.mounted) return null;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not sign in as guest: $e',
                              ),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                          return null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInButton extends ConsumerWidget {
  const _SignInButton({
    required this.label,
    required this.icon,
    this.subtitle,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String? subtitle;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.accentPrimary.withValues(alpha: 0.6),
              ),
              color: Colors.black.withValues(alpha: 0.4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: theme.accentPrimary, size: 24),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: theme.accentPrimary.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
