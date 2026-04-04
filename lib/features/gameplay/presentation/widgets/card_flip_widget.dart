import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 3D Y-axis flip between a card face and back (design spec: 400ms ease-in-out).
class CardFlipWidget extends StatefulWidget {
  const CardFlipWidget({
    super.key,
    required this.showFace,
    required this.front,
    required this.back,
    this.duration = const Duration(milliseconds: 400),
  });

  /// When true, [front] is shown (rotation settles at 0); when false, [back].
  final bool showFace;
  final Widget front;
  final Widget back;
  final Duration duration;

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
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.value = widget.showFace ? 0.0 : 1.0;
  }

  @override
  void didUpdateWidget(CardFlipWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
    if (oldWidget.showFace != widget.showFace) {
      if (widget.showFace) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.showFace ? widget.front : widget.back;
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;
        final angle = t * math.pi;
        final isFront = angle < math.pi / 2;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..rotateY(angle);
        return Transform(
          transform: matrix,
          alignment: Alignment.center,
          child: isFront
              ? widget.front
              : Transform(
                  transform: Matrix4.identity()..rotateY(math.pi),
                  alignment: Alignment.center,
                  child: widget.back,
                ),
        );
      },
    );
  }
}
