import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../online/screens/matchmaking_screen.dart';
import '../providers/tournament_session_provider.dart';
import '../screens/tournament_lobby_screen.dart';
import 'player_count_sheet.dart';
import 'tournament_type_sheet.dart';

/// Bottom Sheet 4 (Single Player) / 3 (Online) — Format Selection
///
/// Gives standard or knockouts options.
/// Routes to either TournamentLobbyScreen or MatchmakingScreen.
class TournamentFormatSelectionSheet extends ConsumerStatefulWidget {
  const TournamentFormatSelectionSheet({super.key});

  @override
  ConsumerState<TournamentFormatSelectionSheet> createState() =>
      _TournamentFormatSelectionSheetState();
}

class _TournamentFormatSelectionSheetState
    extends ConsumerState<TournamentFormatSelectionSheet> {
  TournamentFormat? _selectedFormat = TournamentFormat.knockout;

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
                        'Format',
                        style: GoogleFonts.cinzel(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.accentPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Choose Format',
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

            // Format Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: TournamentFormat.values.map((format) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FormatCard(
                      format: format,
                      isSelected: _selectedFormat == format,
                      onTap: format.isComingSoon
                          ? null
                          : () => setState(() => _selectedFormat = format),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Start CTA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StartButton(
                isActive: _selectedFormat != null,
                onTap: () => _onStart(context),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _goBack(BuildContext context) {
    final session = ref.read(tournamentSessionProvider);
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => session.type == TournamentType.vsAi
          ? const TournamentPlayerCountSheet()
          : const TournamentTypeSheet(),
    );
  }

  void _onStart(BuildContext context) {
    if (_selectedFormat == null) return;
    ref.read(tournamentSessionProvider.notifier).setFormat(_selectedFormat!);
    final session = ref.read(tournamentSessionProvider);

    Navigator.of(context).pop(); // dismiss sheet

    // Route to correct destination based on tournament type
    final destination = session.type == TournamentType.vsAi
        ? const TournamentLobbyScreen()
        : const MatchmakingScreen();

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _FormatCard extends ConsumerStatefulWidget {
  const _FormatCard({
    required this.format,
    required this.isSelected,
    required this.onTap,
  });

  final TournamentFormat format;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  ConsumerState<_FormatCard> createState() => _FormatCardState();
}

class _FormatCardState extends ConsumerState<_FormatCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final isComingSoon = widget.format.isComingSoon;
    final isActive = !isComingSoon && (widget.isSelected || _isHovered);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor:
          isComingSoon ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: Opacity(
        opacity: isComingSoon ? 0.5 : 1.0,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? theme.accentPrimary.withValues(alpha: 0.15)
                  : (_isHovered && !isComingSoon
                      ? theme.accentPrimary.withValues(alpha: 0.08)
                      : theme.backgroundMid),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? theme.accentPrimary
                    : theme.accentDark.withValues(alpha: 0.4),
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
                  : (_isHovered && !isComingSoon
                      ? [
                          BoxShadow(
                            color: theme.accentPrimary.withValues(alpha: 0.06),
                            blurRadius: 12,
                            spreadRadius: 0,
                          ),
                        ]
                      : []),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? theme.accentPrimary.withValues(alpha: 0.2)
                        : theme.accentPrimary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.isSelected
                          ? theme.accentPrimary
                          : theme.accentPrimary.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.format.emoji,
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
                            widget.format.displayName,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: widget.isSelected
                                  ? theme.accentPrimary
                                  : theme.textPrimary,
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
                        widget.format.description,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.textSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: theme.accentPrimary,
                    size: 24,
                  ),
              ],
            ),
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
                  'Start Tournament',
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
