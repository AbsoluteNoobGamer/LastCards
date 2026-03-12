import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../providers/tournament_session_provider.dart';
import 'difficulty_selection_sheet.dart';
import 'format_selection_sheet.dart';
import 'tournament_sub_mode_sheet.dart';

/// Bottom Sheet 3 — Player Count Selection
///
/// Shown after difficulty or player setup.
/// Lets the player pick 3–7 players (no 2 player option for tournament).
class TournamentPlayerCountSheet extends ConsumerStatefulWidget {
  const TournamentPlayerCountSheet({super.key});

  @override
  ConsumerState<TournamentPlayerCountSheet> createState() =>
      _TournamentPlayerCountSheetState();
}

class _TournamentPlayerCountSheetState
    extends ConsumerState<TournamentPlayerCountSheet> {
  int? _selectedCount;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final session = ref.watch(tournamentSessionProvider);

    final typeLabel = session.type?.displayName ?? 'Tournament';
    final diffLabel = session.difficulty?.displayName;
    final titlePrefix = session.type == TournamentType.vsAi && diffLabel != null
        ? '$diffLabel $typeLabel'
        : typeLabel;

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
                      onPressed: () => _goBack(context, session),
                      tooltip: 'Back',
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        titlePrefix,
                        style: GoogleFonts.cinzel(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.accentPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Select Players',
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

            // 3–7 players cards (two rows: 3–4–5, then 6–7)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [3, 4, 5].map((count) {
                      final isSelected = _selectedCount == count;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: count == 3 ? 0 : 8,
                            right: count == 5 ? 0 : 8,
                          ),
                          child: _PlayerCountCard(
                            count: count,
                            isSelected: isSelected,
                            onTap: () => setState(() => _selectedCount = count),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [6, 7].map((count) {
                      final isSelected = _selectedCount == count;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: count == 6 ? 0 : 8,
                            right: count == 7 ? 0 : 8,
                          ),
                          child: _PlayerCountCard(
                            count: count,
                            isSelected: isSelected,
                            onTap: () => setState(() => _selectedCount = count),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Continue CTA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StartButton(
                isActive: _selectedCount != null,
                onTap: () => _onContinue(context),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _goBack(BuildContext context, TournamentSessionState session) {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        if (session.type == TournamentType.vsAi) {
          return const TournamentDifficultySelectionSheet();
        } else {
          // Online knockout: go back to sub-mode sheet so user can switch
          // between Knockout and Bust without restarting the whole flow.
          return TournamentSubModeSheet(type: TournamentType.online);
        }
      },
    );
  }

  void _onContinue(BuildContext context) {
    if (_selectedCount == null) return;
    ref
        .read(tournamentSessionProvider.notifier)
        .setPlayerCount(_selectedCount!);
    Navigator.of(context).pop();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TournamentFormatSelectionSheet(),
    );
  }
}

class _PlayerCountCard extends ConsumerStatefulWidget {
  const _PlayerCountCard({
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  ConsumerState<_PlayerCountCard> createState() => _PlayerCountCardState();
}

class _PlayerCountCardState extends ConsumerState<_PlayerCountCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final isActive = widget.isSelected || _isHovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 100,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? theme.accentPrimary.withValues(alpha: 0.15)
                : theme.backgroundMid,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? theme.accentPrimary
                  : theme.accentDark.withValues(alpha: 0.3),
              width: widget.isSelected ? 2 : 1.5,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: theme.accentPrimary.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.outfit(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: widget.isSelected
                      ? theme.accentPrimary
                      : theme.textSecondary.withValues(alpha: 0.5),
                ),
                child: Text('${widget.count}'),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: widget.isSelected
                      ? theme.accentPrimary.withValues(alpha: 0.8)
                      : theme.textSecondary.withValues(alpha: 0.4),
                  letterSpacing: 0.5,
                ),
                child: const Text('Players'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartButton extends ConsumerWidget {
  const _StartButton({required this.isActive, required this.onTap});

  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: isActive
            ? LinearGradient(
                colors: [theme.accentLight, theme.accentPrimary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isActive ? null : theme.backgroundMid,
        border: Border.all(
          color: isActive
              ? theme.accentPrimary
              : theme.accentDark.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: theme.accentPrimary.withValues(alpha: 0.30),
                  blurRadius: 16,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: isActive ? onTap : null,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  size: 22,
                  color: isActive
                      ? theme.backgroundDeep
                      : theme.textSecondary.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 8),
                Text(
                  'Continue',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? theme.backgroundDeep
                        : theme.textSecondary.withValues(alpha: 0.35),
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
