import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/player.dart';
import '../controllers/game_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/player_styles.dart';
import '../../../../core/providers/theme_provider.dart';

/// Wraps a player's card area with:
/// - Accent glow ring when [isActiveTurn]
/// - 40% opacity dim + pause icon when [isSkipped]
/// - Opponent hands shown as a condensed face-down fan
/// - Card count badge

class PlayerZoneWidget extends ConsumerWidget {
  const PlayerZoneWidget({
    super.key,
    required this.player,
    this.isLocalPlayer = false,
    this.isTournamentFinished = false,
    this.isTournamentEliminated = false,
    this.child,
  });

  final PlayerModel player;
  final bool isLocalPlayer;
  final bool isTournamentFinished;
  final bool isTournamentEliminated;

  /// Override content (e.g. the local PlayerHandWidget). If null, renders
  /// an opponent face-down fan automatically.
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appTheme = ref.watch(themeProvider).theme;
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
        isTournamentFinished: isTournamentFinished,
        isTournamentEliminated: isTournamentEliminated,
        appTheme: appTheme,
      );
    }

    final isActive = player.isActiveTurn;
    final isSkipped = player.isSkipped;
    final isOffline = !player.isConnected;

    final double baseOpacity = isSkipped ? 0.40 : (isActive ? 1.0 : 0.50);

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
        builder: (context, glowValue, childWrapper) {
          return Container(
            padding: const EdgeInsets.all(AppDimensions.sm),
            decoration: BoxDecoration(
              color: isActive
                  ? appTheme.accentPrimary.withValues(alpha: glowValue * 0.13)
                  : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(AppDimensions.radiusCard + 4),
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
                        color: appTheme.textSecondary.withValues(alpha: 0.8),
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
                        color: const Color(0xFFE53935),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: appTheme.surfacePanel,
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
            _PlayerLabel(
              player: playerWithReactiveCount,
              isLocalPlayer: isLocalPlayer,
              appTheme: appTheme,
            ),
            const SizedBox(height: AppDimensions.xs),
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
    required this.appTheme,
    this.isTournamentFinished = false,
    this.isTournamentEliminated = false,
  });

  final PlayerModel player;
  final dynamic appTheme; // AppThemeData
  final bool isTournamentFinished;
  final bool isTournamentEliminated;

  @override
  Widget build(BuildContext context) {
    final color = PlayerStyles.getColor(player.tablePosition);
    final isActive = player.isActiveTurn;
    final hasTournamentStatus = isTournamentFinished;

    // Use accent for active ring, textSecondary for inactive
    final ringColor = isActive
        ? (appTheme.accentPrimary as Color)
        : (appTheme.textSecondary as Color).withValues(alpha: 0.35);
    final ringWidth = isActive ? 3.0 : 1.5;

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
                    AnimatedOpacity(
                      opacity: hasTournamentStatus ? 0.50 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive
                              ? (appTheme.accentPrimary as Color)
                                  .withValues(alpha: 0.22)
                              : color.withValues(alpha: 0.2),
                          border:
                              Border.all(color: ringColor, width: ringWidth),
                          boxShadow: isActive
                              ? [
                                  BoxShadow(
                                    color:
                                        ringColor.withValues(alpha: 0.55),
                                    blurRadius: 14,
                                    spreadRadius: 2,
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
                          color: appTheme.accentDark as Color,
                          border: Border.all(
                            color: appTheme.surfacePanel as Color,
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
              color: isActive
                  ? color
                  : (appTheme.textPrimary as Color),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (hasTournamentStatus) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isTournamentEliminated
                  ? const Color(0x22FF3333)
                  : (appTheme.accentPrimary as Color).withValues(alpha: 0.13),
              border: Border.all(
                color: isTournamentEliminated
                    ? const Color(0xFFFF3333)
                    : (appTheme.accentPrimary as Color),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isTournamentEliminated ? '✗ Eliminated' : '✓ Qualified',
              style: TextStyle(
                color: isTournamentEliminated
                    ? const Color(0xFFFF3333)
                    : (appTheme.accentPrimary as Color),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Player name label with card count badge ───────────────────────────────────

class _PlayerLabel extends StatelessWidget {
  const _PlayerLabel({
    required this.player,
    required this.appTheme,
    this.isLocalPlayer = false,
  });

  final PlayerModel player;
  final dynamic appTheme; // AppThemeData
  final bool isLocalPlayer;

  @override
  Widget build(BuildContext context) {
    String? badgeText;
    Color? badgeColor;

    if (player.isActiveTurn && isLocalPlayer) {
      badgeText = "YOUR TURN";
      badgeColor = PlayerStyles.getColor(player.tablePosition);
    }

    Widget badgeWidget = const SizedBox.shrink();
    if (badgeText != null) {
      badgeWidget = Container(
        margin: const EdgeInsets.only(right: AppDimensions.xs),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color:
              (badgeColor ?? appTheme.textSecondary as Color)
                  .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color:
                  (badgeColor ?? appTheme.textSecondary as Color)
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
                      : (appTheme.textPrimary as Color),
                  fontStyle: FontStyle.normal,
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
            color: appTheme.surfacePanel as Color,
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
              color: appTheme.accentLight as Color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
