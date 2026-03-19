import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local (device) leaderboard storage used as a fallback for offline mode
/// and to make leaderboard updates feel instant.
///
/// Remote leaderboard docs are stored in Firestore as well, but the app may
/// not have network access when the match ends.
class LocalLeaderboardEntry {
  const LocalLeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.wins,
    required this.losses,
    required this.gamesPlayed,
  });

  final String uid;
  final String displayName;
  final int wins;
  final int losses;
  final int gamesPlayed;
}

class LocalLeaderboardStore {
  LocalLeaderboardStore._();

  static final LocalLeaderboardStore instance = LocalLeaderboardStore._();

  static const String _prefsPrefix = 'leaderboard_local_entries_';

  String _prefsKey(String collectionName) =>
      '$_prefsPrefix${collectionName.trim()}';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<Map<String, LocalLeaderboardEntry>> _loadMap(
    String collectionName,
  ) async {
    final prefs = await _prefs();
    final raw = prefs.getString(_prefsKey(collectionName));
    if (raw == null || raw.isEmpty) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final entries = <String, LocalLeaderboardEntry>{};
    for (final e in decoded.entries) {
      final v = e.value as Map<String, dynamic>;
      entries[e.key] = LocalLeaderboardEntry(
        uid: e.key,
        displayName: v['displayName'] as String? ?? e.key,
        wins: (v['wins'] as num?)?.toInt() ?? 0,
        losses: (v['losses'] as num?)?.toInt() ?? 0,
        gamesPlayed: (v['gamesPlayed'] as num?)?.toInt() ?? 0,
      );
    }
    return entries;
  }

  Future<void> _saveMap(
    String collectionName,
    Map<String, LocalLeaderboardEntry> map,
  ) async {
    final prefs = await _prefs();
    final encoded = jsonEncode({
      for (final e in map.entries)
        e.key: {
          'displayName': e.value.displayName,
          'wins': e.value.wins,
          'losses': e.value.losses,
          'gamesPlayed': e.value.gamesPlayed,
        },
    });
    await prefs.setString(_prefsKey(collectionName), encoded);
  }

  Future<List<LocalLeaderboardEntry>> loadEntries(String collectionName) async {
    final map = await _loadMap(collectionName);
    final entries = map.values.toList(growable: false);
    entries.sort((a, b) => b.wins.compareTo(a.wins));
    return entries;
  }

  /// Increments local leaderboard stats for a single player.
  Future<void> incrementEntry({
    required String collectionName,
    required String uid,
    required String displayName,
    required int deltaWins,
    required int deltaLosses,
    required int deltaGamesPlayed,
  }) async {
    final map = await _loadMap(collectionName);
    final current = map[uid];
    final next = LocalLeaderboardEntry(
      uid: uid,
      displayName: displayName,
      wins: (current?.wins ?? 0) + deltaWins,
      losses: (current?.losses ?? 0) + deltaLosses,
      gamesPlayed: (current?.gamesPlayed ?? 0) + deltaGamesPlayed,
    );
    map[uid] = next;
    await _saveMap(collectionName, map);
  }
}

