import 'move_log_entry.dart';

/// Merges [playEntry] into the newest log line when it is the same player's
/// continued turn; otherwise prepends a new line. Keeps at most [maxEntries].
///
/// Used by offline [TableScreen], online card-play events, and Bust so the
/// move log shows one combined line per turn (multiple partial plays).
void mergeOrPrependPlayLog(
  List<MoveLogEntry> entries,
  MoveLogEntry playEntry, {
  int maxEntries = 3,
}) {
  assert(playEntry.type == MoveLogEntryType.play);
  if (entries.isNotEmpty) {
    final top = entries.first;
    if (top.type == MoveLogEntryType.play &&
        top.playerId == playEntry.playerId &&
        top.turnContinues) {
      entries[0] = top.copyWith(
        cardActions: [...top.cardActions, ...playEntry.cardActions],
        skippedPlayerNames: playEntry.skippedPlayerNames,
        turnContinues: playEntry.turnContinues,
      );
      return;
    }
  }
  entries.insert(0, playEntry);
  if (entries.length > maxEntries) {
    entries.removeRange(maxEntries, entries.length);
  }
}
