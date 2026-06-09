import 'package:flutter/material.dart';

import '../animations/card_animations.dart' as anim;

/// 3D Y-axis flip between a card face and back (design spec: 400ms ease-in-out).
///
/// Thin wrapper over the shared [anim.CardFlipWidget] so the app keeps a single
/// perspective-flip implementation. [showFace] true settles on [front], false
/// settles on [back]. Reduce-motion is handled by the shared widget via the
/// app-wide [MediaQuery.disableAnimationsOf] setting.
class CardFlipWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return anim.CardFlipWidget(
      flipped: !showFace,
      front: front,
      back: back,
      duration: duration,
    );
  }
}
