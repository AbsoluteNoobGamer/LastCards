import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/move_log_entry.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../services/game_log_formatter.dart';

/// Displays the latest three move log entries (newest first).
///
/// Player names use the first word only; if that word is longer than 17
/// characters it is shortened to half its length plus an ellipsis. Each name is
/// tinted with a deterministic accent colour.
/// Move text uses hybrid formatting: compact icons for normal cards, full
/// descriptive text for Joker / Ace / Eight-skip plays.
class LastMovePanelWidget extends StatelessWidget {
  const LastMovePanelWidget({super.key, required this.entries});

  final List<MoveLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries.take(3).toList(growable: false);
    if (visibleEntries.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < visibleEntries.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: TweenAnimationBuilder<double>(
              key: ValueKey(
                '${visibleEntries[i].playerId}_${visibleEntries[i].type}_${GameLogFormatter.formatMove(visibleEntries[i])}',
              ),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(20 * (1 - t), 0),
                  child: child,
                ),
              ),
              child: _MoveLabel(entry: visibleEntries[i]),
            ),
          ),
      ],
    );
  }
}

class _MoveLabel extends ConsumerWidget {
  const _MoveLabel({required this.entry});

  final MoveLogEntry entry;

  /// A palette of distinct, readable colours for player name highlights.
  static const _nameColors = <Color>[
    Color(0xFF64B5F6), // sky blue
    Color(0xFF81C784), // mint green
    Color(0xFFFFB74D), // amber
    Color(0xFFCE93D8), // lavender
    Color(0xFFFF8A65), // coral
    Color(0xFF4DD0E1), // teal
  ];

  Color _playerColor(String playerId) {
    final hash = playerId.codeUnits.fold(0, (sum, c) => sum + c);
    return _nameColors[hash % _nameColors.length];
  }

  /// Shortens a display name to its first word. Up to 17 characters shown in
  /// full; longer first words use the first half of the string plus an ellipsis.
  static String _shortName(String fullName) {
    final first = fullName.split(' ').first;
    if (first.length <= 17) return first;
    final half = first.length ~/ 2;
    return '${first.substring(0, half)}…';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final actionText = GameLogFormatter.formatMove(entry);
    final isSpecial = GameLogFormatter.isSpecialEntry(entry);
    final nameColor = _playerColor(entry.playerId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: RichText(
        maxLines: isSpecial ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: _shortName(entry.playerName),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: nameColor,
              ),
            ),
            TextSpan(
              text: ' $actionText',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
