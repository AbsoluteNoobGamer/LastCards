import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/game_state.dart';
import '../../../../core/providers/theme_provider.dart';
import 'stack_block_banner_overlay.dart' show GlobalKeyFollower;

/// Matches [LastCardsTableStrip] inline chip width.
const double kDirectionReversalBannerMaxWidth = 340;

/// Nudge below the suit-lock HUD centre.
const double kDirectionReversalBannerYOffset = 10;

class TurnIndicatorOverlay extends ConsumerStatefulWidget {
  final PlayDirection direction;

  /// True only in the frame(s) after a King was played this turn.
  final bool kingJustPlayed;

  /// Where the “direction reversed” banner sits (below central draw/discard).
  final Alignment bannerAlignment;

  /// When set, scales the banner down so it fits within this width.
  final double? maxWidth;

  /// Tablet/desktop scale multiplier (1.0 on phones).
  final double scale;

  const TurnIndicatorOverlay({
    super.key,
    required this.direction,
    this.kingJustPlayed = false,
    this.bannerAlignment = const Alignment(0, 0.20),
    this.maxWidth,
    this.scale = 1.0,
  });

  @override
  ConsumerState<TurnIndicatorOverlay> createState() =>
      _TurnIndicatorOverlayState();
}

class _TurnIndicatorOverlayState extends ConsumerState<TurnIndicatorOverlay>
    with SingleTickerProviderStateMixin {
  static const _enterMs = 500;
  static const _exitMs = 600;

  late final AnimationController _controller;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    if (widget.kingJustPlayed) {
      _playEnter();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TurnIndicatorOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.kingJustPlayed && !oldWidget.kingJustPlayed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        HapticFeedback.mediumImpact();
      });
      _playEnter();
    } else if (!widget.kingJustPlayed && oldWidget.kingJustPlayed) {
      _playExit();
    }
  }

  Future<void> _playEnter() async {
    _controller.stop();
    setState(() => _visible = true);
    _controller.duration = const Duration(milliseconds: _enterMs);
    await _controller.forward(from: 0);
  }

  Future<void> _playExit() async {
    _controller.duration = const Duration(milliseconds: _exitMs);
    await _controller.reverse(from: 1);
    if (mounted) {
      setState(() => _visible = false);
    }
  }

  Widget _bannerChip(String symbol) {
    final scale = widget.scale;
    final maxWidth = (widget.maxWidth ?? kDirectionReversalBannerMaxWidth) * scale;
    final theme = ref.watch(themeProvider).theme;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsets.symmetric(horizontal: 18 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: theme.accentDark.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(
          color: theme.accentLight.withValues(alpha: 0.95),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        '$symbol Direction reversed',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: theme.backgroundDeep,
          fontSize: 15 * scale,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _animatedBanner(String symbol, double t) {
    final opacity = Curves.easeOut.transform(t.clamp(0.0, 1.0));
    final offsetX = math.sin(t * math.pi * 3) * 5 * (1 - t);
    final scale = 0.92 + (t * 0.08);
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(offsetX, 0),
        child: Transform.scale(
          scale: scale,
          child: _bannerChip(symbol),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCw = widget.direction == PlayDirection.clockwise;
    final String symbol = isCw ? '↻' : '↺';

    return IgnorePointer(
      child: Stack(
        fit: StackFit.loose,
        clipBehavior: Clip.none,
        children: [
          Align(
            alignment: widget.bannerAlignment,
            child: _visible
                ? AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) =>
                        _animatedBanner(symbol, _controller.value),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Positions the direction-reversal banner over the suit-lock HUD slot.
class DirectionBannerAtHud extends StatelessWidget {
  const DirectionBannerAtHud({
    super.key,
    required this.hudKey,
    required this.direction,
    required this.kingJustPlayed,
    this.minTop,
    this.scale = 1.0,
  });

  final GlobalKey hudKey;
  final PlayDirection direction;
  final bool kingJustPlayed;

  /// Floors the banner's top so it stays below the move log band.
  final double? minTop;

  /// Tablet/desktop scale multiplier (1.0 on phones).
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        GlobalKeyFollower(
          targetKey: hudKey,
          targetAnchor: Alignment.center,
          childAnchor: Alignment.center,
          offset: Offset(0, kDirectionReversalBannerYOffset * scale),
          minTop: minTop,
          scale: scale,
          child: TurnIndicatorOverlay(
            direction: direction,
            kingJustPlayed: kingJustPlayed,
            maxWidth: kDirectionReversalBannerMaxWidth,
            bannerAlignment: Alignment.center,
            scale: scale,
          ),
        ),
      ],
    );
  }
}

