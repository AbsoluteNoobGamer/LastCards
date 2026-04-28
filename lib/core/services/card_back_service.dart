import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';
import 'firestore_profile_service.dart';
import 'player_level_service.dart';

class CardBackDesign {
  const CardBackDesign({
    required this.id,
    required this.label,
    this.unlockLevel = 1,
    this.assetPath,
  });

  final String id;
  final String label;
  final int unlockLevel;

  /// If set, this design is a cardbackcover image at this asset path.
  final String? assetPath;
}

class CardBackService {
  CardBackService._();

  static final CardBackService instance = CardBackService._();

  static const String _prefsSelectedKey = 'card_back_selected';
  static const String _prefsUnlockedKey = 'card_back_unlocked';
  static const String _prefsAnimatedEffectsKey = 'card_back_animated_effects';
  static const String _prefsJokerCoverKey = 'joker_cover_selected';
  static const String _prefsCardFaceSetKey = 'card_face_set';
  static const String _cardBackCoverPrefix = 'assets/images/cardbackcover/';
  static const String _cardFacePrefix = 'assets/images/cardfaces/';

  /// Default card back when no preference is saved.
  static const String _defaultCardBackId = 'assets/images/cardbackcover/Purple Complex.png';
  static const String _jokerCoverPrefix = 'assets/images/jokercover/';
  static const String _animatedCardsPrefix = 'assets/animated_cards/';
  static const Set<String> _builtInAnimatedNames = {
    'classic.gif',
    'obsidian.gif',
    'ruby.gif',
    'royal.gif',
  };

  /// Assign custom display names for cardbackcover files (filename → label).
  /// Only the filename is used as key, e.g. 'card_back.png', 'NoobGamer Back.jpg'.
  /// If a file is not in this map, the label is derived from the filename.
  static const Map<String, String> cardBackCoverDisplayNames = {
    'two lions.png': 'Two Lions',
    'NoobGamer Back.jpg': 'NoobGamer',
  };

  static const List<CardBackDesign> designs = [
    CardBackDesign(id: 'classic', label: 'Classic', unlockLevel: 1),
    CardBackDesign(id: 'obsidian', label: 'Obsidian', unlockLevel: 3),
    CardBackDesign(id: 'ruby', label: 'Ruby', unlockLevel: 7),
    CardBackDesign(id: 'royal', label: 'Royal', unlockLevel: 12),
  ];

  final ValueNotifier<String> selectedDesignId =
      ValueNotifier<String>(_defaultCardBackId);
  final ValueNotifier<bool> animatedEffectsEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<String?> uploadedAnimatedAssetPath =
      ValueNotifier<String?>(null);
  final ValueNotifier<List<CardBackDesign>> animatedGifDesigns =
      ValueNotifier<List<CardBackDesign>>([]);
  final ValueNotifier<List<CardBackDesign>> cardBackCoverDesigns =
      ValueNotifier<List<CardBackDesign>>([]);
  final ValueNotifier<String> selectedJokerCoverId =
      ValueNotifier<String>('classic');
  final ValueNotifier<List<CardBackDesign>> jokerCoverDesigns =
      ValueNotifier<List<CardBackDesign>>([]);
  final ValueNotifier<String> selectedCardFaceSetId =
      ValueNotifier<String>('default');

  bool _initialized = false;
  Set<String> _unlocked = <String>{'classic'};

  Set<String> get unlockedDesigns => _unlocked;

  static String _labelFromFilename(String filename) {
    final name = cardBackCoverDisplayNames[filename];
    if (name != null && name.isNotEmpty) return name;
    return filename
        .replaceAll(RegExp(r'\.[^.]+$'), '')
        .replaceAll('_', ' ')
        .trim();
  }

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    await PlayerLevelService.instance.init();
    final selected = prefs.getString(_prefsSelectedKey) ?? _defaultCardBackId;
    final unlockedRaw = prefs.getString(_prefsUnlockedKey);
    final animatedEnabled = prefs.getBool(_prefsAnimatedEffectsKey) ?? true;

    animatedEffectsEnabled.value = animatedEnabled;
    animatedGifDesigns.value = await _loadAnimatedGifDesigns();
    uploadedAnimatedAssetPath.value = await _findUploadedAnimatedAsset();
    cardBackCoverDesigns.value = await _loadCardBackCoverDesigns();
    jokerCoverDesigns.value = await _loadJokerCoverDesigns();
    _unlocked = _unlockedDesignsForLevel(PlayerLevelService.instance.currentLevel.value);

    // Ensure prefs are consistent with level-based unlocking (and migrate
    // away from any legacy/unrelated unlocked state).
    final computedUnlocked = _unlocked.join(',');
    if (unlockedRaw == null || unlockedRaw.trim().isEmpty || unlockedRaw != computedUnlocked) {
      await prefs.setString(_prefsUnlockedKey, computedUnlocked);
    }

    final covers = cardBackCoverDesigns.value;
    final animatedGifs = animatedGifDesigns.value;
    final currentLevel = PlayerLevelService.instance.currentLevel.value;
    final isValidSelected = _unlocked.contains(selected) ||
        covers.any((d) => d.id == selected) ||
        animatedGifs.any((d) => d.id == selected && currentLevel >= d.unlockLevel);
    if (isValidSelected) {
      selectedDesignId.value = selected;
    } else {
      // Saved path no longer exists (e.g. file renamed) — use first cover or classic
      selectedDesignId.value = covers.isNotEmpty ? covers.first.id : 'classic';
      await prefs.setString(_prefsSelectedKey, selectedDesignId.value);
    }

    const defaultJokerId = 'assets/images/jokercover/Red Joker.png';
    final jokerSelected =
        prefs.getString(_prefsJokerCoverKey) ?? defaultJokerId;
    final jokerCovers = jokerCoverDesigns.value;

    CardBackDesign? selectedDesign;
    if (jokerSelected != 'classic') {
      for (final d in jokerCovers) {
        if (d.id == jokerSelected) {
          selectedDesign = d;
          break;
        }
      }
    }

    final isValidAndUnlockedJoker = jokerSelected == 'classic' ||
        (selectedDesign != null && currentLevel >= selectedDesign.unlockLevel);

    selectedJokerCoverId.value = isValidAndUnlockedJoker
        ? jokerSelected
        : (jokerCovers.isNotEmpty ? 'classic' : 'classic');
    if (!isValidAndUnlockedJoker) {
      await prefs.setString(_prefsJokerCoverKey, selectedJokerCoverId.value);
    }

    final cardFaceSet = prefs.getString(_prefsCardFaceSetKey) ?? 'default';
    selectedCardFaceSetId.value =
        (cardFaceSet == 'classic' || cardFaceSet == 'default')
            ? cardFaceSet
            : 'default';

    _initialized = true;

    // Keep unlock state in sync as levels change.
    PlayerLevelService.instance.currentLevel.addListener(() {
      final nextLevel = PlayerLevelService.instance.currentLevel.value;
      final nextUnlocked = _unlockedDesignsForLevel(nextLevel);
      if (_setsEqual(_unlocked, nextUnlocked)) return;

      _unlocked = nextUnlocked;
      unawaited(() async {
        final latestPrefs = await SharedPreferences.getInstance();
        await latestPrefs.setString(_prefsUnlockedKey, _unlocked.join(','));
      }());
    });
  }

  /// Returns the asset path for a card face when using a custom face set, or null for classic.
  static String? cardFaceAssetPathFor(String faceSetId, Rank rank, Suit suit) {
    if (faceSetId != 'default' || rank == Rank.joker) return null;
    return '$_cardFacePrefix$faceSetId/${rank.name}_${suit.name}.png';
  }

  Future<bool> selectCardFaceSet(String faceSetId) async {
    await init();
    if (faceSetId != 'classic' && faceSetId != 'default') return false;
    if (selectedCardFaceSetId.value == faceSetId) return true;
    selectedCardFaceSetId.value = faceSetId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCardFaceSetKey, faceSetId);
    unawaited(_pushCardCustomizationToFirestore());
    return true;
  }

  Future<void> _pushCardCustomizationToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirestoreProfileService().updateCardStyleSelections(
        uid,
        cardBackSelectedId: selectedDesignId.value,
        jokerCoverSelectedId: selectedJokerCoverId.value,
        cardFaceSetId: selectedCardFaceSetId.value,
      );
    } catch (_) {
      // Offline or rules rejection — local prefs remain source of truth.
    }
  }

  Future<List<CardBackDesign>> _loadJokerCoverDesigns() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest
          .listAssets()
          .where((path) => path.startsWith(_jokerCoverPrefix))
          .where((path) {
        final lower = path.toLowerCase();
        return lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg');
      }).toList()
        ..sort();
      return paths
          .map((path) => CardBackDesign(
                id: path,
                label: _labelFromFilename(path.split('/').last),
                assetPath: path,
                unlockLevel: _unlockLevelForJokerCoverPath(path),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static int _unlockLevelForJokerCoverPath(String assetPath) {
    final filename = assetPath.split('/').last.toLowerCase();
    // Keep the most common jokers together so "Red Joker" and "Black Joker"
    // don't diverge accidentally.
    if (filename.contains('red joker') || filename.contains('black joker')) {
      return 3;
    }

    // Default: harder than the base classic joker cover.
    return 5;
  }

  Future<List<CardBackDesign>> _loadCardBackCoverDesigns() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest
          .listAssets()
          .where((path) => path.startsWith(_cardBackCoverPrefix))
          .where((path) {
        final lower = path.toLowerCase();
        return lower.endsWith('.png') ||
            lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg');
      }).toList()
        ..sort();
      return paths
          .map((path) => CardBackDesign(
                id: path,
                label: _labelFromFilename(path.split('/').last),
                assetPath: path,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<CardBackDesign>> _loadAnimatedGifDesigns() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final paths = manifest
          .listAssets()
          .where((path) => path.startsWith(_animatedCardsPrefix))
          .where((path) => path.toLowerCase().endsWith('.gif'))
          .toList()
        ..sort();
      return paths
          .map((path) => CardBackDesign(
                id: path,
                label: _labelFromFilename(path.split('/').last),
                unlockLevel: _unlockLevelForAnimatedGif(path.split('/').last),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static int _unlockLevelForAnimatedGif(String filename) {
    return switch (filename.toLowerCase()) {
      'classic.gif' => 1,
      'obsidian.gif' => 5,
      'ruby.gif' => 10,
      'royal.gif' => 16,
      _ => 8,
    };
  }

  bool isUnlocked(String designId) => _unlocked.contains(designId);

  bool _isDesignUnlocked(String designId) {
    // Built-in animated card backs unlock purely by level.
    for (final design in designs) {
      if (design.id == designId) {
        final level = PlayerLevelService.instance.currentLevel.value;
        return level >= design.unlockLevel;
      }
    }

    // Fallback to persisted unlock set.
    return _unlocked.contains(designId);
  }

  Future<bool> selectDesign(String designId) async {
    await init();
    if (designId == 'uploaded' && uploadedAnimatedAssetPath.value == null) {
      return false;
    }
    if (designId != 'uploaded') {
      // Static cover images are freely accessible (file-based, no level gate).
      final isCover = cardBackCoverDesigns.value.any((d) => d.id == designId);
      if (!isCover) {
        // Check animated GIFs with level gating.
        final gif = animatedGifDesigns.value
            .where((d) => d.id == designId)
            .firstOrNull;
        if (gif != null) {
          final currentLevel = PlayerLevelService.instance.currentLevel.value;
          if (currentLevel < gif.unlockLevel) return false;
        } else if (!_isDesignUnlocked(designId)) {
          return false;
        }
      }
    }
    if (selectedDesignId.value == designId) return true;
    selectedDesignId.value = designId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSelectedKey, designId);
    unawaited(_pushCardCustomizationToFirestore());
    return true;
  }

  Future<bool> selectJokerCover(String designId) async {
    await init();
    if (designId != 'classic') {
      CardBackDesign? design;
      for (final d in jokerCoverDesigns.value) {
        if (d.id == designId) {
          design = d;
          break;
        }
      }
      if (design == null) return false;

      final currentLevel = PlayerLevelService.instance.currentLevel.value;
      if (currentLevel < design.unlockLevel) return false;
    }
    if (selectedJokerCoverId.value == designId) return true;
    selectedJokerCoverId.value = designId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsJokerCoverKey, designId);
    unawaited(_pushCardCustomizationToFirestore());
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
          .where((path) => path.startsWith(_animatedCardsPrefix))
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

  static bool _setsEqual(Set<String> a, Set<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }

  Set<String> _unlockedDesignsForLevel(int currentLevel) {
    final unlocked = <String>{'classic'};
    for (final design in designs) {
      if (currentLevel >= design.unlockLevel) {
        unlocked.add(design.id);
      }
    }
    unlocked.add('classic');
    return unlocked;
  }
}
