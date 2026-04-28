/// How a reaction renders in UI and floating bubbles.
enum ReactionVisualKind {
  unicode,
  gifAsset,
}

/// One unlockable preset reaction — wire id is its index in [kReactionDefinitions].
///
/// [minUnlockLevel] matches local player levels (see app `PlayerLevelService`).
class ReactionDefinition {
  const ReactionDefinition._({
    required this.minUnlockLevel,
    required this.kind,
    this.unicodeLabel,
    this.gifAssetPath,
  });

  /// Plain Unicode emoji bubble (recommended for starters).
  const ReactionDefinition.unicode(String emoji, {int minUnlockLevel = 1})
      : this._(
          minUnlockLevel: minUnlockLevel,
          kind: ReactionVisualKind.unicode,
          unicodeLabel: emoji,
          gifAssetPath: null,
        );

  /// Animated GIF (bundled asset). Fits in circular bubble like CR.
  const ReactionDefinition.gif(String assetPath, {required int minUnlockLevel})
      : this._(
          minUnlockLevel: minUnlockLevel,
          kind: ReactionVisualKind.gifAsset,
          unicodeLabel: null,
          gifAssetPath: assetPath,
        );

  /// Minimum player level required (see [PlayerLevelService]).
  final int minUnlockLevel;
  final ReactionVisualKind kind;
  final String? unicodeLabel;
  final String? gifAssetPath;

  bool get isAnimated => kind == ReactionVisualKind.gifAsset;

  /// Placeholder character for logs / legacy string lists ([kQuickMessages]).
  String get legacyWireEmoji =>
      kind == ReactionVisualKind.unicode ? unicodeLabel! : '🎞';
}

/// Authoritative preset list shared by Flutter app **and** game server validation.
///
/// Indices are sent as [QuickChatAction.messageIndex] / `quick_chat` events.
const List<ReactionDefinition> kReactionDefinitions = [
  ReactionDefinition.unicode('🤞'),
  ReactionDefinition.unicode('👏'),
  ReactionDefinition.unicode('😅'),
  ReactionDefinition.unicode('🔥'),
  ReactionDefinition.unicode('🙏'),
  ReactionDefinition.unicode('🙌'),
  ReactionDefinition.unicode('💪'),
  ReactionDefinition.unicode('✌️'),
  ReactionDefinition.unicode('🃏'),
  ReactionDefinition.unicode('☝️'),
  ReactionDefinition.unicode('😂'),
  ReactionDefinition.unicode('😬'),
  ReactionDefinition.unicode('😤'),
  // Extra unlock tiers (beyond starter row). Wire indices fixed — do not reorder.
  ReactionDefinition.unicode('🎆', minUnlockLevel: 10),
  ReactionDefinition.unicode('✨', minUnlockLevel: 20),
  ReactionDefinition.unicode('👑', minUnlockLevel: 35),
  ReactionDefinition.unicode('⚡', minUnlockLevel: 50),
  // Appended tiers only — do not reorder earlier entries (wire indices stable).
  ReactionDefinition.unicode('🍀', minUnlockLevel: 5),
  ReactionDefinition.unicode('🎯', minUnlockLevel: 7),
  ReactionDefinition.unicode('🎲', minUnlockLevel: 8),
  ReactionDefinition.unicode('😎', minUnlockLevel: 11),
  ReactionDefinition.unicode('🎉', minUnlockLevel: 12),
  ReactionDefinition.unicode('💯', minUnlockLevel: 14),
  ReactionDefinition.unicode('🤝', minUnlockLevel: 15),
  ReactionDefinition.unicode('🫶', minUnlockLevel: 16),
  ReactionDefinition.unicode('🎊', minUnlockLevel: 18),
  ReactionDefinition.unicode('🙃', minUnlockLevel: 19),
  ReactionDefinition.unicode('😏', minUnlockLevel: 21),
  ReactionDefinition.unicode('🥇', minUnlockLevel: 23),
  ReactionDefinition.unicode('🤯', minUnlockLevel: 24),
  ReactionDefinition.unicode('💎', minUnlockLevel: 26),
  ReactionDefinition.unicode('🔮', minUnlockLevel: 27),
  ReactionDefinition.unicode('🌟', minUnlockLevel: 29),
  ReactionDefinition.unicode('💀', minUnlockLevel: 30),
  ReactionDefinition.unicode('🎴', minUnlockLevel: 32),
  ReactionDefinition.unicode('😈', minUnlockLevel: 34),
  ReactionDefinition.unicode('🦄', minUnlockLevel: 37),
  ReactionDefinition.unicode('🚀', minUnlockLevel: 39),
  ReactionDefinition.unicode('🍕', minUnlockLevel: 41),
  ReactionDefinition.unicode('🎖️', minUnlockLevel: 43),
  ReactionDefinition.unicode('🛡️', minUnlockLevel: 46),
  ReactionDefinition.unicode('🐉', minUnlockLevel: 48),
  ReactionDefinition.unicode('🎸', minUnlockLevel: 51),
  ReactionDefinition.unicode('🕶️', minUnlockLevel: 53),
  ReactionDefinition.unicode('🏅', minUnlockLevel: 56),
  ReactionDefinition.unicode('🌈', minUnlockLevel: 58),
  ReactionDefinition.unicode('🦾', minUnlockLevel: 61),
  ReactionDefinition.unicode('🧿', minUnlockLevel: 64),
  ReactionDefinition.unicode('🦁', minUnlockLevel: 67),
  ReactionDefinition.unicode('🎪', minUnlockLevel: 70),
  ReactionDefinition.unicode('🦅', minUnlockLevel: 73),
  ReactionDefinition.unicode('🛸', minUnlockLevel: 76),
  ReactionDefinition.unicode('🧠', minUnlockLevel: 79),
  ReactionDefinition.unicode('🎰', minUnlockLevel: 82),
  ReactionDefinition.unicode('🎭', minUnlockLevel: 86),
  ReactionDefinition.unicode('☠️', minUnlockLevel: 88),
  ReactionDefinition.unicode('🌋', minUnlockLevel: 91),
  ReactionDefinition.unicode('🗿', minUnlockLevel: 94),
  ReactionDefinition.unicode('👁️', minUnlockLevel: 97),
  ReactionDefinition.unicode('🏔️', minUnlockLevel: 100),
];

/// Valid range for Quick Chat indices on wire.
int get kReactionCatalogLength => kReactionDefinitions.length;

/// Standard starter reactions (same count as originally shipped emoji row).
const int kStarterReactionCount = 13;

/// Reaction indices AI uses for random chatter (tier-1 presets only).
List<int> get kAiQuickReactionIndices =>
    List<int>.generate(kStarterReactionCount, (i) => i);

bool isValidReactionWireIndex(int i) =>
    i >= 0 && i < kReactionCatalogLength;

/// Whether [playerLevel] may use this preset (honest client + UI gating).
bool isReactionUnlockedForLevel(int reactionIndex, int playerLevel) {
  if (!isValidReactionWireIndex(reactionIndex)) return false;
  final def = kReactionDefinitions[reactionIndex];
  return playerLevel >= def.minUnlockLevel;
}

/// Indices the player actually has unlocked for [playerLevel].
List<int> unlockedReactionIndicesForLevel(int playerLevel) {
  final out = <int>[];
  for (var i = 0; i < kReactionCatalogLength; i++) {
    if (isReactionUnlockedForLevel(i, playerLevel)) out.add(i);
  }
  return out;
}

/// Indices that may appear on the emoji wheel slots (starter row size).
Iterable<int> defaultWheelReactionIndices() =>
    List<int>.generate(kStarterReactionCount, (i) => i);
