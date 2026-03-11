import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../bust/widgets/bust_setup_sheet.dart';
import '../../single_player/providers/single_player_session_provider.dart';
import '../providers/tournament_session_provider.dart';
import 'difficulty_selection_sheet.dart';
import 'player_count_sheet.dart';
import 'tournament_type_sheet.dart';

/// Bottom Sheet 2 — Sub-mode selection (Knockout vs Bust).
///
/// Shown after the user picks Single Player or Online in [TournamentTypeSheet].
/// Routes to the appropriate next sheet based on the combination of
/// [TournamentType] and [GameSubMode]:
///
/// | Sub-mode | vsAi                               | online                            |
/// |----------|------------------------------------|-----------------------------------|
/// | Knockout | [TournamentDifficultySelectionSheet]| [TournamentPlayerCountSheet]      |
/// | Bust     | [BustSetupSheet] (isOnline: false)  | [BustSetupSheet] (isOnline: true) |
class TournamentSubModeSheet extends ConsumerWidget {
  const TournamentSubModeSheet({required this.type, super.key});

  final TournamentType type;

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
                        type.displayName,
                        style: GoogleFonts.cinzel(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.accentPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Choose Game Mode',
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
            const SizedBox(height: 20),

            // Sub-mode cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: GameSubMode.values.map((subMode) {
                  // Online Bust isn't wired up yet — gate it behind Coming Soon.
                  final isComingSoon = subMode == GameSubMode.bust &&
                      type == TournamentType.online;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SubModeCard(
                      subMode: subMode,
                      isComingSoon: isComingSoon,
                      onTap: isComingSoon
                          ? null
                          : () => _onSubModeSelected(context, ref, subMode),
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

  void _goBack(BuildContext context) {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TournamentTypeSheet(),
    );
  }

  void _onSubModeSelected(
      BuildContext context, WidgetRef ref, GameSubMode subMode) {
    ref.read(tournamentSessionProvider.notifier).setSubMode(subMode);
    Navigator.of(context).pop();

    if (subMode == GameSubMode.bust) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => BustSetupSheet(
          isOnline: type == TournamentType.online,
        ),
      );
      return;
    }

    // Knockout path — route based on type
    if (type == TournamentType.vsAi) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const TournamentDifficultySelectionSheet(),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const TournamentPlayerCountSheet(),
      );
    }
  }
}

// ── Sub-mode card ─────────────────────────────────────────────────────────────

class _SubModeCard extends ConsumerStatefulWidget {
  const _SubModeCard({
    required this.subMode,
    required this.onTap,
    this.isComingSoon = false,
  });

  final GameSubMode subMode;
  final VoidCallback? onTap;
  final bool isComingSoon;

  @override
  ConsumerState<_SubModeCard> createState() => _SubModeCardState();
}

class _SubModeCardState extends ConsumerState<_SubModeCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final isComingSoon = widget.isComingSoon;

    return MouseRegion(
      onEnter: isComingSoon
          ? null
          : (_) => setState(() => _isHovered = true),
      onExit: isComingSoon
          ? null
          : (_) => setState(() {
                _isHovered = false;
                _isPressed = false;
              }),
      cursor:
          isComingSoon ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: Opacity(
        opacity: isComingSoon ? 0.5 : 1.0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: _isPressed ? 0.97 : (_isHovered ? 1.02 : 1.0),
          curve: Curves.easeOutCubic,
          child: GestureDetector(
            onTapDown:
                isComingSoon ? null : (_) => setState(() => _isPressed = true),
            onTapUp: isComingSoon
                ? null
                : (_) {
                    setState(() => _isPressed = false);
                    widget.onTap?.call();
                  },
            onTapCancel:
                isComingSoon ? null : () => setState(() => _isPressed = false),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                        widget.subMode.emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.subMode.displayName,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: theme.textPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (isComingSoon) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      theme.accentDark.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'COMING SOON',
                                  style: GoogleFonts.inter(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: theme.textSecondary,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subMode.description,
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
      ),
    );
  }
}
