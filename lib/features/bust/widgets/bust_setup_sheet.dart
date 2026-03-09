import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/providers/theme_provider.dart';
import '../../single_player/providers/single_player_session_provider.dart';
import '../../tournament/widgets/tournament_type_sheet.dart';
import '../screens/bust_game_screen.dart';

class BustSetupSheet extends ConsumerStatefulWidget {
  const BustSetupSheet({super.key});

  @override
  ConsumerState<BustSetupSheet> createState() => _BustSetupSheetState();
}

class _BustSetupSheetState extends ConsumerState<BustSetupSheet> {
  int _playerCount = 10;
  AiDifficulty _difficulty = AiDifficulty.medium;

  void _goBack(BuildContext context) {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TournamentTypeSheet(),
    );
  }

  void _onStart(BuildContext context) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => BustGameScreen(
          totalPlayers: _playerCount,
          aiDifficulty: _difficulty,
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

  @override
  Widget build(BuildContext context) {
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
                      onPressed: () => _goBack(context),
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
                        'Setup',
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

            // Player count stepper
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.backgroundMid,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.accentDark.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Players',
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: theme.textPrimary,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Including you',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StepperControl(
                      value: _playerCount,
                      min: 5,
                      max: 10,
                      onChanged: (v) => setState(() => _playerCount = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Difficulty chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                    Text(
                      'AI Difficulty',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.textPrimary,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: AiDifficulty.values.map((d) {
                        final isSelected = _difficulty == d;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: d != AiDifficulty.values.last ? 8 : 0,
                            ),
                            child: GestureDetector(
                              onTap: () => setState(() => _difficulty = d),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? theme.accentPrimary
                                          .withValues(alpha: 0.18)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isSelected
                                        ? theme.accentPrimary
                                        : theme.accentDark
                                            .withValues(alpha: 0.35),
                                    width: isSelected ? 2 : 1.5,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    d.displayName,
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? theme.accentPrimary
                                          : theme.textSecondary,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Start CTA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StartButton(
                onTap: () => _onStart(context),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Stepper Control ────────────────────────────────────────────────────────────

class _StepperControl extends ConsumerWidget {
  const _StepperControl({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return Row(
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          enabled: value > min,
          onTap: () => onChanged(value - 1),
          theme: theme,
        ),
        SizedBox(
          width: 40,
          child: Center(
            child: Text(
              '$value',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: theme.accentPrimary,
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          enabled: value < max,
          onTap: () => onChanged(value + 1),
          theme: theme,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.theme,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final dynamic theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? theme.accentPrimary.withValues(alpha: 0.15)
              : theme.backgroundMid,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled
                ? theme.accentPrimary.withValues(alpha: 0.6)
                : theme.accentDark.withValues(alpha: 0.25),
            width: 1.5,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? theme.accentPrimary
              : theme.textSecondary.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

// ── Start Button ───────────────────────────────────────────────────────────────

class _StartButton extends ConsumerWidget {
  const _StartButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

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
                  'Start Bust Game',
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
