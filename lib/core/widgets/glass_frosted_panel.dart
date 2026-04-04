import 'dart:ui';

import 'package:flutter/material.dart';

/// Frosted glass panel: blurs pixels behind its bounds and composites a light tint.
///
/// Tuned for use on busy, colorful backgrounds (gradients, photos). Uses a
/// strong blur plus a very light tint so the backdrop stays visible — the main
/// cue for “glass” vs a flat translucent pill.
class GlassFrostedPanel extends StatelessWidget {
  const GlassFrostedPanel({
    super.key,
    required this.borderRadius,
    required this.accent,
    required this.accentLight,
    required this.child,
    this.shimmerAnimation,
    this.shimmerBandBuilder,
  });

  final double borderRadius;
  final Color accent;
  final Color accentLight;
  final Widget child;

  /// When non-null, [shimmerBandBuilder] is invoked each frame with this value (0–1).
  final Animation<double>? shimmerAnimation;
  final Widget Function(BuildContext context, double t)? shimmerBandBuilder;

  static const double _blurOuter = 22;
  static const double _blurInner = 20;

  @override
  Widget build(BuildContext context) {
    final innerR = borderRadius > 2 ? borderRadius - 1 : borderRadius;

    Widget glassStack = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
      children: [
        // Base: minimal cool-white + accent wash — keep alphas low so blur reads.
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.62),
              width: 1.15,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(Colors.white, const Color(0xFFE8F4FF), 0.35)!
                    .withValues(alpha: 0.11),
                Colors.white.withValues(alpha: 0.04),
                accent.withValues(alpha: 0.055),
              ],
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
        // Inner rim (specular inner edge).
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(1.25),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(innerR),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
        // Left edge catch (vertical highlight).
        Positioned(
          top: 8,
          bottom: 8,
          left: 1,
          width: 2,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Top specular band.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 40,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(innerR),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.38),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Top-left glint.
        Positioned(
          top: -36,
          left: -28,
          child: IgnorePointer(
            child: ClipOval(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.68],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Bottom depth (grounding shadow inside the glass).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 44,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(borderRadius - 1),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.16),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (shimmerAnimation != null && shimmerBandBuilder != null)
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: shimmerAnimation!,
                  builder: (context, _) {
                    return shimmerBandBuilder!(
                      context,
                      shimmerAnimation!.value,
                    );
                  },
                ),
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
        child,
      ],
    );

    // Two blur passes on the same backdrop read as heavier “frost” than one pass.
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: _blurOuter,
          sigmaY: _blurOuter,
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: _blurInner,
            sigmaY: _blurInner,
          ),
          child: glassStack,
        ),
      ),
    );
  }
}
