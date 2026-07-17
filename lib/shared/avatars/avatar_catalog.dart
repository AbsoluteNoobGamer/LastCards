/// Curated in-game avatar cosmetics (Locker → Avatars).
enum AvatarExclusiveKind {
  comboKing,
  rankedCrown,
  hardcoreCrown,
  casualAce,
  tourneyAi,
  tourneyOnline,
  bustOnline,
}

class AvatarDesign {
  const AvatarDesign({
    required this.id,
    required this.label,
    required this.assetPath,
    this.unlockLevel = 1,
    this.animated = false,
    this.exclusiveKind,
  });

  final String id;
  final String label;
  final String assetPath;
  final int unlockLevel;
  final bool animated;
  final AvatarExclusiveKind? exclusiveKind;

  bool get isTitleExclusive => exclusiveKind != null;
}

/// Sentinel: player uses Auth photo / initials instead of a cosmetic.
const String kAvatarUsePhotoId = 'use_photo';

/// Default equipped cosmetic when the player opts into in-game faces.
const String kAvatarDefaultId = 'default_chip';

const List<AvatarDesign> kAvatarCatalog = [
  AvatarDesign(
    id: kAvatarDefaultId,
    label: 'Felt Chip',
    assetPath: 'assets/avatars/default_chip.png',
    unlockLevel: 1,
  ),
  AvatarDesign(
    id: 'spade_ace',
    label: 'Spade Ace',
    assetPath: 'assets/avatars/spade_ace.png',
    unlockLevel: 3,
  ),
  AvatarDesign(
    id: 'neon_joker',
    label: 'Neon Joker',
    assetPath: 'assets/avatars/neon_joker.png',
    unlockLevel: 25,
    animated: true,
  ),
  AvatarDesign(
    id: 'gold_king',
    label: 'Gold King',
    assetPath: 'assets/avatars/gold_king.png',
    unlockLevel: 40,
    animated: true,
  ),
  AvatarDesign(
    id: 'title_combo_king',
    label: 'Combo King',
    assetPath: 'assets/avatars/title_combo_king.png',
    exclusiveKind: AvatarExclusiveKind.comboKing,
    animated: true,
  ),
  AvatarDesign(
    id: 'title_ranked_crown',
    label: 'Ranked Crown',
    assetPath: 'assets/avatars/title_ranked_crown.png',
    exclusiveKind: AvatarExclusiveKind.rankedCrown,
  ),
  AvatarDesign(
    id: 'title_hardcore_crown',
    label: 'Hardcore Crown',
    assetPath: 'assets/avatars/title_hardcore_crown.png',
    exclusiveKind: AvatarExclusiveKind.hardcoreCrown,
    animated: true,
  ),
  AvatarDesign(
    id: 'title_casual_ace',
    label: 'Casual Ace',
    assetPath: 'assets/avatars/title_casual_ace.png',
    exclusiveKind: AvatarExclusiveKind.casualAce,
  ),
  AvatarDesign(
    id: 'title_tourney_ai',
    label: 'Tournament Crown',
    assetPath: 'assets/avatars/title_tourney_crown.png',
    exclusiveKind: AvatarExclusiveKind.tourneyAi,
  ),
  AvatarDesign(
    id: 'title_tourney_online',
    label: 'Online Tournament',
    assetPath: 'assets/avatars/title_tourney_crown.png',
    exclusiveKind: AvatarExclusiveKind.tourneyOnline,
  ),
  AvatarDesign(
    id: 'title_bust_online',
    label: 'Bust Boss',
    assetPath: 'assets/avatars/title_bust_online.png',
    exclusiveKind: AvatarExclusiveKind.bustOnline,
    animated: true,
  ),
];

AvatarDesign? avatarDesignById(String? id) {
  if (id == null || id.isEmpty || id == kAvatarUsePhotoId) return null;
  for (final d in kAvatarCatalog) {
    if (d.id == id) return d;
  }
  return null;
}

bool isKnownAvatarId(String? id) {
  if (id == null || id.isEmpty) return true;
  if (id == kAvatarUsePhotoId) return true;
  return avatarDesignById(id) != null;
}
