import 'package:flutter/material.dart';

import 'animated_title_avatars.dart';
import 'avatar_catalog.dart';

/// Renders a catalog avatar.
///
/// Leaderboard titles use [AnimatedTitleAvatar] (real scene motion — stacking
/// cards, rising bust card, etc.). Other [AvatarDesign.animated] faces keep a
/// light pulse on their PNG.
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

  bool get _pngPulse =>
      widget.design.animated && !widget.design.isTitleExclusive;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant AvatarFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design.id != widget.design.id ||
        oldWidget.design.animated != widget.design.animated) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (_pngPulse) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
    } else {
      _pulse?.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.design.exclusiveKind;
    if (kind != null) {
      return AnimatedTitleAvatar(kind: kind, size: widget.size);
    }

    final size = widget.size;
    final img = Image.asset(
      widget.design.assetPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: const ColoredBox(color: Color(0xFF1A2E1A)),
      ),
    );

    final clipped = ClipOval(child: img);
    final pulse = _pulse;
    if (pulse == null) return clipped;

    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final s = 0.96 + 0.04 * pulse.value;
        return Transform.scale(scale: s, child: child);
      },
      child: clipped,
    );
  }
}
