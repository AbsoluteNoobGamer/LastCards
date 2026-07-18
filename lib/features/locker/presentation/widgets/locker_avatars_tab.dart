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
        return ValueListenableBuilder<bool>(
          valueListenable: service.entitlementsReady,
          builder: (context, entitlementsReady, _) {
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
                      (service.isUnlocked(d) ? unlockedLevel : lockedLevel)
                          .add(d);
                    }

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        Text(
                          'Shown at the table instead of your photo when equipped.',
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
                        ]),
                        const LockerSectionLabel('Leaderboard titles'),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                          child: Text(
                            entitlementsReady
                                ? 'Only the current #1 on each board can equip '
                                    'that title. Lose the spot and it locks again.'
                                : 'Checking who holds each #1…',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              height: 1.35,
                              color: colors.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        _grid([
                          ...titleDesigns.map((d) {
                            final board = d.leaderboardLabel ??
                                leaderboardLabelForKind(d.exclusiveKind!);
                            final unlocked = service.isUnlocked(d);
                            return LockerTile(
                              label: d.label,
                              state: !unlocked
                                  ? LockerTileState.lockedByLevel
                                  : d.id == selectedId
                                      ? LockerTileState.selected
                                      : LockerTileState.owned,
                              lockCaption: unlocked
                                  ? 'Holding #1 · $board'
                                  : '#1 only · $board',
                              preview: _AvatarPreview(design: d),
                              onTap: () {
                                if (!unlocked) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Hold #1 on $board to unlock ${d.label}. '
                                        'It locks again if someone takes the top spot.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                service.select(d.id);
                              },
                            );
                          }),
                        ]),
                        if (lockedLevel.isNotEmpty) ...[
                          const LockerSectionLabel('Locked by level'),
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
      childAspectRatio: 0.78,
      children: children,
    );
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
