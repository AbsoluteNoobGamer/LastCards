import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/player.dart';
import '../controllers/game_provider.dart';
import '../../../../core/models/ai_player_config.dart';
import '../../../../core/utils/display_name_utils.dart';
import '../../../../widgets/marquee_name.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/player_styles.dart';
import '../../../../core/providers/theme_provider.dart';

/// Wraps a player's card area with:
/// - Accent glow ring when active turn
/// - Opponent hands shown as a condensed face-down fan
/// - Card count badge

class PlayerZoneWidget extends ConsumerWidget {
  const PlayerZoneWidget({
    super.key,
    required this.player,
    this.isLocalPlayer = false,
    this.isActiveTurn = false,
    this.isTournamentFinished = false,
    this.isTournamentEliminated = false,
    this.aiConfig,
    this.child,
    this.compact = false,
  });

  final PlayerModel player;
  final bool isLocalPlayer;
  final bool isActiveTurn;
  final bool isTournamentFinished;
  final bool isTournamentEliminated;

  /// AI player config for randomised name / avatar / personality display.
  /// Null for the local human player and in tournament mode.
  final AiPlayerConfig? aiConfig;

  /// Override content (e.g. the local PlayerHandWidget). If null, renders
  /// an opponent face-down fan automatically.
  final Widget? child;

  /// When true, uses smaller padding and label for landscape layout.
  final bool compact;

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
        isActiveTurn: isActiveTurn,
        isTournamentFinished: isTournamentFinished,
        isTournamentEliminated: isTournamentEliminated,
        appTheme: appTheme,
        aiConfig: aiConfig,
      );
    }

    final isActive = isActiveTurn;

    final double baseOpacity = isActive ? 1.0 : 0.50;

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
            padding: EdgeInsets.all(compact ? 4 : AppDimensions.sm),
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
              ],
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PlayerLabel(
              player: playerWithReactiveCount,
              isActiveTurn: isActiveTurn,
              isLocalPlayer: isLocalPlayer,
              appTheme: appTheme,
              compact: compact,
            ),
            SizedBox(height: compact ? 2 : AppDimensions.xs),
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
    this.isActiveTurn = false,
    this.isTournamentFinished = false,
    this.isTournamentEliminated = false,
    this.aiConfig,
  });

  final PlayerModel player;
  final dynamic appTheme;
  final bool isActiveTurn;
  final bool isTournamentFinished;
  final bool isTournamentEliminated;
  final AiPlayerConfig? aiConfig;

  @override
  Widget build(BuildContext context) {
    final positionColor = PlayerStyles.getColor(player.tablePosition);
    final isActive = isActiveTurn;
    final hasTournamentStatus = isTournamentFinished;

    final avatarBaseColor = aiConfig?.avatarColor ?? positionColor;

    final ringColor = isActive
        ? (appTheme.accentPrimary as Color)
        : (appTheme.textSecondary as Color).withValues(alpha: 0.35);
    final ringWidth = isActive ? 3.0 : 1.5;

    // Aggressive AI gets a subtle persistent red glow even when idle.
    final isAggressive = aiConfig?.personality == AiPersonality.aggressive;
    final List<BoxShadow>? boxShadows = isActive
        ? [
            BoxShadow(
              color: ringColor.withValues(alpha: 0.55),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ]
        : isAggressive
            ? [
                BoxShadow(
                  color: const Color(0xFFFF5252).withValues(alpha: 0.30),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Avatar circle ──────────────────────────────────────────────────
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
                              : avatarBaseColor.withValues(
                                  alpha: aiConfig != null ? 0.35 : 0.20),
                          border:
                              Border.all(color: ringColor, width: ringWidth),
                          boxShadow: boxShadows,
                        ),
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.transparent,
                          child: Text(
                              aiConfig?.initials ??
                                  initialsFromDisplayName(player.displayName),
                              style: TextStyle(
                                color: isActive
                                    ? Colors.white
                                    : Colors.white
                                        .withValues(alpha: 0.85),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                        ),
                      ),
                    ),
                    // Card count badge
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

        // ── Player name (marquee when long) ───────────────────────────────────
        MarqueeName(
          text: player.displayName,
          style: AppTypography.labelSmall.copyWith(
            color: isActive
                ? (aiConfig?.nameColor ?? positionColor)
                : (appTheme.textPrimary as Color),
            fontWeight: FontWeight.w700,
          ),
          maxWidth: 96,
          textAlign: TextAlign.center,
          color: isActive
              ? (aiConfig?.nameColor ?? positionColor)
              : (appTheme.textPrimary as Color),
        ),

        // ── Tournament status badge ────────────────────────────────────────
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
    this.isActiveTurn = false,
    this.isLocalPlayer = false,
    this.compact = false,
  });

  final PlayerModel player;
  final dynamic appTheme;
  final bool isActiveTurn;
  final bool isLocalPlayer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    String? badgeText;
    Color? badgeColor;

    if (isActiveTurn && isLocalPlayer) {
      badgeText = "YOUR TURN";
      badgeColor = PlayerStyles.getColor(player.tablePosition);
    }

    final badgePadding = compact
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
        : const EdgeInsets.symmetric(horizontal: 6, vertical: 2);
    final badgeFontSize = compact ? 7.0 : 9.0;
    final iconSize = compact ? 10.0 : 14.0;
    final nameFontSize = compact ? 9.0 : null;
    final countFontSize = compact ? 8.0 : 10.0;
    final gap = compact ? 2.0 : AppDimensions.xs;

    Widget badgeWidget = const SizedBox.shrink();
    if (badgeText != null) {
      badgeWidget = Container(
        margin: EdgeInsets.only(right: gap),
        padding: badgePadding,
        decoration: BoxDecoration(
          color: (badgeColor ?? appTheme.textSecondary as Color)
              .withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(compact ? 3 : 4),
          border: Border.all(
              color: (badgeColor ?? appTheme.textSecondary as Color)
                  .withValues(alpha: 0.5),
              width: 1),
        ),
        child: Text(
          badgeText,
          style: TextStyle(
            color: badgeColor,
            fontSize: badgeFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    final positionColor = PlayerStyles.getColor(player.tablePosition);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badgeWidget,
        Transform.scale(
          scale: isActiveTurn && !compact ? 1.05 : 1.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: iconSize,
                backgroundColor: positionColor.withValues(alpha: 0.25),
                child: Text(
                  initialsFromDisplayName(player.displayName),
                  style: TextStyle(
                    color: positionColor,
                    fontSize: iconSize * 0.8,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              SizedBox(width: gap),
              MarqueeName(
                text: player.displayName,
                style: AppTypography.labelSmall.copyWith(
                  color: isActiveTurn
                      ? positionColor
                      : (appTheme.textPrimary as Color),
                  fontStyle: FontStyle.normal,
                  fontSize: nameFontSize,
                  shadows: isActiveTurn && !compact
                      ? [
                          Shadow(
                            color: positionColor.withValues(alpha: 0.8),
                            blurRadius: 8,
                          )
                        ]
                      : null,
                ),
                maxWidth: 120,
                textAlign: TextAlign.left,
                color: isActiveTurn
                    ? positionColor
                    : (appTheme.textPrimary as Color),
              ),
            ],
          ),
        ),
        SizedBox(width: gap),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 4 : 5,
            vertical: compact ? 0 : 1,
          ),
          decoration: BoxDecoration(
            color: appTheme.surfacePanel as Color,
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            border: Border.all(
                color: PlayerStyles.getColor(player.tablePosition)
                    .withValues(alpha: 0.6),
                width: 0.5),
          ),
          child: Text(
            '${player.cardCount}',
            style: AppTypography.labelSmall.copyWith(
              fontSize: countFontSize,
              color: appTheme.accentLight as Color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
