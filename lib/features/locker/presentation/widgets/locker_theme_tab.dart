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
    final trialAvailableIndices = <int>[];
    final lockedIndices = <int>[];
    for (var i = 0; i < kAppThemes.length; i++) {
      final theme = kAppThemes[i];
      final isUnlocked = theme.minUnlockLevel <= level;
      final isActiveTrial = themeState.trialThemeId == theme.id;
      if (isUnlocked || isActiveTrial) {
        unlockedIndices.add(i);
      } else if (theme.trialGames != null &&
          !themeState.trialedThemeIds.contains(theme.id)) {
        trialAvailableIndices.add(i);
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
          trialThemeId: themeState.trialThemeId,
          trialGamesRemaining: themeState.trialGamesRemaining,
          onTap: (index) {
            HapticFeedback.selectionClick();
            notifier.setTheme(index);
          },
        ),
        if (trialAvailableIndices.isNotEmpty) ...[
          const LockerSectionLabel('Trial available'),
          _themeGrid(
            trialAvailableIndices,
            activeIndex: themeState.activeIndex,
            trialAvailable: true,
            onTap: (index) => _confirmStartTrial(context, notifier, index),
          ),
        ],
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

  Future<void> _confirmStartTrial(
    BuildContext context,
    ThemeNotifier notifier,
    int index,
  ) async {
    final theme = kAppThemes[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Try ${theme.name}?'),
        content: Text(
          'You can play ${theme.trialGames} games with this theme before it '
          'reverts. This trial can only be used once.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Start trial'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      HapticFeedback.selectionClick();
      await notifier.startTrial(index);
    }
  }

  Widget _themeGrid(
    List<int> indices, {
    required int activeIndex,
    required void Function(int index) onTap,
    bool locked = false,
    bool trialAvailable = false,
    String? trialThemeId,
    int? trialGamesRemaining,
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
        final isActiveTrial = trialThemeId == theme.id;
        return LockerTile(
          label: theme.name,
          state: locked
              ? LockerTileState.lockedByLevel
              : trialAvailable
                  ? LockerTileState.trialAvailable
                  : isActive
                      ? LockerTileState.selected
                      : LockerTileState.owned,
          lockCaption: locked ? 'Level ${theme.minUnlockLevel}' : null,
          trialCaption: trialAvailable
              ? 'Trial · ${theme.trialGames} games'
              : isActiveTrial
                  ? 'Trial · $trialGamesRemaining left'
                  : null,
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
