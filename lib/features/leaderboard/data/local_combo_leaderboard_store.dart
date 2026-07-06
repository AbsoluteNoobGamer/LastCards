import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:last_cards/core/models/card_model.dart';

/// A player's best-ever combo (most cards played in a single turn), plus the
/// actual hand that produced it.
class ComboLeaderboardEntry {
  const ComboLeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.comboCount,
    required this.cards,
    required this.achievedAtMillis,
  });

  final String uid;
  final String displayName;
  final int comboCount;

  /// The cards played, in play order — what actually made up the combo.
  final List<CardModel> cards;

  final int achievedAtMillis;
}

/// Local (device) storage for the combo-record leaderboard — instant UI and
/// an offline-friendly fallback, mirroring [LocalLeaderboardStore]'s pattern
/// but tracking a single best record per player instead of incrementing
/// counters.
class LocalComboLeaderboardStore {
  LocalComboLeaderboardStore._();

  static final LocalComboLeaderboardStore instance =
      LocalComboLeaderboardStore._();

  static const String _prefsKey = 'leaderboard_local_combo_entries';

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<Map<String, ComboLeaderboardEntry>> _loadMap() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final entries = <String, ComboLeaderboardEntry>{};
      for (final e in decoded.entries) {
        final v = e.value as Map<String, dynamic>;
        final cardsJson = (v['cards'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        entries[e.key] = ComboLeaderboardEntry(
          uid: e.key,
          displayName: v['displayName'] as String? ?? e.key,
          comboCount: (v['comboCount'] as num?)?.toInt() ?? 0,
          cards: cardsJson.map(CardModel.fromJson).toList(),
          achievedAtMillis: (v['achievedAtMillis'] as num?)?.toInt() ?? 0,
        );
      }
      return entries;
    } catch (_) {
      // Corrupt/legacy payload — treat as empty rather than crash.
      return {};
    }
  }

  Future<void> _saveMap(Map<String, ComboLeaderboardEntry> map) async {
    final prefs = await _prefs();
    final encoded = jsonEncode({
      for (final e in map.entries)
        e.key: {
          'displayName': e.value.displayName,
          'comboCount': e.value.comboCount,
          'cards': e.value.cards.map((c) => c.toJson()).toList(),
          'achievedAtMillis': e.value.achievedAtMillis,
        },
    });
    await prefs.setString(_prefsKey, encoded);
  }

  /// All recorded entries, ranked by combo count descending.
  Future<List<ComboLeaderboardEntry>> loadEntries() async {
    final map = await _loadMap();
    final entries = map.values.toList(growable: false);
    entries.sort((a, b) => b.comboCount.compareTo(a.comboCount));
    return entries;
  }

  Future<ComboLeaderboardEntry?> loadEntryForUser(String uid) async {
    final map = await _loadMap();
    return map[uid];
  }

  /// Updates the stored record for [uid] only if [comboCount] beats the
  /// existing one. Returns the resulting entry (new or unchanged) and
  /// whether this call actually set a new record.
  Future<(ComboLeaderboardEntry entry, bool isNewRecord)> recordIfBest({
    required String uid,
    required String displayName,
    required int comboCount,
    required List<CardModel> cards,
    required int achievedAtMillis,
  }) async {
    final map = await _loadMap();
    final current = map[uid];
    if (current != null && current.comboCount >= comboCount) {
      return (current, false);
    }
    final next = ComboLeaderboardEntry(
      uid: uid,
      displayName: displayName,
      comboCount: comboCount,
      cards: cards,
      achievedAtMillis: achievedAtMillis,
    );
    map[uid] = next;
    await _saveMap(map);
    return (next, true);
  }
}
