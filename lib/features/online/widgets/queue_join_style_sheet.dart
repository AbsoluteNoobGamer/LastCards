import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../providers/online_session_provider.dart';
import '../screens/matchmaking_screen.dart';
import 'mode_selection_sheet.dart';
import 'player_count_sheet.dart';

/// After picking Ranked or Ranked (Hardcore), choose Select table vs Quick match.
class QueueJoinStyleSheet extends ConsumerWidget {
  const QueueJoinStyleSheet({super.key});

  void _pickSelectTable(BuildContext context, WidgetRef ref) {
    ref.read(onlineSessionProvider.notifier).setQueueJoinStyle(
          OnlineQueueJoinStyle.selectTable,
        );
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PlayerCountSheet(),
    );
  }

  void _pickQuickMatch(BuildContext context, WidgetRef ref) {
    ref.read(onlineSessionProvider.notifier).setQueueJoinStyle(
          OnlineQueueJoinStyle.joinWaitingQueue,
        );
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

  void _goBack(BuildContext context) {
    Navigator.of(context).pop();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ModeSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final tier = ref.watch(onlineSessionProvider).mode;

    final title = tier?.displayName ?? 'Online';

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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                        title,
                        style: GoogleFonts.cinzel(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.accentPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'How do you want to join?',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                children: [
                  _JoinStyleCard(
                    emoji: '🪑',
                    label: 'Select table',
                    description:
                        'Choose 2–7 players, then open a table at that size',
                    onTap: () => _pickSelectTable(context, ref),
                  ),
                  const SizedBox(height: 12),
                  _JoinStyleCard(
                    emoji: '⚡',
                    label: 'Quick match',
                    description:
                        'Jump into any open table already waiting for players',
                    onTap: () => _pickQuickMatch(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinStyleCard extends ConsumerStatefulWidget {
  const _JoinStyleCard({
    required this.emoji,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  ConsumerState<_JoinStyleCard> createState() => _JoinStyleCardState();
}

class _JoinStyleCardState extends ConsumerState<_JoinStyleCard> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _pressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          scale: _pressed ? 0.98 : (_hover ? 1.02 : 1.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: _hover
                  ? theme.accentPrimary.withValues(alpha: 0.08)
                  : theme.backgroundMid,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hover
                    ? theme.accentPrimary.withValues(alpha: 0.7)
                    : theme.accentDark.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Text(widget.emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.textPrimary,
                        ),
                      ),
                      Text(
                        widget.description,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.accentPrimary.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
