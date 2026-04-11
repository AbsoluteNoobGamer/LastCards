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
import '../../../../core/utils/shadow_blur.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import 'quick_chat_bubble.dart';

/// Data for a quick chat bubble shown above a player's avatar.
typedef QuickChatBubbleData = ({String id, String playerName, String message, bool isLocal});

/// Opponent circle avatar diameter (must match [SizedBox] in [_OpponentAvatarZone]).
const double _kOpponentAvatarSize = 68;

/// Gap between bubble bottom and avatar top when [QuickChatBubble] is overlaid.
const double _kQuickChatBubbleGap = 6;

/// Approximate [_PlayerLabel] row height for bubble anchoring (compact vs normal).
double _localLabelBubbleBottomInset(bool compact) =>
    (compact ? 28.0 : 34.0) + _kQuickChatBubbleGap;

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
    this.hasLastCardsDeclared = false,
    this.aiConfig,
    this.child,
    this.compact = false,
    this.chatBubble,
    this.onRemoveQuickChatBubble,
    this.isAiThinking = false,
    this.skipSeatHighlight = false,
    this.onOpponentAvatarTap,
  });

  final PlayerModel player;
  /// Shows a "LAST CARDS" pill when this player has declared.
  final bool hasLastCardsDeclared;
  final bool isLocalPlayer;
  final bool isActiveTurn;
  /// Opponent seat: show "thinking" affordance while AI chooses a move.
  final bool isAiThinking;
  /// Brief dim + pause icon when this seat is skipped by an Eight.
  final bool skipSeatHighlight;
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

  /// Active quick chat bubble for this player, if any.
  final QuickChatBubbleData? chatBubble;

  /// Callback to remove a bubble by id.
  final void Function(String id)? onRemoveQuickChatBubble;

  /// Opponent seats only: tap avatar (e.g. online profile / add friend).
  final VoidCallback? onOpponentAvatarTap;

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
        return SkipSeatHighlightOverlay(
        active: skipSeatHighlight,
        theme: appTheme,
        child: _OpponentAvatarZone(
          player: playerWithReactiveCount,
          isActiveTurn: isActiveTurn,
          isAiThinking: isAiThinking,
          isTournamentFinished: isTournamentFinished,
          isTournamentEliminated: isTournamentEliminated,
          hasLastCardsDeclared: hasLastCardsDeclared,
          appTheme: appTheme,
          aiConfig: aiConfig,
          chatBubble: chatBubble,
          onRemoveQuickChatBubble: onRemoveQuickChatBubble,
          onAvatarTap: onOpponentAvatarTap,
        ),
      );
    }

    final isActive = isActiveTurn;

    final double baseOpacity = isActive ? 1.0 : 0.50;

    final zoneBody = AnimatedOpacity(
      opacity: baseOpacity,
      duration: const Duration(milliseconds: 300),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(
          begin: isActive ? 0.85 : 0.0,
          end: isActive ? 1.0 : 0.0,
        ),
        duration: Duration(milliseconds: isActive && isLocalPlayer ? 1100 : 1500),
        curve: Curves.easeInOutCubic,
        builder: (context, glowValue, childWrapper) {
          final gv = glowValue.clamp(0.0, 1.0);
          final glowMul =
              isLocalPlayer && isActive ? 0.26 : (isActive ? 0.22 : 0.16);
          return Container(
            padding: EdgeInsets.all(compact ? 4 : AppDimensions.sm),
            decoration: BoxDecoration(
              color: isActive
                  ? appTheme.accentPrimary.withValues(alpha: gv * glowMul)
                  : Colors.transparent,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: appTheme.accentPrimary
                            .withValues(alpha: 0.35 * gv),
                        blurRadius: nonNegativeShadowBlur(16 + 10 * gv),
                        spreadRadius: 1 + gv,
                      ),
                    ]
                  : null,
              borderRadius:
                  BorderRadius.circular(AppDimensions.radiusCard + 4),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                childWrapper!,
              ],
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _PlayerLabel(
                  player: playerWithReactiveCount,
                  isActiveTurn: isActiveTurn,
                  isLocalPlayer: isLocalPlayer,
                  hasLastCardsDeclared: hasLastCardsDeclared,
                  appTheme: appTheme,
                  compact: compact,
                ),
                if (chatBubble != null && onRemoveQuickChatBubble != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: _localLabelBubbleBottomInset(compact),
                    child: Center(
                      child: QuickChatBubble(
                        key: ValueKey(chatBubble!.id),
                        playerName: chatBubble!.playerName,
                        message: chatBubble!.message,
                        isLocal: chatBubble!.isLocal,
                        onDismiss: () =>
                            onRemoveQuickChatBubble!(chatBubble!.id),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: compact ? 2 : AppDimensions.xs),
            child ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );

    return SkipSeatHighlightOverlay(
      active: skipSeatHighlight,
      theme: appTheme,
      child: zoneBody,
    );
  }
}

/// Dims the whole player zone and shows a pause icon (Eight skip feedback).
class SkipSeatHighlightOverlay extends StatelessWidget {
  const SkipSeatHighlightOverlay({
    super.key,
    required this.active,
    required this.theme,
    required this.child,
  });

  final bool active;
  final AppThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Opacity(opacity: 0.42, child: child),
        IgnorePointer(
          child: Icon(
            Icons.pause_circle_outline_rounded,
            size: 36,
            color: theme.accentPrimary.withValues(alpha: 0.92),
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OpponentAvatarZone extends StatelessWidget {
  const _OpponentAvatarZone({
    required this.player,
    required this.appTheme,
    this.isActiveTurn = false,
    this.isAiThinking = false,
    this.isTournamentFinished = false,
    this.isTournamentEliminated = false,
    this.hasLastCardsDeclared = false,
    this.aiConfig,
    this.chatBubble,
    this.onRemoveQuickChatBubble,
    this.onAvatarTap,
  });

  final PlayerModel player;
  final dynamic appTheme;
  final bool isActiveTurn;
  final bool isAiThinking;
  final bool isTournamentFinished;
  final bool isTournamentEliminated;
  final bool hasLastCardsDeclared;
  final AiPlayerConfig? aiConfig;
  final QuickChatBubbleData? chatBubble;
  final void Function(String id)? onRemoveQuickChatBubble;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final positionColor = PlayerStyles.getColor(player.tablePosition);
    final isActive = isActiveTurn;
    final hasTournamentStatus = isTournamentFinished;

    final avatarBaseColor = aiConfig?.avatarColor ?? positionColor;

    final ringColor = isActive
        ? (appTheme.accentPrimary as Color)
        : (appTheme.textSecondary as Color).withValues(alpha: 0.35);
    final ringWidth = isActive ? 3.5 : 1.5;

    // Aggressive AI gets a subtle persistent red glow even when idle.
    final isAggressive = aiConfig?.personality == AiPersonality.aggressive;
    final List<BoxShadow>? boxShadows = isActive
        ? [
            BoxShadow(
              color: ringColor.withValues(alpha: 0.62),
              blurRadius: 18 + (isAiThinking ? 6 : 0),
              spreadRadius: 2 + (isAiThinking ? 1 : 0),
            ),
            BoxShadow(
              color: ringColor.withValues(alpha: isAiThinking ? 0.35 : 0.2),
              blurRadius: 28,
              spreadRadius: 0,
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

    final avatarCircle = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(36),
        onTap: onAvatarTap ?? () {},
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppDimensions.minTouchTarget,
            minHeight: AppDimensions.minTouchTarget,
          ),
          child: SizedBox(
            width: _kOpponentAvatarSize,
            height: _kOpponentAvatarSize,
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
                      border: Border.all(color: ringColor, width: ringWidth),
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
                              : Colors.white.withValues(alpha: 0.85),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (isAiThinking)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 2,
                    child: IgnorePointer(
                      child: Center(child: _ThinkingEllipsis()),
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
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            avatarCircle,
            if (chatBubble != null && onRemoveQuickChatBubble != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: _kOpponentAvatarSize + _kQuickChatBubbleGap,
                child: Center(
                  child: QuickChatBubble(
                    key: ValueKey(chatBubble!.id),
                    playerName: chatBubble!.playerName,
                    message: chatBubble!.message,
                    isLocal: chatBubble!.isLocal,
                    onDismiss: () =>
                        onRemoveQuickChatBubble!(chatBubble!.id),
                  ),
                ),
              ),
          ],
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

        if (hasLastCardsDeclared) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (appTheme.accentPrimary as Color).withValues(alpha: 0.15),
              border: Border.all(
                color: (appTheme.accentPrimary as Color),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'LAST CARDS',
              style: TextStyle(
                color: appTheme.accentPrimary as Color,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],

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
    this.hasLastCardsDeclared = false,
    this.compact = false,
  });

  final PlayerModel player;
  final dynamic appTheme;
  final bool isActiveTurn;
  final bool isLocalPlayer;
  final bool hasLastCardsDeclared;
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

    final lastCardsPill = hasLastCardsDeclared
        ? Padding(
            padding: EdgeInsets.only(right: gap),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 4 : 6,
                vertical: compact ? 1 : 2,
              ),
              decoration: BoxDecoration(
                color: (appTheme.accentPrimary as Color).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(compact ? 3 : 4),
                border: Border.all(
                  color: (appTheme.accentPrimary as Color),
                  width: 1,
                ),
              ),
              child: Text(
                'LAST CARDS',
                style: TextStyle(
                  color: appTheme.accentPrimary as Color,
                  fontSize: compact ? 6.5 : 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        badgeWidget,
        lastCardsPill,
        Transform.scale(
          scale: isActiveTurn && !compact ? 1.05 : 1.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: iconSize / 2,
                backgroundColor: positionColor.withValues(alpha: 0.25),
                child: Text(
                  initialsFromDisplayName(player.displayName),
                  style: TextStyle(
                    color: positionColor,
                    fontSize: iconSize * 0.45,
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

class _ThinkingEllipsis extends StatefulWidget {
  const _ThinkingEllipsis();

  @override
  State<_ThinkingEllipsis> createState() => _ThinkingEllipsisState();
}

class _ThinkingEllipsisState extends State<_ThinkingEllipsis>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Opacity(
        opacity: 0.4 + 0.6 * _ctrl.value,
        child: const Text(
          '···',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
          ),
        ),
      ),
    );
  }
}
