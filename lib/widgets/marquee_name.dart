import 'dart:math';

import 'package:flutter/material.dart';

/// Displays player names. When the text overflows the available width,
/// it scrolls horizontally (marquee) so the full name is readable.
class MarqueeName extends StatefulWidget {
  const MarqueeName({
    super.key,
    required this.text,
    required this.style,
    this.maxWidth = 96,
    this.textAlign = TextAlign.center,
    this.color,
  });

  final String text;
  final TextStyle style;
  final double maxWidth;
  final TextAlign textAlign;
  final Color? color;

  @override
  State<MarqueeName> createState() => _MarqueeNameState();
}

class _MarqueeNameState extends State<MarqueeName>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Laid-out width and height for [widget.text], using the same scaling as
  /// rendered [Text] (including [MediaQuery.textScalerOf]).
  Size _textMetrics(BuildContext context) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: (widget.color != null
                ? widget.style.copyWith(color: widget.color)
                : widget.style)
            .copyWith(inherit: true),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final size = Size(textPainter.width, textPainter.height);
    textPainter.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = min(widget.maxWidth, constraints.maxWidth);
        if (availableWidth <= 0) return const SizedBox.shrink();

        final metrics = _textMetrics(context);
        final textWidth = metrics.width;
        final overflows = textWidth > availableWidth;

        if (!overflows) {
          _controller.stop();
          _controller.reset();
          return SizedBox(
            width: availableWidth,
            child: Text(
              widget.text,
              style: widget.color != null
                  ? widget.style.copyWith(color: widget.color)
                  : widget.style,
              textAlign: widget.textAlign,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        }

        const gap = 24.0;
        final totalScroll = textWidth + gap;
        final lineHeight = metrics.height;

        return SizedBox(
          width: availableWidth,
          height: lineHeight,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                if (!_controller.isAnimating) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_controller.isAnimating) {
                      _controller.repeat();
                    }
                  });
                }
                // [Stack] + [clipBehavior] clips the wide Row without tripping
                // RenderFlex overflow (Transform + Row did). Outer [SizedBox]
                // height is required so the stack has a non-zero size.
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.centerLeft,
                  children: [
                    Positioned(
                      left: -_animation.value * totalScroll,
                      top: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.text,
                            style: widget.color != null
                                ? widget.style.copyWith(color: widget.color)
                                : widget.style,
                            maxLines: 1,
                          ),
                          SizedBox(width: gap),
                          Text(
                            widget.text,
                            style: widget.color != null
                                ? widget.style.copyWith(color: widget.color)
                                : widget.style,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
