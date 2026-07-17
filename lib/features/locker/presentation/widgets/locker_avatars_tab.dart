import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/avatar_catalog_service.dart';
import '../../../../core/services/player_level_service.dart';
import '../../../../core/widgets/gameplay_circle_avatar.dart';
import '../../../../shared/avatars/avatar_catalog.dart';
import '../../../../shared/avatars/avatar_face.dart';
import 'locker_tile.dart';

/// "Avatars" tab — photo/initials plus level and title-exclusive cosmetics.
class LockerAvatarsTab extends StatefulWidget {
  const LockerAvatarsTab({super.key});

  @override
  State<LockerAvatarsTab> createState() => _LockerAvatarsTabState();
}

class _LockerAvatarsTabState extends State<LockerAvatarsTab> {
  @override
  void initState() {
    super.initState();
    AvatarCatalogService.instance.refreshTitleEntitlements();
  }

  @override
  Widget build(BuildContext context) {
    final service = AvatarCatalogService.instance;
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<String>(
      valueListenable: service.selectedId,
      builder: (context, selectedId, _) {
        return ValueListenableBuilder<Set<AvatarExclusiveKind>>(
          valueListenable: service.ownedTitles,
          builder: (context, ownedTitles, _) {
            return ValueListenableBuilder<int>(
              valueListenable: PlayerLevelService.instance.currentLevel,
              builder: (context, level, _) {
                final levelDesigns = <AvatarDesign>[];
                final titleDesigns = <AvatarDesign>[];
                for (final d in kAvatarCatalog) {
                  if (d.isTitleExclusive) {
                    titleDesigns.add(d);
                  } else {
                    levelDesigns.add(d);
                  }
                }

                final unlockedLevel = <AvatarDesign>[];
                final lockedLevel = <AvatarDesign>[];
                for (final d in levelDesigns) {
                  (service.isUnlocked(d) ? unlockedLevel : lockedLevel).add(d);
                }

                final unlockedTitle = <AvatarDesign>[];
                final lockedTitle = <AvatarDesign>[];
                for (final d in titleDesigns) {
                  (service.isUnlocked(d) ? unlockedTitle : lockedTitle).add(d);
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      'Shown at the table instead of your photo when equipped. '
                      'Title exclusives unlock while you hold #1 on that board.',
                      style: GoogleFonts.dmSans(
                        fontSize: 12.5,
                        color: colors.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const LockerSectionLabel('Unlocked'),
                    _grid([
                      LockerTile(
                        label: 'Photo / initials',
                        state: selectedId == kAvatarUsePhotoId
                            ? LockerTileState.selected
                            : LockerTileState.owned,
                        preview: const _UsePhotoPreview(),
                        onTap: () => service.select(kAvatarUsePhotoId),
                      ),
                      ...unlockedLevel.map((d) {
                        return LockerTile(
                          label: d.label,
                          state: d.id == selectedId
                              ? LockerTileState.selected
                              : LockerTileState.owned,
                          preview: _AvatarPreview(design: d),
                          onTap: () => service.select(d.id),
                        );
                      }),
                      ...unlockedTitle.map((d) {
                        return LockerTile(
                          label: d.label,
                          state: d.id == selectedId
                              ? LockerTileState.selected
                              : LockerTileState.owned,
                          preview: _AvatarPreview(design: d),
                          onTap: () => service.select(d.id),
                        );
                      }),
                    ]),
                    if (lockedLevel.isNotEmpty || lockedTitle.isNotEmpty) ...[
                      const LockerSectionLabel('Locked'),
                      _grid([
                        ...lockedLevel.map((d) {
                          return LockerTile(
                            label: d.label,
                            state: LockerTileState.lockedByLevel,
                            lockCaption: 'Level ${d.unlockLevel}',
                            preview: _AvatarPreview(design: d),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Reach level ${d.unlockLevel} to unlock ${d.label}.',
                                  ),
                                ),
                              );
                            },
                          );
                        }),
                        ...lockedTitle.map((d) {
                          return LockerTile(
                            label: d.label,
                            state: LockerTileState.lockedByLevel,
                            lockCaption: _titleCaption(d.exclusiveKind),
                            preview: _AvatarPreview(design: d),
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Hold #1 on ${_titleBoardName(d.exclusiveKind)} '
                                    'to unlock ${d.label}.',
                                  ),
                                ),
                              );
                            },
                          );
                        }),
                      ]),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _grid(List<Widget> children) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.82,
      children: children,
    );
  }

  static String _titleCaption(AvatarExclusiveKind? kind) {
    return switch (kind) {
      AvatarExclusiveKind.comboKing => 'Combo #1',
      AvatarExclusiveKind.rankedCrown => 'Ranked #1',
      AvatarExclusiveKind.hardcoreCrown => 'Hardcore #1',
      AvatarExclusiveKind.casualAce => 'Casual #1',
      AvatarExclusiveKind.tourneyAi => 'AI tourney #1',
      AvatarExclusiveKind.tourneyOnline => 'Online tourney #1',
      AvatarExclusiveKind.bustOnline => 'Bust online #1',
      null => 'Title #1',
    };
  }

  static String _titleBoardName(AvatarExclusiveKind? kind) {
    return switch (kind) {
      AvatarExclusiveKind.comboKing => 'the Combo leaderboard',
      AvatarExclusiveKind.rankedCrown => 'Ranked',
      AvatarExclusiveKind.hardcoreCrown => 'Ranked Hardcore',
      AvatarExclusiveKind.casualAce => 'Casual Online wins',
      AvatarExclusiveKind.tourneyAi => 'AI Tournament wins',
      AvatarExclusiveKind.tourneyOnline => 'Online Tournament wins',
      AvatarExclusiveKind.bustOnline => 'Bust Online wins',
      null => 'that leaderboard',
    };
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.design});

  final AvatarDesign design;

  @override
  Widget build(BuildContext context) {
    return Center(child: AvatarFace(design: design, size: 56));
  }
}

class _UsePhotoPreview extends StatelessWidget {
  const _UsePhotoPreview();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: CircleAvatar(
        radius: 28,
        backgroundColor: colors.primary.withValues(alpha: 0.18),
        child: GameplayCircleAvatar(
          radius: 28,
          displayName: 'You',
          initialsOverride: 'YO',
          foregroundTextStyle: TextStyle(
            color: colors.primary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
