import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/game_state.dart';
import '../../../../services/audio_service.dart' as game_audio;
import '../../../../services/game_sound.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/providers/theme_provider.dart';

class FloatingActionBarWidget extends ConsumerStatefulWidget {
  final String activePlayerName;
  final PlayDirection direction;
  final bool canEndTurn;
  final VoidCallback? onEndTurn;
  final bool pulseLocalTurn;

  /// Who follows when the current turn ends (8 / K / direction). Null to hide.
  final String? nextTurnLabel;

  const FloatingActionBarWidget({
    super.key,
    required this.activePlayerName,
    required this.direction,
    required this.canEndTurn,
    this.onEndTurn,
    this.compact = false,
    this.pulseLocalTurn = false,
    this.nextTurnLabel,
  });

  /// When true, uses smaller padding/fonts for landscape layout.
  final bool compact;

  @override
  ConsumerState<FloatingActionBarWidget> createState() =>
      _FloatingActionBarWidgetState();
}

class _FloatingActionBarWidgetState extends ConsumerState<FloatingActionBarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPulse());
  }

  void _syncPulse() {
    if (!mounted) return;
    if (widget.pulseLocalTurn) {
      if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat();
      }
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
  }

  @override
  void didUpdateWidget(covariant FloatingActionBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulseLocalTurn != widget.pulseLocalTurn) _syncPulse();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final accent = theme.accentPrimary;
    final accentLight = theme.accentLight;
    final accentDark = theme.accentDark;
    final surface = theme.surfacePanel;
    final textSec = theme.textSecondary;
    final bgDeep = theme.backgroundDeep;

    final bool isCw = widget.direction == PlayDirection.clockwise;
    final String dirIcon = isCw ? '↻' : '↺';
    final String dirText = isCw ? 'Clockwise' : 'Counter-Clockwise';

    return LayoutBuilder(
      builder: (context, constraints) {
        // Use shorter dimension: in landscape, maxWidth is the long axis.
        final isMobile = math.min(constraints.maxWidth, constraints.maxHeight) <
            AppDimensions.breakpointMobile;
        final useCompact = widget.compact ||
            (isMobile && constraints.maxWidth > constraints.maxHeight);

        Widget endTurnButton() {
          return AnimatedOpacity(
            opacity: widget.canEndTurn ? 1.0 : 0.5,
            duration: const Duration(milliseconds: 250),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.canEndTurn
                      ? [accentLight, accentDark]
                      : [surface, surface],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusButton),
                boxShadow: widget.canEndTurn
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: ElevatedButton(
                onPressed: widget.canEndTurn && widget.onEndTurn != null
                    ? () {
                        HapticFeedback.heavyImpact();
                        game_audio.AudioService.instance
                            .playSound(GameSound.endTurnButton);
                        widget.onEndTurn!();
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: widget.canEndTurn ? bgDeep : textSec,
                  disabledForegroundColor: textSec,
                  padding: EdgeInsets.symmetric(
                    horizontal: useCompact ? 8 : (isMobile ? 12 : 20),
                    vertical: useCompact ? 6 : (isMobile ? 10 : 12),
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'End Turn',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: useCompact ? 11 : (isMobile ? 13 : 16),
                  ),
                ),
              ),
            ),
          );
        }

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: useCompact ? 8 : (isMobile ? AppDimensions.sm : AppDimensions.md),
            vertical: useCompact ? 4 : (isMobile ? 6 : 8),
          ),
          decoration: BoxDecoration(
            color: surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(useCompact ? 20 : 32),
            border: Border.all(
              color: accentDark.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left: Direction
              SizedBox(
                width: useCompact ? 64 : (isMobile ? 90 : 120),
                child: Row(
                  children: [
                    Icon(
                      isCw ? Icons.rotate_right : Icons.rotate_left,
                      color: accent,
                      size: useCompact ? 12 : (isMobile ? 14 : 16),
                    ),
                    SizedBox(width: useCompact ? 2 : 4),
                    Expanded(
                      child: Text(
                        '$dirIcon $dirText',
                        style: TextStyle(
                          color: textSec.withValues(alpha: 0.9),
                          fontSize: useCompact ? 9 : (isMobile ? 10 : 12),
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                width: 1,
                height: useCompact ? 18 : 24,
                color: accentDark.withValues(alpha: 0.3),
                margin: EdgeInsets.symmetric(horizontal: useCompact ? 4 : 8),
              ),

              // Center: Whose turn + next player (8 / K aware)
              Expanded(
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) {
                    final pulse = widget.pulseLocalTurn
                        ? 1.0 +
                            0.055 *
                                math.sin(_pulseCtrl.value * 2 * math.pi)
                        : 1.0;
                    final next = widget.nextTurnLabel;
                    final hasNext =
                        next != null && next.isNotEmpty;
                    return Transform.scale(
                      scale: pulse,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.activePlayerName == 'You'
                                ? 'Your Turn'
                                : "${widget.activePlayerName}'s Turn",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: accent,
                              fontSize: useCompact ? 12 : (isMobile ? 14 : 16),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (hasNext) ...[
                            SizedBox(height: useCompact ? 1 : 2),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              child: Text(
                                'Next: $next',
                                key: ValueKey(next),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: textSec.withValues(alpha: 0.92),
                                  fontSize:
                                      useCompact ? 8 : (isMobile ? 10 : 11),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),

              Container(
                width: 1,
                height: useCompact ? 18 : 24,
                color: accentDark.withValues(alpha: 0.3),
                margin: EdgeInsets.symmetric(horizontal: useCompact ? 4 : 8),
              ),

              // Right: End Turn Button
              SizedBox(
                width: useCompact ? 64 : (isMobile ? 90 : 120),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: endTurnButton(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
