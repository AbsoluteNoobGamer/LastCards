import 'package:flutter/material.dart';

import '../../domain/entities/player.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/player_styles.dart';
import 'card_back_widget.dart';

/// Wraps a player's card area with:
/// - Gold glow ring when [isActiveTurn]
/// - 40% opacity dim + pause icon when [isSkipped]
/// - Opponent hands shown as a condensed face-down fan
/// - Card count badge

class PlayerZoneWidget extends StatelessWidget {
  const PlayerZoneWidget({
    super.key,
    required this.player,
    this.isLocalPlayer = false,
    this.isNextTurn = false,
    this.child,
  });

  final PlayerModel player;
  final bool isLocalPlayer;
  final bool isNextTurn;

  /// Override content (e.g. the local PlayerHandWidget). If null, renders
  /// an opponent face-down fan automatically.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final isActive = player.isActiveTurn;
    final isSkipped = player.isSkipped;
    final isOffline = !player.isConnected;

    // Inactive: 50% opacity gray (unless skipped)
    final double baseOpacity =
        isSkipped ? 0.40 : (isActive || isNextTurn ? 1.0 : 0.50);

    return AnimatedOpacity(
      opacity: baseOpacity,
      duration: const Duration(milliseconds: 300),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: isActive ? 0.9 : 0.0,
          end: isActive ? 1.0 : 0.0,
        ),
        duration: const Duration(milliseconds: 1500),
        curve: Curves.easeInOutCubic,
        onEnd: () {
          // If we want a continuous pulse, we'd need a StatefulWidget to swap the tween ends.
          // Since the user requested dropping AnimatedBuilder for TweenAnimationBuilder
          // for performance, we can just let it sit at 1.0, or quickly wrap in a stateful
          // just to flip the tween target if requested. For now, pushing to 1.0 is smooth.
          // Let's actually implement a continuous ping-pong by just rebuilding via a local state
          // if we strictly need heartbeat, but a static "on" glow is usually better for battery.
          // I will leave it static-on when active, saving repaints entirely once settled.
        },
        builder: (context, glowValue, childWrapper) {
          return Container(
            padding: const EdgeInsets.all(AppDimensions.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusCard + 4),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: PlayerStyles.getColor(player.tablePosition)
                            .withValues(alpha: glowValue * 0.8),
                        blurRadius: 15 * glowValue,
                        spreadRadius: 2 * glowValue,
                      ),
                    ]
                  : isNextTurn
                      ? [
                          BoxShadow(
                            color: AppColors.blueAccent.withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
              border: Border.all(
                color: isActive
                    ? PlayerStyles.getColor(player.tablePosition).withValues(alpha: glowValue)
                    : isNextTurn
                        ? AppColors.blueAccent.withValues(alpha: 0.8)
                        : AppColors.textSecondary
                            .withValues(alpha: 0.3), // Gray border
                width: isActive ? 2.5 : (isNextTurn ? 2.0 : 1.0),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                childWrapper!,

                // Skip indicator overlay
                if (isSkipped)
                  Positioned.fill(
                    child: Center(
                      child: Icon(
                        Icons.pause_circle_outline_rounded,
                        color: AppColors.textSecondary.withValues(alpha: 0.8),
                        size: 32,
                      ),
                    ),
                  ),

                // Offline indicator
                if (isOffline)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.redSoft,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surfacePanel,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Player name + card count
            _PlayerLabel(
              player: player,
              isLocalPlayer: isLocalPlayer,
              isNextTurn: isNextTurn,
            ),
            const SizedBox(height: AppDimensions.xs),

            // Content
            child ?? _OpponentFan(cardCount: player.cardCount),
          ],
        ),
      ),
    );
  }
}

// ── Player name label with card count badge ───────────────────────────────────

class _PlayerLabel extends StatelessWidget {
  const _PlayerLabel({
    required this.player,
    this.isLocalPlayer = false,
    this.isNextTurn = false,
  });

  final PlayerModel player;
  final bool isLocalPlayer;
  final bool isNextTurn;

  @override
  Widget build(BuildContext context) {
    // Determine badge text
    String? badgeText;
    Color? badgeColor;

    if (player.isActiveTurn && isLocalPlayer) {
      badgeText = "YOUR TURN";
      badgeColor = PlayerStyles.getColor(player.tablePosition);
    } else if (!player.isActiveTurn && isLocalPlayer) {
      badgeText = "Waiting...";
      badgeColor = AppColors.textSecondary;
    }

    Widget badgeWidget = const SizedBox.shrink();
    if (badgeText != null) {
      badgeWidget = Container(
        margin: const EdgeInsets.only(right: AppDimensions.xs),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color:
              (badgeColor ?? AppColors.textSecondary).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: (badgeColor ?? AppColors.textSecondary)
                  .withValues(alpha: 0.5),
              width: 1),
        ),
        child: Text(
          badgeText,
          style: TextStyle(
            color: badgeColor,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badgeWidget,
        Transform.scale(
          scale: player.isActiveTurn ? 1.05 : 1.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PlayerStyles.getIcon(player.tablePosition),
                color: PlayerStyles.getColor(player.tablePosition),
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                player.displayName,
                style: AppTypography.labelSmall.copyWith(
                  color: player.isActiveTurn
                      ? PlayerStyles.getColor(player.tablePosition)
                      : (isNextTurn ? Colors.white : AppColors.textPrimary),
                  fontStyle: isNextTurn ? FontStyle.italic : FontStyle.normal,
                  shadows: player.isActiveTurn
                      ? [
                          Shadow(
                            color: PlayerStyles.getColor(player.tablePosition).withValues(alpha: 0.8),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppDimensions.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.surfacePanel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: PlayerStyles.getColor(player.tablePosition).withValues(alpha: 0.6), width: 0.5),
          ),
          child: Text(
            '${player.cardCount}',
            style: AppTypography.labelSmall.copyWith(
              fontSize: 10,
              color: AppColors.goldLight,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Opponent face-down card fan ───────────────────────────────────────────────

class _OpponentFan extends StatelessWidget {
  const _OpponentFan({required this.cardCount});

  final int cardCount;

  @override
  Widget build(BuildContext context) {
    const maxVisible = 7;
    final visible = cardCount.clamp(0, maxVisible);
    const cardW = AppDimensions.cardWidthSmall;
    const overlap = 18.0;

    if (visible == 0) return const SizedBox(width: cardW, height: 70);

    final totalWidth = cardW + (visible - 1) * overlap;

    return SizedBox(
      width: totalWidth,
      height: AppDimensions.cardHeight(cardW),
      child: Stack(
        children: [
          for (int i = 0; i < visible; i++)
            Positioned(
              left: i * overlap.toDouble(),
              child: const CardBackWidget(width: cardW),
            ),
        ],
      ),
    );
  }
}
