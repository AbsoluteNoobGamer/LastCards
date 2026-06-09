import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reusable animation controllers and helpers for card interactions.
///
/// These helpers do not drive [BoxShadow] / [Shadow] blur; for animated blur,
/// use `nonNegativeShadowBlur` in core/utils/shadow_blur.dart.
///
/// Each class is a self-contained [TickerProviderStateMixin]-compatible
/// animation spec. Widgets compose these into their own [AnimationController]s.
abstract final class CardAnimations {
  // ── Durations ─────────────────────────────────────────────────────────────

  /// Card picked up from hand — 150ms ease-out
  static const Duration liftDuration = Duration(milliseconds: 150);

  /// Card played to discard pile — 300ms ease-in-out arc
  static const Duration playDuration = Duration(milliseconds: 300);

  /// Card drawn from draw pile into hand — 250ms ease-out
  static const Duration drawDuration = Duration(milliseconds: 250);

  /// 3D card flip (back → face) — 400ms ease-in-out
  static const Duration flipDuration = Duration(milliseconds: 400);

  /// Hand reflow after a card is played — 200ms ease-out
  static const Duration reflowDuration = Duration(milliseconds: 200);

  // ── Curves ────────────────────────────────────────────────────────────────

  static const Curve liftCurve = Curves.easeOut;
  static const Curve playCurve = Curves.easeInOut;
  static const Curve drawCurve = Curves.easeOut;
  static const Curve flipCurve = Curves.easeInOut;
  static const Curve reflowCurve = Curves.easeOut;
}

// ── Card flip widget ──────────────────────────────────────────────────────────

/// A true 3D Y-axis perspective flip from [front] to [back].
///
/// The transform is built with a real perspective entry
/// (`Matrix4..setEntry(3, 2, perspective)`) and rotates the card by an [angle]
/// that runs from `0` to `pi` across the animation. Once `angle` passes
/// `pi / 2` the [back] face is shown and counter-rotated by `pi` so its
/// contents are not mirrored.
///
/// Drive the flip with [flipped]. When reduce-motion is active the flip snaps
/// straight to its final face instead of animating; by default that follows the
/// app-wide setting (folded into [MediaQuery.disableAnimationsOf]), but a
/// [reduceMotion] override may be supplied.
///
/// This is the single perspective-flip implementation in the app —
/// `widgets/card_flip_widget.dart` is a thin wrapper over it.
class CardFlipWidget extends StatefulWidget {
  const CardFlipWidget({
    super.key,
    required this.front,
    required this.back,
    this.flipped = false,
    this.perspective = 0.0015,
    this.reduceMotion,
    this.duration = CardAnimations.flipDuration,
    this.onFlipComplete,
  });

  final Widget front;
  final Widget back;

  /// When true the card settles on [back]; when false it settles on [front].
  final bool flipped;

  /// Perspective strength fed to `Matrix4..setEntry(3, 2, perspective)`.
  final double perspective;

  /// Snaps instantly to the final face instead of animating. When null, the
  /// app-wide reduce-motion setting ([MediaQuery.disableAnimationsOf]) is used.
  final bool? reduceMotion;

  final Duration duration;
  final VoidCallback? onFlipComplete;

  @override
  State<CardFlipWidget> createState() => _CardFlipWidgetState();
}

class _CardFlipWidgetState extends State<CardFlipWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = CurvedAnimation(
      parent: _controller,
      curve: CardAnimations.flipCurve,
    );

    if (widget.flipped) _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(CardFlipWidget old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.flipped && !old.flipped) {
      _controller.forward().whenComplete(() => widget.onFlipComplete?.call());
    } else if (!widget.flipped && old.flipped) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _reduceMotion =>
      widget.reduceMotion ?? MediaQuery.disableAnimationsOf(context);

  @override
  Widget build(BuildContext context) {
    // Reduce motion: snap to the resolved face, no perspective animation.
    if (_reduceMotion) {
      return widget.flipped ? widget.back : widget.front;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final angle = _animation.value * math.pi;
        final showBack = angle > math.pi / 2;

        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, widget.perspective)
            ..rotateY(angle),
          alignment: Alignment.center,
          child: showBack
              ? Transform(
                  // Counter-rotate so the back face reads correctly (not mirrored).
                  transform: Matrix4.identity()..rotateY(math.pi),
                  alignment: Alignment.center,
                  child: widget.back,
                )
              : widget.front,
        );
      },
    );
  }
}

// ── Slide arc to discard pile ─────────────────────────────────────────────────

/// Animated widget that slides from its initial position to [targetOffset].
/// Used for the card-play animation from hand to the center pile.
class CardPlaySlideWidget extends StatefulWidget {
  const CardPlaySlideWidget({
    super.key,
    required this.child,
    required this.targetOffset,
    this.onComplete,
  });

  final Widget child;
  final Offset targetOffset;
  final VoidCallback? onComplete;

  @override
  State<CardPlaySlideWidget> createState() => _CardPlaySlideWidgetState();
}

class _CardPlaySlideWidgetState extends State<CardPlaySlideWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CardAnimations.playDuration,
    );
    _slideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: widget.targetOffset,
    ).animate(
      CurvedAnimation(parent: _controller, curve: CardAnimations.playCurve),
    );

    _controller.forward().whenComplete(() => widget.onComplete?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (_, child) => Transform.translate(
        offset: _slideAnim.value,
        child: child,
      ),
      child: widget.child,
    );
  }
}
