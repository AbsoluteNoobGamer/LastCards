import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/player.dart';
import '../controllers/game_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/player_styles.dart';

/// Wraps a player's card area with:
/// - Gold glow ring when [isActiveTurn]
/// - 40% opacity dim + pause icon when [isSkipped]
/// - Opponent hands shown as a condensed face-down fan
/// - Card count badge

class PlayerZoneWidget extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final liveGameState = ref.watch(gameStateProvider);
    final livePlayers = liveGameState?.players ?? const [];
    var reactiveCardCount = player.cardCount;
    for (final p in livePlayers) {
      if (p.id == player.id) {
        reactiveCardCount = p.cardCount;
        break;
      }
    }
    final playerWithReactiveCount =
        player.copyWith(cardCount: reactiveCardCount);

    if (!isLocalPlayer && child == null) {
      return _OpponentAvatarZone(
        player: playerWithReactiveCount,
        isNextTurn: isNextTurn,
      );
    }

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
              color: isActive
                  ? AppColors.goldPrimary.withValues(alpha: glowValue * 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimensions.radiusCard + 4),
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
              player: playerWithReactiveCount,
              isLocalPlayer: isLocalPlayer,
              isNextTurn: isNextTurn,
            ),
            const SizedBox(height: AppDimensions.xs),

            // Content
            child ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

class _OpponentAvatarZone extends StatelessWidget {
  const _OpponentAvatarZone({
    required this.player,
    required this.isNextTurn,
  });

  final PlayerModel player;
  final bool isNextTurn;

  @override
  Widget build(BuildContext context) {
    final color = PlayerStyles.getColor(player.tablePosition);
    final isActive = player.isActiveTurn;

    final ringColor = isActive
        ? color
        : (isNextTurn
            ? AppColors.blueAccent
            : AppColors.textSecondary.withValues(alpha: 0.35));
    final ringWidth = isActive ? 3.0 : (isNextTurn ? 2.2 : 1.5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(36),
            onTap: () {},
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppDimensions.minTouchTarget,
                minHeight: AppDimensions.minTouchTarget,
              ),
              child: SizedBox(
                width: 68,
                height: 68,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? AppColors.goldPrimary.withValues(alpha: 0.22)
                            : color.withValues(alpha: 0.2),
                        border: Border.all(color: ringColor, width: ringWidth),
                        boxShadow: isActive || isNextTurn
                            ? [
                                BoxShadow(
                                  color: ringColor.withValues(alpha: 0.55),
                                  blurRadius: isActive ? 14 : 10,
                                  spreadRadius: isActive ? 2 : 1,
                                ),
                              ]
                            : null,
                      ),
                      child: CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.transparent,
                        child: Icon(
                          PlayerStyles.getIcon(player.tablePosition),
                          color: color,
                          size: 28,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.goldDark,
                          border: Border.all(
                            color: AppColors.surfacePanel,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '${player.cardCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 96,
          child: Text(
            player.displayName,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelSmall.copyWith(
              color: isActive ? color : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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
                            color: PlayerStyles.getColor(player.tablePosition)
                                .withValues(alpha: 0.8),
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
            border: Border.all(
                color: PlayerStyles.getColor(player.tablePosition)
                    .withValues(alpha: 0.6),
                width: 0.5),
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
