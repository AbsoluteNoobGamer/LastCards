import '../core/models/card_model.dart';
import '../core/models/move_log_entry.dart';

/// Formats move log entries into compact hybrid text:
/// - Normal cards: rank + suit symbol (e.g. 8♠ 4♥)
/// - Joker: full descriptive text ("played Joker as A♠")
/// - Ace with declared suit: full text ("played A → ♥")
/// - Eight skips: full text ("played 8♠, skipped Mia")
/// - Draw: simple text ("drew 2 cards")
class GameLogFormatter {
  const GameLogFormatter._();

  /// Returns a compact icon string for a single card.
  /// Uses the effective suit/rank so Joker declared values are shown correctly.
  static String cardToIcon(CardModel card) {
    return '${card.effectiveRank.displayLabel}${card.effectiveSuit.symbol}';
  }

  /// Returns the action portion of the log entry (without the player name).
  /// The player name is rendered separately in a coloured span.
  static String formatMove(MoveLogEntry entry) {
    switch (entry.type) {
      case MoveLogEntryType.timeoutDraw:
        return 'timed out, drew ${_cardCountLabel(entry.drawCount)}';
      case MoveLogEntryType.draw:
        return 'drew ${_cardCountLabel(entry.drawCount)}';
      case MoveLogEntryType.invalidPlayDraw:
        return 'drew ${_cardCountLabel(entry.drawCount)} for invalid play';
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
    // Skip applies when the LAST card played was an Eight (regardless of what
    // came before it). A non-Eight played after an Eight cancels the skip, so
    // checking the last card is both necessary and sufficient.
    final isEightSkip = cards.last.card.effectiveRank == Rank.eight &&
        entry.skippedPlayerNames.isNotEmpty;
    // Long multi-card plays need extra lines so all cards are visible.
    final hasManyCards = cards.length > 6;
    return hasJoker || hasAceDeclaration || isEightSkip || hasManyCards;
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
        return 'played Joker as ${declaredRank.displayLabel}${declaredSuit.symbol}';
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
    // The skip applies whenever the LAST card played was an Eight —
    // whether it was a solo Eight or the tail of a mixed sequence.
    final endsOnEight = cards.last.card.effectiveRank == Rank.eight;
    if (endsOnEight && skipped.isNotEmpty) {
      final icons = cards.map((a) => cardToIcon(a.card)).join(' ');
      return 'played $icons, skipped ${_joinNames(skipped)}';
    }

    // NORMAL PLAY: compact icons, show all cards (no limit).
    final icons = cards.map((a) => cardToIcon(a.card)).join(' ');
    return 'played $icons';
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
