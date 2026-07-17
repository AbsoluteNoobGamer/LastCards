import 'package:flutter/material.dart';

import 'avatar_catalog.dart';

/// Renders a catalog avatar (static asset, optional subtle pulse when animated).
class AvatarFace extends StatefulWidget {
  const AvatarFace({
    super.key,
    required this.design,
    required this.size,
  });

  final AvatarDesign design;
  final double size;

  @override
  State<AvatarFace> createState() => _AvatarFaceState();
}

class _AvatarFaceState extends State<AvatarFace>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.design.animated) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant AvatarFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design.animated != widget.design.animated) {
      _pulse?.dispose();
      _pulse = null;
      if (widget.design.animated) {
        _pulse = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1600),
        )..repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = Image.asset(
      widget.design.assetPath,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: const ColoredBox(color: Color(0xFF1A2E1A)),
      ),
    );

    final clipped = ClipOval(child: img);
    final pulse = _pulse;
    if (pulse == null) return clipped;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final t = 0.96 + 0.04 * pulse.value;
        return Transform.scale(scale: t, child: child);
      },
      child: clipped,
    );
  }
}
