import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/card_back_service.dart';
import '../../../../core/services/player_level_service.dart';
import 'locker_tile.dart';

/// "Card backs" tab: static covers (always owned) + animated backs
/// (level-gated).
class LockerCardBacksTab extends StatelessWidget {
  const LockerCardBacksTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CardBackService.instance;

    return ValueListenableBuilder<String>(
      valueListenable: service.selectedDesignId,
      builder: (context, selectedId, _) {
        return ValueListenableBuilder<List<CardBackDesign>>(
          valueListenable: service.cardBackCoverDesigns,
          builder: (context, covers, _) {
            return ValueListenableBuilder<List<CardBackDesign>>(
              valueListenable: service.animatedGifDesigns,
              builder: (context, animated, _) {
                return ValueListenableBuilder<int>(
                  valueListenable: PlayerLevelService.instance.currentLevel,
                  builder: (context, level, _) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        const LockerSectionLabel('Card backs'),
                        _grid(
                          covers.map((d) {
                            return LockerTile(
                              label: d.label,
                              state: d.id == selectedId
                                  ? LockerTileState.selected
                                  : LockerTileState.owned,
                              preview: _swatch(context, d.label),
                              onTap: () => service.selectDesign(d.id),
                            );
                          }).toList(),
                        ),
                        const LockerSectionLabel('Animated card backs'),
                        _grid(
                          animated.map((d) {
                            final unlocked = level >= d.unlockLevel;
                            final isSelected = d.id == selectedId;
                            return LockerTile(
                              label: d.label,
                              state: isSelected
                                  ? LockerTileState.selected
                                  : unlocked
                                      ? LockerTileState.owned
                                      : LockerTileState.lockedByLevel,
                              lockCaption: unlocked ? null : 'Level ${d.unlockLevel}',
                              preview: _swatch(context, d.label),
                              onTap: () {
                                if (!unlocked) return;
                                service.selectDesign(d.id);
                              },
                            );
                          }).toList(),
                        ),
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
}

/// "Jokers" tab.
class LockerJokersTab extends StatelessWidget {
  const LockerJokersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CardBackService.instance;

    return ValueListenableBuilder<String>(
      valueListenable: service.selectedJokerCoverId,
      builder: (context, selectedId, _) {
        return ValueListenableBuilder<List<CardBackDesign>>(
          valueListenable: service.jokerCoverDesigns,
          builder: (context, jokers, _) {
            return ValueListenableBuilder<int>(
              valueListenable: PlayerLevelService.instance.currentLevel,
              builder: (context, level, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    const LockerSectionLabel('Joker covers'),
                    _grid([
                      LockerTile(
                        label: 'Classic',
                        state: selectedId == 'classic'
                            ? LockerTileState.selected
                            : LockerTileState.owned,
                        preview: _swatch(context, 'Classic'),
                        onTap: () => service.selectJokerCover('classic'),
                      ),
                      ...jokers.map((d) {
                        final unlocked = level >= d.unlockLevel;
                        final isSelected = d.id == selectedId;
                        return LockerTile(
                          label: d.label,
                          state: isSelected
                              ? LockerTileState.selected
                              : unlocked
                                  ? LockerTileState.owned
                                  : LockerTileState.lockedByLevel,
                          lockCaption: unlocked ? null : 'Level ${d.unlockLevel}',
                          preview: _swatch(context, d.label),
                          onTap: () {
                            if (!unlocked) return;
                            service.selectJokerCover(d.id);
                          },
                        );
                      }),
                    ]),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// "Faces" tab — just two options today (default / classic), always unlocked.
class LockerFacesTab extends StatelessWidget {
  const LockerFacesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CardBackService.instance;
    final colors = Theme.of(context).colorScheme;

    return ValueListenableBuilder<String>(
      valueListenable: service.selectedCardFaceSetId,
      builder: (context, selectedId, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const LockerSectionLabel('Card faces'),
            Text(
              'Changes the rank and suit artwork on every card face.',
              style: GoogleFonts.dmSans(fontSize: 12.5, color: colors.onSurface.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 12),
            _grid([
              LockerTile(
                label: 'Default',
                state: selectedId == 'default' ? LockerTileState.selected : LockerTileState.owned,
                preview: _swatch(context, 'Default'),
                onTap: () => service.selectCardFaceSet('default'),
              ),
              LockerTile(
                label: 'Classic',
                state: selectedId == 'classic' ? LockerTileState.selected : LockerTileState.owned,
                preview: _swatch(context, 'Classic'),
                onTap: () => service.selectCardFaceSet('classic'),
              ),
            ]),
          ],
        );
      },
    );
  }
}

Widget _grid(List<Widget> tiles) {
  return GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    crossAxisSpacing: 10,
    mainAxisSpacing: 10,
    childAspectRatio: 0.82,
    children: tiles,
  );
}

/// Placeholder thumbnail (initials-style) until real asset thumbnails are
/// wired in — keeps this file independent from asset-loading concerns.
Widget _swatch(BuildContext context, String label) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    color: colors.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Text(
      label.isNotEmpty ? label[0].toUpperCase() : '?',
      style: GoogleFonts.playfairDisplay(
        fontSize: 18,
        color: colors.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
