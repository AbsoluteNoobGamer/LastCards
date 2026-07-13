import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/services/player_level_service.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/theme/app_themes.dart';
import 'locker_tile.dart';

/// "Table theme" tab — the app-wide visual theme. Level-gated like the rest
/// of the Locker's cosmetics: Classic Felt is free, the other 12 themes
/// unlock as the player levels up.
class LockerThemeTab extends ConsumerWidget {
  const LockerThemeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);
    final level = PlayerLevelService.instance.currentLevel.value;

    final unlockedIndices = <int>[];
    final lockedIndices = <int>[];
    for (var i = 0; i < kAppThemes.length; i++) {
      if (kAppThemes[i].minUnlockLevel <= level) {
        unlockedIndices.add(i);
      } else {
        lockedIndices.add(i);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        const LockerSectionLabel('Unlocked'),
        _themeGrid(
          unlockedIndices,
          activeIndex: themeState.activeIndex,
          onTap: (index) {
            HapticFeedback.selectionClick();
            notifier.setTheme(index);
          },
        ),
        const LockerSectionLabel('Locked'),
        _themeGrid(
          lockedIndices,
          activeIndex: themeState.activeIndex,
          locked: true,
          onTap: (index) {
            final theme = kAppThemes[index];
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Reach level ${theme.minUnlockLevel} to unlock this theme.',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _themeGrid(
    List<int> indices, {
    required int activeIndex,
    required void Function(int index) onTap,
    bool locked = false,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: indices.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemBuilder: (context, i) {
        final index = indices[i];
        final theme = kAppThemes[index];
        final isActive = activeIndex == index;
        return LockerTile(
          label: theme.name,
          state: locked
              ? LockerTileState.lockedByLevel
              : isActive
                  ? LockerTileState.selected
                  : LockerTileState.owned,
          lockCaption: locked ? 'Level ${theme.minUnlockLevel}' : null,
          preview: _ThemeSwatch(theme: theme),
          onTap: () => onTap(index),
        );
      },
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final swatch = theme.swatchPreview;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: swatch.isNotEmpty
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: swatch,
              )
            : null,
      ),
    );
  }
}
