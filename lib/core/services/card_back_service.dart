import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_model.dart';
import 'analytics_service.dart';
import 'cosmetic_unlock_service.dart';
import 'firestore_profile_service.dart';
import 'player_level_service.dart';
import 'purchase_service.dart';

class CardBackDesign {
  const CardBackDesign({
    required this.id,
    required this.label,
    this.unlockLevel = 1,
    this.assetPath,
    this.coinUnlockCost,
    this.cashUnlockProductId,
  });

  final String id;
  final String label;
  final int unlockLevel;

  /// If set, this design is a cardbackcover image at this asset path.
  final String? assetPath;

  /// Coin price to permanently unlock this design early. Null means it
  /// isn't coin-purchasable (e.g. free designs).
  final int? coinUnlockCost;

  /// Non-consumable IAP product ID to buy this design outright. Null means
  /// it isn't cash-purchasable.
  final String? cashUnlockProductId;
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

  /// Default card back when no preference is saved — the free generic
  /// procedural back every player owns (see `CardBackWidget`'s 'classic'
  /// branch). Cover images are level/coin/cash-gated like other cosmetics.
  static const String _defaultCardBackId = 'classic';

  /// Cover images' unlock levels (filename, lowercase → level). Files not
  /// listed default to level 5.
  static const Map<String, int> _coverUnlockLevels = {
    'purple complex.png': 3,
    'gold carbon.png': 4,
    'metalic blue.jpg': 6,
    'darkness in green.png': 8,
    'noobgamer back.jpg': 10,
    'two lions.png': 12,
  };

  static int _coinCostForLevel(int unlockLevel) =>
      CosmeticUnlockService.coinCostForLevel(unlockLevel);

  /// 'Gold Carbon.png' → 'gold_carbon' — stable product-id fragment for a
  /// bundled asset filename. Must stay in sync with the product IDs
  /// configured in App Store Connect / Play Console (and
  /// ios/Runner/Configuration.storekit for local testing).
  static String _slugForFilename(String filename) {
    final base = filename.replaceAll(RegExp(r'\.[^.]+$'), '').toLowerCase();
    return base
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
  static const String _jokerCoverPrefix = 'assets/images/jokercover/';
  static const String _animatedCardsPrefix = 'assets/animated_cards/';
  static const Set<String> _builtInAnimatedNames = {
    'classic.gif',
    'obsidian.gif',
    'ruby.gif',
    'royal.gif',
    'aurora.gif',
    'lava_flow.gif',
    'hologram.gif',
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
    // New backs
    CardBackDesign(id: 'midas', label: 'Midas', unlockLevel: 5),
    CardBackDesign(id: 'ivory_onyx', label: 'Ivory & Onyx', unlockLevel: 4),
    CardBackDesign(id: 'platinum', label: 'Platinum', unlockLevel: 6),
    CardBackDesign(id: 'midnight_forest', label: 'Midnight Forest', unlockLevel: 8),
    CardBackDesign(id: 'ocean_depths', label: 'Ocean Depths', unlockLevel: 9),
    CardBackDesign(id: 'inferno', label: 'Inferno', unlockLevel: 10),
    CardBackDesign(id: 'circuit_board', label: 'Circuit Board', unlockLevel: 8),
    CardBackDesign(id: 'mosaic', label: 'Mosaic', unlockLevel: 11),
    CardBackDesign(id: 'labyrinth', label: 'Labyrinth', unlockLevel: 13),
    CardBackDesign(id: 'aurora', label: 'Aurora', unlockLevel: 15),
    CardBackDesign(id: 'lava_flow', label: 'Lava Flow', unlockLevel: 14),
    CardBackDesign(id: 'hologram', label: 'Hologram', unlockLevel: 18),
    CardBackDesign(id: 'galaxy', label: 'Galaxy', unlockLevel: 20),
    CardBackDesign(id: 'vintage_casino', label: 'Vintage Casino', unlockLevel: 2),
    CardBackDesign(id: 'zodiac', label: 'Zodiac', unlockLevel: 16),
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

    // Declare cash-unlock products before PurchaseService.init() queries the
    // store (main() runs this service's init first).
    for (final d in [
      ...cardBackCoverDesigns.value,
      ...animatedGifDesigns.value,
    ]) {
      final productId = d.cashUnlockProductId;
      if (productId != null) {
        PurchaseService.instance.registerCosmeticProduct(
          productId: productId,
          category: CosmeticUnlockService.categoryCardBacks,
          itemId: d.id,
        );
      }
    }
    for (final d in jokerCoverDesigns.value) {
      final productId = d.cashUnlockProductId;
      if (productId != null) {
        PurchaseService.instance.registerCosmeticProduct(
          productId: productId,
          category: CosmeticUnlockService.categoryJokers,
          itemId: d.id,
        );
      }
    }

    // Ensure prefs are consistent with level-based unlocking (and migrate
    // away from any legacy/unrelated unlocked state).
    final computedUnlocked = _unlocked.join(',');
    if (unlockedRaw == null || unlockedRaw.trim().isEmpty || unlockedRaw != computedUnlocked) {
      await prefs.setString(_prefsUnlockedKey, computedUnlocked);
    }

    final covers = cardBackCoverDesigns.value;
    final animatedGifs = animatedGifDesigns.value;
    final isValidSelected = selected == 'classic' ||
        _unlocked.contains(selected) ||
        covers.any((d) => d.id == selected && isCardBackOwned(d)) ||
        animatedGifs.any((d) => d.id == selected && isCardBackOwned(d));
    if (isValidSelected) {
      selectedDesignId.value = selected;
    } else {
      // Saved design is gone (file renamed) or no longer owned (covers
      // became gated) — fall back to the free generic back.
      selectedDesignId.value = 'classic';
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
        (selectedDesign != null && isJokerCoverOwned(selectedDesign));

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

  /// [pushToFirestore]: set false when applying a batch from Firestore (each
  /// selection would otherwise write all three fields and clobber not-yet-applied keys).
  Future<bool> selectCardFaceSet(
    String faceSetId, {
    bool pushToFirestore = true,
  }) async {
    await init();
    if (faceSetId != 'classic' && faceSetId != 'default') return false;
    if (selectedCardFaceSetId.value == faceSetId) return true;
    selectedCardFaceSetId.value = faceSetId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCardFaceSetKey, faceSetId);
    if (pushToFirestore) unawaited(_pushCardCustomizationToFirestore());
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
      return paths.map((path) {
        final filename = path.split('/').last;
        final level = _unlockLevelForJokerCoverPath(path);
        return CardBackDesign(
          id: path,
          label: _labelFromFilename(filename),
          assetPath: path,
          unlockLevel: level,
          coinUnlockCost: level > 1 ? _coinCostForLevel(level) : null,
          cashUnlockProductId:
              level > 1 ? 'joker_unlock_${_slugForFilename(filename)}' : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static int _unlockLevelForJokerCoverPath(String assetPath) {
    final filename = assetPath.split('/').last.toLowerCase();
    return switch (filename) {
      'jokerface.png' => 4,
      'joker_hearts_carbon.png' => 8,
      'joker2_hearts_carbon.png' => 12,
      'joker sci-fi.png' => 18,
      // Default: harder than the base classic joker cover.
      _ => 5,
    };
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
      return paths.map((path) {
        final filename = path.split('/').last;
        final level = _coverUnlockLevels[filename.toLowerCase()] ?? 5;
        return CardBackDesign(
          id: path,
          label: _labelFromFilename(filename),
          assetPath: path,
          unlockLevel: level,
          coinUnlockCost: _coinCostForLevel(level),
          cashUnlockProductId: 'cardback_unlock_${_slugForFilename(filename)}',
        );
      }).toList();
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
      return paths.map((path) {
        final filename = path.split('/').last;
        final level = _unlockLevelForAnimatedGif(filename);
        return CardBackDesign(
          id: path,
          label: _labelFromFilename(filename),
          unlockLevel: level,
          coinUnlockCost: level > 1 ? _coinCostForLevel(level) : null,
          cashUnlockProductId: level > 1
              ? 'cardback_unlock_${_slugForFilename(filename)}'
              : null,
        );
      }).toList();
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

  /// Owned = reached by level, or permanently purchased with coins/cash.
  bool isCardBackOwned(CardBackDesign d) =>
      PlayerLevelService.instance.currentLevel.value >= d.unlockLevel ||
      CosmeticUnlockService.instance
          .isPurchased(CosmeticUnlockService.categoryCardBacks, d.id);

  bool isJokerCoverOwned(CardBackDesign d) =>
      PlayerLevelService.instance.currentLevel.value >= d.unlockLevel ||
      CosmeticUnlockService.instance
          .isPurchased(CosmeticUnlockService.categoryJokers, d.id);

  static List<CardBackDesign> _sortedLadder(Iterable<CardBackDesign> items) {
    return items.where((d) => d.cashUnlockProductId != null).toList()
      ..sort((a, b) {
        final cmp = a.unlockLevel.compareTo(b.unlockLevel);
        return cmp != 0 ? cmp : a.label.compareTo(b.label);
      });
  }

  /// True if [id] is next in line for a cash unlock: every earlier design
  /// in the card-back ladder (covers + animated, by unlock level) is
  /// already owned — by level, coins, or a prior purchase. Same
  /// keep-progression-intact rule as theme cash unlocks.
  bool canCashUnlockCardBack(String id) {
    for (final d in _sortedLadder(
        [...cardBackCoverDesigns.value, ...animatedGifDesigns.value])) {
      if (d.id == id) return true;
      if (!isCardBackOwned(d)) return false;
    }
    return false;
  }

  bool canCashUnlockJoker(String id) {
    for (final d in _sortedLadder(jokerCoverDesigns.value)) {
      if (d.id == id) return true;
      if (!isJokerCoverOwned(d)) return false;
    }
    return false;
  }

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

  /// [pushToFirestore]: set false when applying a batch from Firestore (avoids each step writing all three fields).
  Future<bool> selectDesign(
    String designId, {
    bool pushToFirestore = true,
  }) async {
    await init();
    if (designId == 'uploaded' && uploadedAnimatedAssetPath.value == null) {
      return false;
    }
    if (designId != 'uploaded' && designId != 'classic') {
      // Covers and animated GIFs are both gated: level, or a coin/cash
      // purchase recorded in [CosmeticUnlockService].
      final design = cardBackCoverDesigns.value
              .where((d) => d.id == designId)
              .firstOrNull ??
          animatedGifDesigns.value.where((d) => d.id == designId).firstOrNull;
      if (design != null) {
        if (!isCardBackOwned(design)) return false;
      } else if (!_isDesignUnlocked(designId)) {
        return false;
      }
    }
    if (selectedDesignId.value == designId) return true;
    selectedDesignId.value = designId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSelectedKey, designId);
    if (pushToFirestore) unawaited(_pushCardCustomizationToFirestore());
    AnalyticsService.instance.logCardBackChanged(designId: designId);
    return true;
  }

  /// [pushToFirestore]: set false when applying a batch from Firestore (avoids each step writing all three fields).
  Future<bool> selectJokerCover(
    String designId, {
    bool pushToFirestore = true,
  }) async {
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
      if (!isJokerCoverOwned(design)) return false;
    }
    if (selectedJokerCoverId.value == designId) return true;
    selectedJokerCoverId.value = designId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsJokerCoverKey, designId);
    if (pushToFirestore) unawaited(_pushCardCustomizationToFirestore());
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
