import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../providers/online_session_provider.dart';
import '../screens/matchmaking_screen.dart';
import 'mode_selection_sheet.dart';

/// Bottom Sheet 2 — Player Count Selection
///
/// Shown after the user selects a game mode in [ModeSelectionSheet].
/// Lets the player pick 2, 3, or 4 players; then "Find Game" navigates
/// to [MatchmakingScreen].
class PlayerCountSheet extends ConsumerStatefulWidget {
  const PlayerCountSheet({super.key});

  @override
  ConsumerState<PlayerCountSheet> createState() => _PlayerCountSheetState();
}

class _PlayerCountSheetState extends ConsumerState<PlayerCountSheet> {
  int? _selectedCount;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final session = ref.watch(onlineSessionProvider);
    final modeLabel = session.mode?.displayName ?? 'Online';

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
            const SizedBox(height: 4),

            // ── Header row: back chevron + title ──────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Back button
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
                  // Title
                  Column(
                    children: [
                      Text(
                        modeLabel,
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

            // ── Player count cards (row) ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [2, 3, 4].map((count) {
                  final isSelected = _selectedCount == count;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: count == 2 ? 0 : 6,
                        right: count == 4 ? 0 : 6,
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
            ),

            const SizedBox(height: 24),

            // ── Find Game CTA ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _FindGameButton(
                isActive: _selectedCount != null,
                onTap: () => _onFindGame(context),
              ),
            ),

            const SizedBox(height: 20),
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
      builder: (_) => const ModeSelectionSheet(),
    );
  }

  void _onFindGame(BuildContext context) {
    if (_selectedCount == null) return;
    ref.read(onlineSessionProvider.notifier).setPlayerCount(_selectedCount!);
    Navigator.of(context).pop();
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
              ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

// ── Player Count Card ─────────────────────────────────────────────────────────

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

// ── Find Game Button ──────────────────────────────────────────────────────────

class _FindGameButton extends ConsumerWidget {
  const _FindGameButton({required this.isActive, required this.onTap});

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
                  Icons.search_rounded,
                  size: 20,
                  color: isActive
                      ? theme.backgroundDeep
                      : theme.textSecondary.withValues(alpha: 0.35),
                ),
                const SizedBox(width: 8),
                Text(
                  'Find Game',
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
