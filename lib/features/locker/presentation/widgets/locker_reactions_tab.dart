import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/reaction_wheel_provider.dart';
import '../../../../core/services/player_level_service.dart';
import '../../../../shared/reactions/built_in_reaction_widgets.dart';
import '../../../../shared/reactions/reaction_catalog.dart';
import 'locker_tile.dart';

/// "Reactions" tab — the 13-slot wheel plus the full owned/locked catalog.
///
/// Tap a wheel slot to select it, then tap any owned (or ad-unlockable)
/// reaction below to assign it into that slot.
class LockerReactionsTab extends ConsumerStatefulWidget {
  const LockerReactionsTab({super.key});

  @override
  ConsumerState<LockerReactionsTab> createState() => _LockerReactionsTabState();
}

class _LockerReactionsTabState extends ConsumerState<LockerReactionsTab> {
  int _activeSlot = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final wheel = ref.watch(reactionWheelProvider);
    final notifier = ref.read(reactionWheelProvider.notifier);
    final level = PlayerLevelService.instance.currentLevel.value;

    final ownedIndices = <int>[];
    final lockedIndices = <int>[];
    for (var i = 0; i < kReactionCatalogLength; i++) {
      if (isReactionUnlockedForLevel(i, level)) {
        ownedIndices.add(i);
      } else {
        lockedIndices.add(i);
      }
    }
    // Display in ascending unlock-level order (top-left = lowest level),
    // independent of wire index / catalog order.
    int byLevel(int a, int b) {
      final cmp = kReactionDefinitions[a].minUnlockLevel.compareTo(kReactionDefinitions[b].minUnlockLevel);
      return cmp != 0 ? cmp : a.compareTo(b);
    }

    ownedIndices.sort(byLevel);
    lockedIndices.sort(byLevel);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const LockerSectionLabel('Wheel — tap a slot, then pick a reaction'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: wheel.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, slotIndex) {
            final catalogId = wheel[slotIndex];
            final def = kReactionDefinitions[catalogId];
            final isActiveSlot = slotIndex == _activeSlot;
            return GestureDetector(
              onTap: () => setState(() => _activeSlot = slotIndex),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActiveSlot ? colors.primary : colors.primary.withValues(alpha: 0.25),
                    width: isActiveSlot ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: def.kind == ReactionVisualKind.builtIn && def.builtInId != null
                    ? BuiltInReactionIcon(builtInId: def.builtInId!, size: 20)
                    : Text(def.unicodeLabel ?? '?', style: const TextStyle(fontSize: 20)),
              ),
            );
          },
        ),
        const LockerSectionLabel('Owned'),
        _reactionGrid(
          ownedIndices,
          wheel: wheel,
          onTap: (id) => notifier.setSlot(_activeSlot, id),
        ),
        const LockerSectionLabel('Locked'),
        _reactionGrid(
          lockedIndices,
          wheel: wheel,
          locked: true,
          onTap: (_) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Reach the required level to unlock this reaction.')),
            );
          },
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => notifier.restoreDefaults(),
          child: Text(
            'Restore default wheel',
            style: GoogleFonts.dmSans(fontSize: 12.5, color: colors.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }

  Widget _reactionGrid(
    List<int> indices, {
    required List<int> wheel,
    required void Function(int catalogId) onTap,
    bool locked = false,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: indices.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, i) {
        final catalogId = indices[i];
        final def = kReactionDefinitions[catalogId];
        final inWheel = wheel.contains(catalogId);
        return LockerTile(
          label: null,
          state: locked
              ? LockerTileState.lockedByLevel
              : inWheel
                  ? LockerTileState.selected
                  : LockerTileState.owned,
          lockCaption: locked ? 'Level ${def.minUnlockLevel}' : null,
          preview: Center(
            child: def.kind == ReactionVisualKind.builtIn && def.builtInId != null
                ? BuiltInReactionIcon(builtInId: def.builtInId!, size: 22)
                : Text(def.unicodeLabel ?? '?', style: const TextStyle(fontSize: 22)),
          ),
          onTap: () => onTap(catalogId),
        );
      },
    );
  }
}
