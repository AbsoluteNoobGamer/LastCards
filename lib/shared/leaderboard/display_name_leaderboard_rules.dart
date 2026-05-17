/// Rules for which display names may appear on leaderboards (client + server).
library;

/// Normalized key for uniqueness (case-insensitive, no spaces).
String normalizeLeaderboardDisplayNameKey(String name) {
  return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
}

/// Default / placeholder names that must not appear on leaderboards.
bool isDefaultOrReservedDisplayName(String name) {
  final key = normalizeLeaderboardDisplayNameKey(name);
  if (key.isEmpty) return true;
  const blocked = {
    'guest',
    'player',
    'player2',
    'player3',
    'player4',
    'noob1',
    'waiting',
    'you',
  };
  return blocked.contains(key);
}

/// True when [name] may be shown on leaderboards and persisted to stat docs.
bool isLeaderboardEligibleDisplayName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;
  return !isDefaultOrReservedDisplayName(trimmed);
}

/// Filters leaderboard rows: drops ineligible names and duplicate display names
/// (keeps the first / highest-ranked entry per normalized name).
List<T> filterLeaderboardEntriesForDisplay<T>(
  List<T> entries,
  String Function(T entry) displayName,
) {
  final seenKeys = <String>{};
  final out = <T>[];
  for (final e in entries) {
    final name = displayName(e);
    if (!isLeaderboardEligibleDisplayName(name)) continue;
    final key = normalizeLeaderboardDisplayNameKey(name);
    if (seenKeys.contains(key)) continue;
    seenKeys.add(key);
    out.add(e);
  }
  return out;
}
