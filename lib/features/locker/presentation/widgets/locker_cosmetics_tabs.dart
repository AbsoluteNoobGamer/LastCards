import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/card_back_service.dart';
import '../../../../core/services/cosmetic_unlock_service.dart';
import '../../../../core/services/player_level_service.dart';
import 'locker_tile.dart';
import 'unlock_cosmetic_sheet.dart';

/// "Card backs" tab: the free generic Classic back, plus covers and
/// animated backs — level-gated, or unlockable early with coins/cash.
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
                    return ValueListenableBuilder<int>(
                      valueListenable: CosmeticUnlockService.instance.revision,
                      builder: (context, _, __) {
                        final owned = <CardBackDesign>[];
                        final locked = <CardBackDesign>[];
                        for (final d in [...covers, ...animated]) {
                          (service.isCardBackOwned(d) ? owned : locked).add(d);
                        }
                        locked.sort((a, b) {
                          final cmp = a.unlockLevel.compareTo(b.unlockLevel);
                          return cmp != 0 ? cmp : a.label.compareTo(b.label);
                        });

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          children: [
                            const LockerSectionLabel('Unlocked'),
                            _grid([
                              LockerTile(
                                label: 'Classic',
                                state: selectedId == 'classic'
                                    ? LockerTileState.selected
                                    : LockerTileState.owned,
                                preview: _swatch(context, 'Classic'),
                                onTap: () => service.selectDesign('classic'),
                              ),
                              ...owned.map((d) {
                                return LockerTile(
                                  label: d.label,
                                  state: d.id == selectedId
                                      ? LockerTileState.selected
                                      : LockerTileState.owned,
                                  preview: _thumbnail(context, d),
                                  onTap: () => service.selectDesign(d.id),
                                );
                              }),
                            ]),
                            const LockerSectionLabel('Locked'),
                            _grid(
                              locked.map((d) {
                                return LockerTile(
                                  label: d.label,
                                  state: LockerTileState.lockedByLevel,
                                  lockCaption: 'Level ${d.unlockLevel}',
                                  preview: _thumbnail(context, d),
                                  onTap: () => showUnlockCosmeticSheet(
                                    context,
                                    name: d.label,
                                    unlockLevel: d.unlockLevel,
                                    coinCost: d.coinUnlockCost,
                                    cashProductId: d.cashUnlockProductId,
                                    cashGateSatisfied:
                                        service.canCashUnlockCardBack(d.id),
                                    cashGateMessage:
                                        'Unlock the card back before this one '
                                        'first to buy this with real money.',
                                    onCoinGranted: () =>
                                        CosmeticUnlockService.instance
                                            .markPurchased(
                                      CosmeticUnlockService.categoryCardBacks,
                                      d.id,
                                    ),
                                  ),
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
                return ValueListenableBuilder<int>(
                  valueListenable: CosmeticUnlockService.instance.revision,
                  builder: (context, _, __) {
                    final unlockedJokers = <CardBackDesign>[];
                    final lockedJokers = <CardBackDesign>[];
                    for (final d in jokers) {
                      (service.isJokerCoverOwned(d)
                              ? unlockedJokers
                              : lockedJokers)
                          .add(d);
                    }
                    lockedJokers.sort((a, b) {
                      final cmp = a.unlockLevel.compareTo(b.unlockLevel);
                      return cmp != 0 ? cmp : a.label.compareTo(b.label);
                    });

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        const LockerSectionLabel('Unlocked'),
                        _grid([
                          LockerTile(
                            label: 'Classic',
                            state: selectedId == 'classic'
                                ? LockerTileState.selected
                                : LockerTileState.owned,
                            preview: _swatch(context, 'Classic'),
                            onTap: () => service.selectJokerCover('classic'),
                          ),
                          ...unlockedJokers.map((d) {
                            return LockerTile(
                              label: d.label,
                              state: d.id == selectedId
                                  ? LockerTileState.selected
                                  : LockerTileState.owned,
                              preview: _thumbnail(context, d),
                              onTap: () => service.selectJokerCover(d.id),
                            );
                          }),
                        ]),
                        const LockerSectionLabel('Locked'),
                        _grid(
                          lockedJokers.map((d) {
                            return LockerTile(
                              label: d.label,
                              state: LockerTileState.lockedByLevel,
                              lockCaption: 'Level ${d.unlockLevel}',
                              preview: _thumbnail(context, d),
                              onTap: () => showUnlockCosmeticSheet(
                                context,
                                name: d.label,
                                unlockLevel: d.unlockLevel,
                                coinCost: d.coinUnlockCost,
                                cashProductId: d.cashUnlockProductId,
                                cashGateSatisfied:
                                    service.canCashUnlockJoker(d.id),
                                cashGateMessage:
                                    'Unlock the joker before this one first '
                                    'to buy this with real money.',
                                onCoinGranted: () => CosmeticUnlockService
                                    .instance
                                    .markPurchased(
                                  CosmeticUnlockService.categoryJokers,
                                  d.id,
                                ),
                              ),
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

/// Real thumbnail for a card back / joker cover, falling back to an
/// initials-style placeholder if the asset fails to load (e.g. missing
/// bundled asset, corrupt file).
///
/// Uses [BoxFit.cover] rather than [BoxFit.contain]: these are tall
/// portrait card images inside a roughly-square tile, so "contain" leaves
/// large empty bars down the sides. "cover" fills the tile completely and
/// crops a bit off the top/bottom instead, which reads much better at
/// thumbnail size.
Widget _thumbnail(BuildContext context, CardBackDesign d) {
  final path = d.assetPath ?? d.id;
  final colors = Theme.of(context).colorScheme;
  return ColoredBox(
    color: colors.surfaceContainerHighest,
    child: Image.asset(
      path,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _swatch(context, d.label),
    ),
  );
}

/// Placeholder thumbnail (initials-style) — used as a fallback when an
/// asset fails to load, and for abstract options with no single image
/// (e.g. card face sets).
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
