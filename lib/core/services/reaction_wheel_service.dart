import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/reactions/reaction_catalog.dart';

/// Local persistence for the 13-slot reaction wheel (catalog indices per slot).
class ReactionWheelService {
  ReactionWheelService._();
  static final ReactionWheelService instance = ReactionWheelService._();

  static const _prefsKey = 'reaction_wheel_slots_v1';

  List<int> _defaultSlots() =>
      List<int>.generate(kStarterReactionCount, (i) => i);

  /// Clamp [candidate] IDs to catalog range; replace locked reactions with starters.
  List<int> sanitizeForLevel(List<int>? candidate, int playerLevel) {
    final unlocked = unlockedReactionIndicesForLevel(playerLevel).toSet();
    final starter = List<int>.generate(kStarterReactionCount, (i) => i);
    List<int> src;
    if (candidate == null || candidate.length != kStarterReactionCount) {
      src = _defaultSlots();
    } else {
      src = List<int>.from(candidate);
    }
    for (var s = 0; s < kStarterReactionCount; s++) {
      final id = src[s];
      if (!isValidReactionWireIndex(id) || !unlocked.contains(id)) {
        src[s] = starter[s];
      }
    }
    return src;
  }

  Future<List<int>> loadSlots() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return _defaultSlots();
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      if (decoded.length != kStarterReactionCount) return _defaultSlots();
      return decoded.map((e) => (e as num).toInt()).toList();
    } catch (_) {
      return _defaultSlots();
    }
  }

  Future<void> saveSlots(List<int> slots) async {
    if (slots.length != kStarterReactionCount) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(slots));
  }
}
