import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CardBackDesign {
  const CardBackDesign({
    required this.id,
    required this.label,
    required this.unlockWins,
  });

  final String id;
  final String label;
  final int unlockWins;
}

class CardBackService {
  CardBackService._();

  static final CardBackService instance = CardBackService._();

  static const String _prefsSelectedKey = 'card_back_selected';
  static const String _prefsUnlockedKey = 'card_back_unlocked';
  static const String _prefsWinsKey = 'card_back_total_wins';
  static const String _prefsAnimatedEffectsKey = 'card_back_animated_effects';
  static const Set<String> _builtInAnimatedNames = {
    'classic.gif',
    'obsidian.gif',
    'ruby.gif',
    'royal.gif',
  };

  static const List<CardBackDesign> designs = [
    CardBackDesign(id: 'classic', label: 'Classic', unlockWins: 0),
    CardBackDesign(id: 'obsidian', label: 'Obsidian', unlockWins: 3),
    CardBackDesign(id: 'ruby', label: 'Ruby', unlockWins: 8),
    CardBackDesign(id: 'royal', label: 'Royal', unlockWins: 15),
  ];

  final ValueNotifier<String> selectedDesignId = ValueNotifier<String>('classic');
  final ValueNotifier<bool> animatedEffectsEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<String?> uploadedAnimatedAssetPath =
      ValueNotifier<String?>(null);

  bool _initialized = false;
  int _totalWins = 0;
  Set<String> _unlocked = <String>{'classic'};

  int get totalWins => _totalWins;
  Set<String> get unlockedDesigns => _unlocked;

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final selected = prefs.getString(_prefsSelectedKey) ?? 'classic';
    final unlockedRaw = prefs.getString(_prefsUnlockedKey);
    final wins = prefs.getInt(_prefsWinsKey) ?? 0;
    final animated = prefs.getBool(_prefsAnimatedEffectsKey) ?? true;

    _totalWins = wins;
    animatedEffectsEnabled.value = animated;
    uploadedAnimatedAssetPath.value = await _findUploadedAnimatedAsset();
    _unlocked = unlockedRaw == null || unlockedRaw.trim().isEmpty
        ? <String>{'classic'}
        : unlockedRaw
            .split(',')
            .where((entry) => entry.trim().isNotEmpty)
            .toSet();
    _unlocked.add('classic');
    // Temporary testing mode: unlock all card backs.
    _unlocked.addAll(designs.map((d) => d.id));

    if (_unlocked.contains(selected)) {
      selectedDesignId.value = selected;
    } else {
      selectedDesignId.value = 'classic';
    }
    _initialized = true;
  }

  bool isUnlocked(String designId) => _unlocked.contains(designId);

  Future<bool> selectDesign(String designId) async {
    await init();
    if (designId == 'uploaded' && uploadedAnimatedAssetPath.value == null) {
      return false;
    }
    if (designId != 'uploaded' && !_unlocked.contains(designId)) return false;
    if (selectedDesignId.value == designId) return true;
    selectedDesignId.value = designId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSelectedKey, designId);
    return true;
  }

  Future<void> setAnimatedEffectsEnabled(bool enabled) async {
    await init();
    animatedEffectsEnabled.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAnimatedEffectsKey, enabled);
  }

  Future<String?> _findUploadedAnimatedAsset() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAnimated = manifest
          .listAssets()
          .where((path) => path.startsWith('assets/animated_cards/'))
          .where((path) => path.toLowerCase().endsWith('.gif'))
          .toList(growable: false);
      for (final assetPath in allAnimated) {
        final filename = assetPath.split('/').last.toLowerCase();
        if (!_builtInAnimatedNames.contains(filename)) {
          return assetPath;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> registerWin() async {
    await init();
    _totalWins += 1;
    var unlockedChanged = false;

    for (final design in designs) {
      if (_totalWins >= design.unlockWins && !_unlocked.contains(design.id)) {
        _unlocked.add(design.id);
        unlockedChanged = true;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsWinsKey, _totalWins);
    if (unlockedChanged) {
      await prefs.setString(_prefsUnlockedKey, _unlocked.join(','));
    }
  }
}
