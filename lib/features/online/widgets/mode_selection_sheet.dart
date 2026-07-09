import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/navigation/app_page_routes.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../lobby/presentation/screens/lobby_screen.dart';
import '../providers/online_session_provider.dart';
import '../screens/matchmaking_screen.dart';
import 'player_count_sheet.dart';

/// Bottom Sheet — online mode selection. Quick Match, Ranked, and Ranked
/// Hardcore are one-tap straight into matchmaking; Private Game opens the
/// lobby. Picking a specific table size is a secondary link below the
/// main cards rather than its own top-level mode.
class ModeSelectionSheet extends ConsumerWidget {
  const ModeSelectionSheet({super.key});

  static const _topLevelModes = [
    OnlineGameMode.quickMatchCasual,
    OnlineGameMode.ranked,
    OnlineGameMode.rankedHardcore,
    OnlineGameMode.privateGame,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return Container(
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textSecondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Choose Mode',
              style: GoogleFonts.cinzel(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: theme.accentPrimary,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select how you want to play online',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: theme.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: _topLevelModes.map((mode) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ModeCard(
                      mode: mode,
                      onTap: () => _onModeSelected(context, ref, mode),
                    ),
                  );
                }).toList(),
              ),
            ),
            TextButton(
              onPressed: () => _onCustomTableSize(context, ref),
              child: Text(
                'Prefer a specific table size? Choose players',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: theme.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.textSecondary.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  void _onModeSelected(
    BuildContext context, WidgetRef ref, OnlineGameMode mode) {
    if (mode == OnlineGameMode.ranked ||
        mode == OnlineGameMode.rankedHardcore) {
      final user = ref.read(authStateProvider).value;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Sign in is required for Ranked mode. Please restart the app to sign in.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
    }

    ref.read(onlineSessionProvider.notifier).setMode(mode);
    Navigator.of(context).pop();

    if (mode == OnlineGameMode.privateGame) {
      Navigator.of(context).push(
        AppPageRoutes.fadeSlide((_) => const LobbyScreen()),
      );
      return;
    }

    // Quick Match, Ranked, and Ranked Hardcore are all one-tap now — go
    // straight into matchmaking with no intermediate submenu.
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MatchmakingScreen(),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _onCustomTableSize(BuildContext context, WidgetRef ref) {
    ref
        .read(onlineSessionProvider.notifier)
        .setMode(OnlineGameMode.selectTableCasual);
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PlayerCountSheet(),
    );
  }
}

class _ModeCard extends ConsumerStatefulWidget {
  const _ModeCard({required this.mode, required this.onTap});

  final OnlineGameMode mode;
  final VoidCallback onTap;

  @override
  ConsumerState<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends ConsumerState<_ModeCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        scale: _isPressed ? 0.97 : (_isHovered ? 1.02 : 1.0),
        curve: Curves.easeOutCubic,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: _isHovered
                  ? theme.accentPrimary.withValues(alpha: 0.08)
                  : theme.backgroundMid,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isHovered
                    ? theme.accentPrimary.withValues(alpha: 0.7)
                    : theme.accentDark.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.accentPrimary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.accentPrimary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.accentPrimary.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.mode.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.mode.displayName,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.mode.description,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.textSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.accentPrimary.withValues(alpha: 0.6),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
