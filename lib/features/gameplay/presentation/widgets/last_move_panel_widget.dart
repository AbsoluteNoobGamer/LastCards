import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/card_model.dart';
import '../../../../core/models/move_log_entry.dart';
import '../../../../core/providers/theme_provider.dart';

String formatMoveLogEntry(MoveLogEntry entry) {
  switch (entry.type) {
    case MoveLogEntryType.timeoutDraw:
      return '${entry.playerName} timed out and drew ${_cardCountLabel(entry.drawCount)}';
    case MoveLogEntryType.draw:
      return '${entry.playerName} drew ${_cardCountLabel(entry.drawCount)}';
    case MoveLogEntryType.play:
      final cards = entry.cardActions;
      if (cards.isEmpty) return '${entry.playerName} played a card';
      final skipped = entry.skippedPlayerNames;
      final allEights = cards.every((a) => a.card.effectiveRank == Rank.eight);

      if (allEights && skipped.isNotEmpty) {
        return '${entry.playerName} played ${cards.length} ${cards.length == 1 ? 'Eight' : 'Eights'} and skipped ${_joinNames(skipped)}';
      }

      if (cards.length == 1) {
        final cardText = _describeCardAction(cards.first);
        if (skipped.length == 1) {
          return '${entry.playerName} played $cardText, so ${skipped.first} missed their turn';
        }
        if (skipped.isNotEmpty) {
          return '${entry.playerName} played $cardText and skipped ${_joinNames(skipped)}';
        }
        return '${entry.playerName} played $cardText';
      }

      final ordered = cards.map(_describeCardAction).join(', ');
      var text = '${entry.playerName} played ${cards.length} cards: $ordered';
      if (skipped.isNotEmpty) {
        text = '$text and skipped ${_joinNames(skipped)}';
      }
      return text;
  }
}

String _describeCardAction(MoveCardAction action) {
  final card = action.card;
  if (card.isJoker) {
    final rank = card.jokerDeclaredRank;
    final suit = card.jokerDeclaredSuit;
    if (rank != null && suit != null) {
      return 'Joker as ${_rankName(rank)} of ${suit.displayName}';
    }
    return 'Joker';
  }

  if (card.effectiveRank == Rank.ace && action.aceDeclaredSuit != null) {
    return 'Ace and changed suit to ${action.aceDeclaredSuit!.displayName}';
  }

  return '${_rankName(card.effectiveRank)} of ${card.effectiveSuit.displayName}';
}

String _rankName(Rank rank) {
  return switch (rank) {
    Rank.jack => 'Jack',
    Rank.queen => 'Queen',
    Rank.king => 'King',
    Rank.ace => 'Ace',
    Rank.joker => 'Joker',
    _ => rank.numericValue.toString(),
  };
}

String _joinNames(List<String> names) {
  if (names.length <= 1) return names.first;
  if (names.length == 2) return '${names.first} and ${names.last}';
  return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
}

String _cardCountLabel(int count) {
  return '$count ${count == 1 ? 'card' : 'cards'}';
}

/// Displays the latest three move log entries (newest first).
class LastMovePanelWidget extends StatelessWidget {
  const LastMovePanelWidget({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries.take(3).toList(growable: false);
    if (visibleEntries.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 108),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in visibleEntries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _MoveLabel(text: formatMoveLogEntry(entry)),
              ),
          ],
        ),
      ),
    );
  }

  final List<MoveLogEntry> entries;
}

class _MoveLabel extends ConsumerWidget {
  const _MoveLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.surfacePanel.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: theme.accentLight,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
