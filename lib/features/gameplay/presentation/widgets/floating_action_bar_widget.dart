import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/audio_service.dart' as game_audio;
import '../../../../services/game_sound.dart';
import '../../../../core/models/game_state.dart';
import '../../../../core/theme/app_colors.dart';
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

  /// True when it is the local player's turn — left slot shows animated direction.
  /// When false (and [lastCardsEnabled]), left slot shows Last Cards.
  final bool isLocalTurn;

  /// Grey out / disable Last Cards after it was pressed.
  final bool hasAlreadyDeclared;

  /// When false (e.g. Bust), left slot always shows direction; Last Cards is hidden.
  final bool lastCardsEnabled;

  /// Local player's current hand size (drives one-time highlight when crossing to ≤5).
  final int localHandSize;

  final VoidCallback? onLastCards;

  const FloatingActionBarWidget({
    super.key,
    required this.activePlayerName,
    required this.direction,
    required this.canEndTurn,
    this.onEndTurn,
    this.compact = false,
    this.pulseLocalTurn = false,
    this.nextTurnLabel,
    this.isLocalTurn = false,
    this.hasAlreadyDeclared = false,
    this.lastCardsEnabled = true,
    this.localHandSize = 0,
    this.onLastCards,
  });

  /// When true, uses smaller padding/fonts for landscape layout.
  final bool compact;

  @override
  ConsumerState<FloatingActionBarWidget> createState() =>
      _FloatingActionBarWidgetState();
}

class _FloatingActionBarWidgetState extends ConsumerState<FloatingActionBarWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _directionRotateCtrl;

  /// Bumps when hand size crosses from strictly above 5 down to 5 or below.
  int _lastCardsHighlightKey = 0;

  bool get _showDirectionLeft =>
      !widget.lastCardsEnabled || widget.isLocalTurn;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _directionRotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncPulse();
      _syncDirectionRotation();
    });
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

  /// Starts/stops the direction icon rotation (reduced motion + Last Cards slot).
  void _syncDirectionRotation() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _directionRotateCtrl.stop();
      return;
    }
    if (!_showDirectionLeft) {
      _directionRotateCtrl.stop();
      return;
    }
    if (!_directionRotateCtrl.isAnimating) {
      _directionRotateCtrl.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncDirectionRotation();
  }

  @override
  void didUpdateWidget(covariant FloatingActionBarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.localHandSize > 5 && widget.localHandSize <= 5) {
      _lastCardsHighlightKey++;
    }
    if (oldWidget.pulseLocalTurn != widget.pulseLocalTurn) {
      _syncPulse();
    }
    if (oldWidget.isLocalTurn != widget.isLocalTurn ||
        oldWidget.lastCardsEnabled != widget.lastCardsEnabled ||
        oldWidget.direction != widget.direction) {
      _syncDirectionRotation();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _directionRotateCtrl.dispose();
    super.dispose();
  }

  Widget _buildLastCardsButton({
    required bool useCompact,
    required bool isMobile,
    required double slotWidth,
    required Color accent,
    required Color accentLight,
    required Color accentDark,
    required Color surface,
    required Color textSec,
    required Color bgDeep,
  }) {
    final declared = widget.hasAlreadyDeclared;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final bump = _lastCardsHighlightKey > 0 && !disableAnim;
    final startScale = bump ? 1.25 : 1.0;
    final scaleMs = bump ? 500 : 1;
    final glowMs = bump ? 800 : 1;

    final inner = AnimatedOpacity(
      opacity: declared ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: declared
                ? [surface, surface]
                : [accentLight, accentDark],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
          boxShadow: declared
              ? null
              : [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: ElevatedButton(
          onPressed: declared ? null : widget.onLastCards,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: declared ? textSec : bgDeep,
            padding: EdgeInsets.symmetric(
              horizontal: useCompact ? 4 : (isMobile ? 6 : 8),
              vertical: useCompact ? 6 : (isMobile ? 8 : 10),
            ),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Last Cards',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: useCompact ? 9 : (isMobile ? 10 : 12),
            ),
            maxLines: 2,
          ),
        ),
      ),
    );

    final scaled = TweenAnimationBuilder<double>(
      key: ValueKey('lc-scale-$_lastCardsHighlightKey'),
      tween: Tween(begin: startScale, end: 1.0),
      duration: Duration(milliseconds: scaleMs),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child!),
      child: inner,
    );

    final withGlow = TweenAnimationBuilder<double>(
      key: ValueKey('lc-glow-$_lastCardsHighlightKey'),
      tween: Tween(begin: bump ? 1.0 : 0.0, end: 0.0),
      duration: Duration(milliseconds: glowMs),
      curve: Curves.easeOut,
      builder: (context, glowValue, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
            boxShadow: glowValue > 0.001
                ? [
                    BoxShadow(
                      color: AppColors.goldPrimary
                          .withValues(alpha: 0.6 * glowValue),
                      blurRadius: 16 * glowValue,
                      spreadRadius: 2 * glowValue,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: scaled,
    );

    return SizedBox(width: slotWidth, child: withGlow);
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

    return LayoutBuilder(
      builder: (context, constraints) {
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

        final isCw = widget.direction == PlayDirection.clockwise;
        final directionIconData =
            isCw ? Icons.rotate_right : Icons.rotate_left;
        final dirIconSize = useCompact ? 16.0 : (isMobile ? 20.0 : 24.0);
        final disableDirAnim = MediaQuery.disableAnimationsOf(context);

        Widget leftSection() {
          final double slotWidth =
              useCompact ? 64.0 : (isMobile ? 90.0 : 120.0);
          final canDeclareLastCards = widget.lastCardsEnabled &&
              widget.onLastCards != null &&
              !widget.hasAlreadyDeclared;
          final showLastCardsSlot = widget.lastCardsEnabled &&
              widget.onLastCards != null;

          Widget directionIcon({double? width}) {
            final w = width ?? slotWidth;
            final directionIconChild = Icon(
              directionIconData,
              color: accent,
              size: dirIconSize,
            );

            return SizedBox(
              width: w,
              child: Center(
                child: Semantics(
                  label: isCw
                      ? 'Play direction: clockwise'
                      : 'Play direction: counter-clockwise',
                  child: disableDirAnim
                      ? directionIconChild
                      : AnimatedBuilder(
                          animation: _directionRotateCtrl,
                          child: directionIconChild,
                          builder: (_, child) {
                            final angle = isCw
                                ? _directionRotateCtrl.value * 2 * math.pi
                                : -_directionRotateCtrl.value * 2 * math.pi;
                            return Transform.rotate(
                              angle: angle,
                              child: child,
                            );
                          },
                        ),
                ),
              ),
            );
          }

          // Opponent's turn: Last Cards slot (greyed after declaring).
          if (!widget.isLocalTurn && showLastCardsSlot) {
            return _buildLastCardsButton(
              useCompact: useCompact,
              isMobile: isMobile,
              slotWidth: slotWidth,
              accent: accent,
              accentLight: accentLight,
              accentDark: accentDark,
              surface: surface,
              textSec: textSec,
              bgDeep: bgDeep,
            );
          }

          // Your turn + not yet declared: direction + Last Cards (can declare now).
          if (widget.isLocalTurn && canDeclareLastCards) {
            final narrowLc =
                useCompact ? 72.0 : (isMobile ? 88.0 : 104.0);
            final dirW = useCompact ? 34.0 : 40.0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                directionIcon(width: dirW),
                SizedBox(width: useCompact ? 4 : 6),
                _buildLastCardsButton(
                  useCompact: useCompact,
                  isMobile: isMobile,
                  slotWidth: narrowLc,
                  accent: accent,
                  accentLight: accentLight,
                  accentDark: accentDark,
                  surface: surface,
                  textSec: textSec,
                  bgDeep: bgDeep,
                ),
              ],
            );
          }

          // Direction only (your turn after declaring, Bust, or no Last Cards).
          if (_showDirectionLeft) {
            return directionIcon();
          }

          return _buildLastCardsButton(
            useCompact: useCompact,
            isMobile: isMobile,
            slotWidth: slotWidth,
            accent: accent,
            accentLight: accentLight,
            accentDark: accentDark,
            surface: surface,
            textSec: textSec,
            bgDeep: bgDeep,
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
              leftSection(),

              Container(
                width: 1,
                height: useCompact ? 18 : 24,
                color: accentDark.withValues(alpha: 0.3),
                margin: EdgeInsets.symmetric(horizontal: useCompact ? 4 : 8),
              ),

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

              SizedBox(
                width: useCompact ? 64.0 : (isMobile ? 90.0 : 120.0),
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
