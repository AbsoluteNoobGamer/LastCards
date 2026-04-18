import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:last_cards/core/providers/theme_provider.dart';
import 'package:last_cards/core/theme/app_dimensions.dart';
import 'package:last_cards/core/theme/app_typography.dart';
import 'package:last_cards/core/utils/display_name_utils.dart';
import 'package:last_cards/widgets/marquee_name.dart';
import 'package:last_cards/features/gameplay/presentation/widgets/player_zone_widget.dart'
    show QuickChatBubbleData, SkipSeatHighlightOverlay;
import 'package:last_cards/features/gameplay/presentation/widgets/quick_chat_bubble.dart';
import '../models/bust_player_view_model.dart';

class BustPlayerSlot extends ConsumerWidget {
  const BustPlayerSlot({
    super.key,
    required this.player,
    this.compact = false,
    this.showThinking = false,
    this.chatBubble,
    this.onRemoveQuickChatBubble,
    this.skipSeatHighlight = false,
  });

  final BustPlayerViewModel player;
  final bool showThinking;

  /// When true, uses smaller avatar and text for landscape/constrained layouts.
  final bool compact;

  /// Active quick chat bubble for this player, if any.
  final QuickChatBubbleData? chatBubble;

  /// Callback to remove a bubble by id.
  final void Function(String id)? onRemoveQuickChatBubble;
  final bool skipSeatHighlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    final Color borderColor;
    final double borderWidth;
    final Color bgColor;
    final List<BoxShadow> shadows;

    if (player.isEliminated) {
      borderColor = theme.textSecondary.withValues(alpha: 0.35);
      borderWidth = 1.5;
      bgColor = player.color.withValues(alpha: 0.2);
      shadows = const [];
    } else if (player.isActive) {
      borderColor = theme.accentPrimary;
      borderWidth = 3.0;
      bgColor = theme.accentPrimary.withValues(alpha: 0.22);
      shadows = [
        BoxShadow(
          color: theme.accentPrimary.withValues(alpha: 0.55),
          blurRadius: 14,
          spreadRadius: 2,
        ),
      ];
    } else {
      borderColor = theme.textSecondary.withValues(alpha: 0.35);
      borderWidth = 1.5;
      bgColor = player.color.withValues(alpha: 0.2);
      shadows = const [];
    }

    final avatarSize = compact ? 44.0 : 60.0;
    final badgeSize = compact ? 18.0 : 22.0;
    final slotWidth = compact ? 56.0 : 80.0;
    final iconSize = compact ? 20.0 : 28.0;

    Widget slot = SizedBox(
      width: slotWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: shadows,
                ),
                child: Center(
                  child: Text(
                    initialsFromDisplayName(player.displayName),
                    style: TextStyle(
                      color: player.isEliminated
                          ? player.color.withValues(alpha: 0.7)
                          : Colors.white.withValues(
                              alpha: player.isActive ? 1.0 : 0.9),
                      fontSize: iconSize * 0.85,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              if (showThinking)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 2,
                  child: IgnorePointer(
                    child: Center(
                      child: Text(
                        '···',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 12 : 16,
                          fontWeight: FontWeight.w900,
                          shadows: const [
                            Shadow(blurRadius: 4, color: Colors.black87),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: badgeSize,
                  height: badgeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.accentDark,
                    border: Border.all(
                      color: theme.surfacePanel,
                      width: compact ? 1.0 : 1.5,
                    ),
                  ),
                  child: Text(
                    player.isEliminated ? 'X' : '${player.cardCount}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 9 : 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 2 : AppDimensions.xs),
          MarqueeName(
            text: player.displayName,
            style: AppTypography.labelSmall.copyWith(
              color: player.isActive ? player.color : theme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 9 : null,
            ),
            maxWidth: slotWidth,
            textAlign: TextAlign.center,
            color: player.isActive ? player.color : theme.textPrimary,
          ),
          if (chatBubble != null && onRemoveQuickChatBubble != null) ...[
            const SizedBox(height: 4),
            Center(
              child: QuickChatBubble(
                key: ValueKey(chatBubble!.id),
                playerName: chatBubble!.playerName,
                message: chatBubble!.message,
                isLocal: chatBubble!.isLocal,
                tailPointsUp: true,
                onDismiss: () =>
                    onRemoveQuickChatBubble!(chatBubble!.id),
              ),
            ),
          ],
          // ── Tournament status badge (qualified/eliminated) ─────────────────
          if (player.isTournamentFinished) ...[
            SizedBox(height: compact ? 2 : 4),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 6,
                vertical: compact ? 1 : 2,
              ),
              decoration: BoxDecoration(
                color: player.isTournamentEliminated
                    ? const Color(0x22FF3333)
                    : theme.accentPrimary.withValues(alpha: 0.13),
                border: Border.all(
                  color: player.isTournamentEliminated
                      ? const Color(0xFFFF3333)
                      : theme.accentPrimary,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                player.isTournamentEliminated ? '✗ Eliminated' : '✓ Qualified',
                style: TextStyle(
                  color: player.isTournamentEliminated
                      ? const Color(0xFFFF3333)
                      : theme.accentPrimary,
                  fontSize: compact ? 8 : 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (player.isEliminated) {
      slot = Opacity(opacity: 0.40, child: slot);
    } else if (player.isTournamentFinished) {
      slot = Opacity(opacity: 0.50, child: slot);
    }

    if (skipSeatHighlight) {
      slot = SkipSeatHighlightOverlay(
        active: true,
        theme: theme,
        child: slot,
      );
    }

    return slot;
  }
}
