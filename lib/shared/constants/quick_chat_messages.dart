import '../reactions/reaction_catalog.dart';

export '../reactions/reaction_catalog.dart'
    show
        ReactionDefinition,
        ReactionVisualKind,
        defaultWheelReactionIndices,
        isReactionUnlockedForLevel,
        isValidReactionWireIndex,
        kAiQuickReactionIndices,
        kReactionCatalogLength,
        kReactionDefinitions,
        kStarterReactionCount,
        unlockedReactionIndicesForLevel;

/// Back-compat emoji strings aligned with reaction indices (`legacyWireEmoji`
/// substitutes `🎞` for GIF entries).
///
/// Prefer [kReactionDefinitions] for UI; wire format stays **index**.
final List<String> kQuickMessages = List.unmodifiable(
  [
    for (final d in kReactionDefinitions) d.legacyWireEmoji,
  ],
);
