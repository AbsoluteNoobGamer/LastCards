import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../online/providers/online_session_provider.dart';
import '../../online/screens/matchmaking_screen.dart';
import '../../single_player/providers/single_player_session_provider.dart';
import '../../tournament/providers/tournament_session_provider.dart';
import '../../tournament/widgets/tournament_sub_mode_sheet.dart';
import '../screens/bust_game_screen.dart';

class BustSetupSheet extends ConsumerWidget {
  const BustSetupSheet({required this.isOnline, super.key});

  /// Whether this Bust session is online (real players) or offline (vs AI).
  final bool isOnline;

  void _goBack(BuildContext context, TournamentType type) {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TournamentSubModeSheet(type: type),
    );
  }

  void _onStart(BuildContext context, WidgetRef ref) {
    Navigator.of(context).pop();

    if (isOnline) {
      ref.read(onlineSessionProvider.notifier).setPlayerCount(10);
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
    } else {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => BustGameScreen(
            totalPlayers: 10,
            aiDifficulty: AiDifficulty.hard,
            isOnline: false,
          ),
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
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final tournamentType = ref.watch(tournamentSessionProvider).type
        ?? (isOnline ? TournamentType.online : TournamentType.vsAi);

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
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.textSecondary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),

            // Header row with back button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: theme.accentPrimary,
                        size: 30,
                      ),
                      onPressed: () => _goBack(context, tournamentType),
                      tooltip: 'Back',
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        'Bust Mode',
                        style: GoogleFonts.cinzel(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.accentPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Last one standing wins',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: theme.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Mode info card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  color: theme.backgroundMid,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.accentDark.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                      icon: Icons.group_rounded,
                      label: isOnline ? '10 players (online)' : '10 players (vs AI)',
                      theme: theme,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.rotate_right_rounded,
                      label: '2 rotations per round',
                      theme: theme,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.cancel_rounded,
                      label: '2 players eliminated each round',
                      theme: theme,
                      color: AppColors.redAccent,
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.emoji_events_rounded,
                      label: 'Last player standing wins',
                      theme: theme,
                      color: AppColors.goldPrimary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Start CTA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StartButton(
                onTap: () => _onStart(context, ref),
                theme: theme,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Info row ───────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.theme,
    this.color,
  });

  final IconData icon;
  final String label;
  final dynamic theme;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? theme.accentPrimary;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: c),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ── Start button ───────────────────────────────────────────────────────────────

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onTap, required this.theme});

  final VoidCallback onTap;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [theme.accentLight, theme.accentPrimary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: theme.accentPrimary,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.30),
            blurRadius: 16,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: theme.backgroundDeep,
                ),
                const SizedBox(width: 8),
                Text(
                  'Start Bust',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: theme.backgroundDeep,
                    letterSpacing: 1.0,
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
