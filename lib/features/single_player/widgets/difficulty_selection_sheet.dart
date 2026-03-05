import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../providers/single_player_session_provider.dart';
import 'player_count_sheet.dart';

/// Bottom Sheet 1 — Difficulty Selection
///
/// Shows three large tappable option cards: Easy, Medium, Hard.
/// On selection, dismisses and opens [SPPlayerCountSheet].
class DifficultySelectionSheet extends ConsumerWidget {
  const DifficultySelectionSheet({super.key});

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
            // ── Drag handle ───────────────────────────────────────────────
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

            // ── Title ─────────────────────────────────────────────────────
            Text(
              'Choose Difficulty',
              style: GoogleFonts.cinzel(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: theme.accentPrimary,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How hard do you want the AI to play?',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: theme.textSecondary,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 24),

            // ── Difficulty Cards ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: AiDifficulty.values.map((difficulty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DifficultyCard(
                      difficulty: difficulty,
                      onTap: () =>
                          _onDifficultySelected(context, ref, difficulty),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _onDifficultySelected(
      BuildContext context, WidgetRef ref, AiDifficulty difficulty) {
    ref.read(singlePlayerSessionProvider.notifier).setDifficulty(difficulty);
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SPPlayerCountSheet(),
    );
  }
}

// ── Difficulty Option Card ────────────────────────────────────────────────────

class _DifficultyCard extends ConsumerStatefulWidget {
  const _DifficultyCard({required this.difficulty, required this.onTap});

  final AiDifficulty difficulty;
  final VoidCallback onTap;

  @override
  ConsumerState<_DifficultyCard> createState() => _DifficultyCardState();
}

class _DifficultyCardState extends ConsumerState<_DifficultyCard> {
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
                // Emoji icon in a circle badge
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
                      widget.difficulty.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.difficulty.displayName,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.difficulty.description,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.textSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),

                // Chevron
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
