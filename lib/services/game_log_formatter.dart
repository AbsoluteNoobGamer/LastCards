import '../core/models/card_model.dart';
import '../core/models/move_log_entry.dart';

/// Formats move log entries into compact hybrid text:
/// - Normal cards: bold suit symbol + rank (e.g. ♠8 ♥4)
/// - Joker: full descriptive text ("played Joker as ♠A")
/// - Ace with declared suit: full text ("played A → ♥")
/// - Eight skips: full text ("played ♠8, skipped Mia")
/// - Draw: simple text ("drew 2 cards")
class GameLogFormatter {
  const GameLogFormatter._();

  /// Returns a compact icon string for a single card.
  /// Uses the effective suit/rank so Joker declared values are shown correctly.
  static String cardToIcon(CardModel card) {
    return '${card.effectiveSuit.symbol}${card.effectiveRank.displayLabel}';
  }

  /// Returns the action portion of the log entry (without the player name).
  /// The player name is rendered separately in a coloured span.
  static String formatMove(MoveLogEntry entry) {
    switch (entry.type) {
      case MoveLogEntryType.timeoutDraw:
        return 'timed out, drew ${_cardCountLabel(entry.drawCount)}';
      case MoveLogEntryType.draw:
        return 'drew ${_cardCountLabel(entry.drawCount)}';
      case MoveLogEntryType.play:
        return _formatPlay(entry);
    }
  }

  /// Whether this entry should be treated as a "special" move that needs
  /// [maxLines: 2] to avoid cropping critical information.
  static bool isSpecialEntry(MoveLogEntry entry) {
    if (entry.type != MoveLogEntryType.play) return false;
    final cards = entry.cardActions;
    if (cards.isEmpty) return false;
    final hasJoker = cards.any((a) => a.card.isJoker);
    final hasAceDeclaration = cards.any(
      (a) =>
          a.card.effectiveRank == Rank.ace && a.aceDeclaredSuit != null,
    );
    final isEightSkip = cards.every(
          (a) => a.card.effectiveRank == Rank.eight,
        ) &&
        entry.skippedPlayerNames.isNotEmpty;
    return hasJoker || hasAceDeclaration || isEightSkip;
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  static String _formatPlay(MoveLogEntry entry) {
    final cards = entry.cardActions;
    if (cards.isEmpty) return 'played a card';

    final skipped = entry.skippedPlayerNames;

    // JOKER: always full descriptive text.
    if (cards.any((a) => a.card.isJoker)) {
      final jokerAction = cards.firstWhere((a) => a.card.isJoker);
      final card = jokerAction.card;
      final declaredSuit = card.jokerDeclaredSuit;
      final declaredRank = card.jokerDeclaredRank;
      if (declaredSuit != null && declaredRank != null) {
        return 'played Joker as ${declaredSuit.symbol}${declaredRank.displayLabel}';
      }
      return 'played Joker';
    }

    // ACE with declared suit: always full descriptive text.
    final aceAction = cards
        .where(
          (a) =>
              a.card.effectiveRank == Rank.ace && a.aceDeclaredSuit != null,
        )
        .firstOrNull;
    if (aceAction != null) {
      return 'played A → ${aceAction.aceDeclaredSuit!.symbol}';
    }

    // EIGHT SKIP: always full text to preserve who was skipped.
    final allEights =
        cards.every((a) => a.card.effectiveRank == Rank.eight);
    if (allEights && skipped.isNotEmpty) {
      final icons = cards.map((a) => cardToIcon(a.card)).join(' ');
      return 'played $icons, skipped ${_joinNames(skipped)}';
    }

    // NORMAL PLAY: compact icons, max 3 shown then "+N more".
    final icons = cards.take(3).map((a) => cardToIcon(a.card)).join(' ');
    final extra = cards.length > 3 ? ' +${cards.length - 3}' : '';
    return 'played $icons$extra';
  }

  static String _cardCountLabel(int count) =>
      '$count ${count == 1 ? 'card' : 'cards'}';

  static String _joinNames(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names.first} & ${names.last}';
    return '${names.sublist(0, names.length - 1).join(', ')} & ${names.last}';
  }
}
