import 'dart:math' as math;

/// Blur radius for [BoxShadow] and [Shadow] must be non-negative.
///
/// Use when the value is computed (e.g. from an [Animation] or tween) so a
/// brief overshoot or bad input cannot trigger framework asserts.
@pragma('vm:prefer-inline')
double nonNegativeShadowBlur(double blur) => math.max(0.0, blur);
