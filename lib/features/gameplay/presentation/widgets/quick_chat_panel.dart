import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/reaction_wheel_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/services/player_level_service.dart';
import '../../../../shared/constants/quick_chat_messages.dart';
import '../../../../shared/reactions/built_in_reaction_widgets.dart';

export '../../../../shared/constants/quick_chat_messages.dart' show kQuickMessages;

/// In-game picker: one tap per starter-row slot ([reactionWheelProvider] indices).
class QuickChatPanel extends ConsumerWidget {
  const QuickChatPanel({
    required this.onMessageSelected,
    this.embedded = false,
    super.key,
  });

  /// Receives catalog **wire index** (`messageIndex` / `QuickChatAction`).
  final void Function(int messageWireIndex) onMessageSelected;

  /// When true, skips the outer glass chrome (parent panel already provides it).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final wheel = ref.watch(reactionWheelProvider);
    final level = PlayerLevelService.instance.currentLevel.value;

    final grid = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < wheel.length; i++)
            _ReactionSlotButton(
              catalogId: wheel[i],
              playerLevel: level,
              accent: theme.accentDark,
              onTap: () {
                if (!isReactionUnlockedForLevel(wheel[i], level)) return;
                onMessageSelected(wheel[i]);
              },
            ),
        ],
      ),
    );

    if (embedded) {
      return Align(alignment: Alignment.topCenter, child: grid);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: grid,
    );
  }
}

class _ReactionSlotButton extends StatelessWidget {
  const _ReactionSlotButton({
    required this.catalogId,
    required this.playerLevel,
    required this.accent,
    required this.onTap,
  });

  final int catalogId;
  final int playerLevel;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unlocked = isReactionUnlockedForLevel(catalogId, playerLevel);
    final def = isValidReactionWireIndex(catalogId)
        ? kReactionDefinitions[catalogId]
        : kReactionDefinitions[0];

    Widget child;
    if (def.kind == ReactionVisualKind.gifAsset && def.gifAssetPath != null) {
      child = ClipOval(
        child: Image.asset(
          def.gifAssetPath!,
          width: 34,
          height: 34,
          fit: BoxFit.cover,
        ),
      );
    } else if (def.kind == ReactionVisualKind.builtIn && def.builtInId != null) {
      child = BuiltInReactionIcon(builtInId: def.builtInId!, size: 34);
    } else {
      child = Text(
        def.unicodeLabel ?? '',
        style: const TextStyle(fontSize: 26, height: 1.0),
      );
    }

    return Opacity(
      opacity: unlocked ? 1 : 0.35,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: unlocked ? onTap : null,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.42),
              border: Border.all(
                color: accent.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(child: child),
                if (!unlocked)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Icon(Icons.lock, size: 12, color: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
