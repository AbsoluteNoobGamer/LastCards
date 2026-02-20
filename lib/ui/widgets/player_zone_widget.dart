import 'package:flutter/material.dart';

import '../../core/models/player_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'card_back_widget.dart';

/// Wraps a player's card area with:
/// - Gold glow ring when [isActiveTurn]
/// - 40% opacity dim + pause icon when [isSkipped]
/// - Opponent hands shown as a condensed face-down fan
/// - Card count badge
class PlayerZoneWidget extends StatefulWidget {
  const PlayerZoneWidget({
    super.key,
    required this.player,
    this.isLocalPlayer = false,
    this.child,
  });

  final PlayerModel player;
  final bool isLocalPlayer;

  /// Override content (e.g. the local PlayerHandWidget). If null, renders
  /// an opponent face-down fan automatically.
  final Widget? child;

  @override
  State<PlayerZoneWidget> createState() => _PlayerZoneWidgetState();
}

class _PlayerZoneWidgetState extends State<PlayerZoneWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    if (widget.player.isActiveTurn) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(PlayerZoneWidget old) {
    super.didUpdateWidget(old);
    if (widget.player.isActiveTurn && !old.player.isActiveTurn) {
      _glowController.repeat(reverse: true);
    } else if (!widget.player.isActiveTurn && old.player.isActiveTurn) {
      _glowController.stop();
      _glowController.reset();
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.player.isActiveTurn;
    final isSkipped = widget.player.isSkipped;
    final isOffline = !widget.player.isConnected;

    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (context, child) {
        return AnimatedOpacity(
          opacity: isSkipped ? 0.40 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: Container(
            padding: const EdgeInsets.all(AppDimensions.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusCard + 4),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppColors.goldPrimary
                            .withValues(alpha: _glowAnim.value * 0.6),
                        blurRadius: AppDimensions.turnGlowRadius * 2,
                        spreadRadius: AppDimensions.turnGlowRadius / 2,
                      ),
                    ]
                  : null,
              border: Border.all(
                color: isActive
                    ? AppColors.goldPrimary
                        .withValues(alpha: _glowAnim.value * 0.8)
                    : Colors.transparent,
                width: AppDimensions.turnRingWidth,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                child!,

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
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Player name + card count
          _PlayerLabel(player: widget.player),
          const SizedBox(height: AppDimensions.xs),

          // Content
          widget.child ??
              _OpponentFan(cardCount: widget.player.cardCount),
        ],
      ),
    );
  }
}

// ── Player name label with card count badge ───────────────────────────────────

class _PlayerLabel extends StatelessWidget {
  const _PlayerLabel({required this.player});

  final PlayerModel player;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          player.displayName,
          style: AppTypography.labelSmall,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(width: AppDimensions.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.surfacePanel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.goldDark, width: 0.5),
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
