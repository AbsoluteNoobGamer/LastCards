import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/player_level_service.dart';
import '../theme/app_colors.dart';

/// Animated gold / violet particles and rotating aura around the avatar when
/// the local player reaches [PlayerLevelService.prestigeAvatarUnlockLevel].
class PrestigeAvatarFrame extends StatefulWidget {
  const PrestigeAvatarFrame({
    super.key,
    required this.child,
    required this.avatarRadius,
    this.showGoldBorderWhenInactive = true,
    this.inactiveBorderColor,
    this.inactiveBorderWidth = 3,
  });

  /// Inner [CircleAvatar] radius (not including any border).
  final double avatarRadius;

  /// Avatar widget (typically a [CircleAvatar]).
  final Widget child;

  /// When level is below prestige, wrap the child in the standard gold ring.
  final bool showGoldBorderWhenInactive;

  /// Border when inactive; defaults to [AppColors.goldPrimary] if null.
  final Color? inactiveBorderColor;

  /// Width of the inactive border.
  final double inactiveBorderWidth;

  @override
  State<PrestigeAvatarFrame> createState() => _PrestigeAvatarFrameState();
}

class _PrestigeAvatarFrameState extends State<PrestigeAvatarFrame>
    with TickerProviderStateMixin {
  late final AnimationController _rotateController;
  late final AnimationController _sparkleController;
  late final VoidCallback _levelListener;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _levelListener = _onLevelChanged;
    PlayerLevelService.instance.currentLevel.addListener(_levelListener);
    _syncControllersToLevel();
  }

  void _onLevelChanged() {
    _syncControllersToLevel();
    setState(() {});
  }

  void _syncControllersToLevel() {
    final on = PlayerLevelService.instance.currentLevel.value >=
        PlayerLevelService.prestigeAvatarUnlockLevel;
    if (on) {
      if (!_rotateController.isAnimating) _rotateController.repeat();
      if (!_sparkleController.isAnimating) _sparkleController.repeat();
    } else {
      _rotateController.stop();
      _sparkleController.stop();
    }
  }

  @override
  void dispose() {
    PlayerLevelService.instance.currentLevel.removeListener(_levelListener);
    _rotateController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prestige = PlayerLevelService.instance.currentLevel.value >=
        PlayerLevelService.prestigeAvatarUnlockLevel;

    if (!prestige) {
      if (!widget.showGoldBorderWhenInactive) {
        return widget.child;
      }
      final borderColor =
          widget.inactiveBorderColor ?? AppColors.goldPrimary;
      return Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: borderColor,
            width: widget.inactiveBorderWidth,
          ),
        ),
        child: widget.child,
      );
    }

    final ring = widget.avatarRadius * 0.42;
    final totalSide = (widget.avatarRadius + ring) * 2;

    return SizedBox(
      width: totalSide,
      height: totalSide,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _rotateController,
          _sparkleController,
        ]),
        builder: (context, _) {
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PrestigeAuraPainter(
                      rotation: _rotateController.value * 2 * math.pi,
                      sparklePhase: _sparkleController.value * 2 * math.pi,
                      avatarRadius: widget.avatarRadius,
                      ringExtra: ring,
                    ),
                  ),
                ),
              ),
              widget.child,
            ],
          );
        },
      ),
    );
  }
}

class _PrestigeAuraPainter extends CustomPainter {
  _PrestigeAuraPainter({
    required this.rotation,
    required this.sparklePhase,
    required this.avatarRadius,
    required this.ringExtra,
  });

  final double rotation;
  final double sparklePhase;
  final double avatarRadius;
  final double ringExtra;

  static const Color _gold = AppColors.goldPrimary;
  static const Color _goldLight = AppColors.goldLight;
  static const Color _violet = Color(0xFF9B59FF);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = avatarRadius + ringExtra;

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          _gold.withValues(alpha: 0.45),
          _violet.withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const [0.35, 0.65, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: outerR + 6))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, outerR + 4, glowPaint);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.2
      ..strokeCap = StrokeCap.round;

    const segments = 5;
    for (var s = 0; s < segments; s++) {
      final start = s * (2 * math.pi / segments);
      final sweep = 2 * math.pi / segments * 0.52;
      final t = s / segments;
      arcPaint.color =
          Color.lerp(Color.lerp(_gold, _violet, t)!, _goldLight, 0.35)!;
      arcPaint.shader = null;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: outerR - 2),
        start,
        sweep,
        false,
        arcPaint,
      );
    }

    canvas.restore();

    _drawSparkleRing(
      canvas,
      center,
      avatarRadius + ringExtra * 0.55,
      16,
      rotation * 0.85,
      1.0,
    );
    _drawSparkleRing(
      canvas,
      center,
      avatarRadius + ringExtra * 0.92,
      22,
      -rotation * 1.1 + sparklePhase * 0.15,
      0.85,
    );

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..shader = SweepGradient(
        colors: [
          _goldLight.withValues(alpha: 0.95),
          _violet.withValues(alpha: 0.75),
          _gold.withValues(alpha: 0.9),
          _goldLight.withValues(alpha: 0.95),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: avatarRadius + 1));
    canvas.drawCircle(center, avatarRadius + 1.2, rimPaint);
  }

  void _drawSparkleRing(
    Canvas canvas,
    Offset center,
    double radius,
    int count,
    double angleOffset,
    double opacityScale,
  ) {
    for (var i = 0; i < count; i++) {
      final a = angleOffset + (i * 2 * math.pi / count);
      final twinkle = 0.35 +
          0.65 *
              math
                  .sin(sparklePhase * 1.4 + i * 0.7)
                  .clamp(-1.0, 1.0);
      final p = Offset(
        center.dx + radius * math.cos(a),
        center.dy + radius * math.sin(a),
      );
      final r = 1.4 + 1.8 * twinkle;
      final op = (0.25 + 0.55 * twinkle) * opacityScale;
      final dot = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.95 * op),
            _goldLight.withValues(alpha: 0.5 * op),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: p, radius: r * 2.2));
      canvas.drawCircle(p, r, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _PrestigeAuraPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.sparklePhase != sparklePhase ||
        oldDelegate.avatarRadius != avatarRadius ||
        oldDelegate.ringExtra != ringExtra;
  }
}
