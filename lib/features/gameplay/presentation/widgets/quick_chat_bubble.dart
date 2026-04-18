import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';

/// A chat bubble for quick chat messages.
/// Shows only the message (player name is already visible near the avatar).
/// Animates in (scale 0.8 → 1.0) and out (opacity 1.0 → 0.0) before removal.
///
/// [tailPointsUp] places the tail on top of the bubble pointing toward the
/// speaker — use when the bubble sits **below** the avatar/name row.
class QuickChatBubble extends ConsumerStatefulWidget {
  const QuickChatBubble({
    required this.playerName,
    required this.message,
    required this.isLocal,
    required this.onDismiss,
    this.tailPointsUp = false,
    super.key,
  });

  final String playerName;
  final String message;
  final bool isLocal;
  final VoidCallback onDismiss;

  /// When `true`, tail is above the body and points up (bubble below speaker).
  /// When `false`, tail is below the body and points down (bubble above speaker).
  final bool tailPointsUp;

  @override
  ConsumerState<QuickChatBubble> createState() => _QuickChatBubbleState();
}

class _QuickChatBubbleState extends ConsumerState<QuickChatBubble>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late AnimationController _wobbleController;
  late Animation<double> _scaleAnimation;
  Timer? _dismissTimer;

  static bool _isExcitedMessage(String m) {
    final t = m.trim();
    if (t.isEmpty) return false;
    if (t.contains('!')) return true;
    final letters = RegExp(r'[A-Za-z]').allMatches(t).map((e) => e.group(0)!);
    if (letters.isEmpty) return false;
    return t == t.toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 240),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _wobbleController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
    _scaleController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isExcitedMessage(widget.message) &&
          !MediaQuery.disableAnimationsOf(context)) {
        _wobbleController.forward(from: 0);
      }
    });

    _dismissTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _fadeController.forward().then((_) {
        if (mounted) widget.onDismiss();
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _scaleController.dispose();
    _fadeController.dispose();
    _wobbleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final base = widget.isLocal
        ? theme.accentPrimary.withValues(alpha: 0.88)
        : theme.surfacePanel.withValues(alpha: 0.95);
    final top = Color.lerp(base, Colors.white, widget.isLocal ? 0.12 : 0.08)!;
    final bottom = Color.lerp(base, Colors.black, 0.22)!;

    final bubbleBody = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        widget.message,
        style: TextStyle(
          color: theme.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    final withTail = widget.tailPointsUp
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: -6,
                left: 0,
                right: 0,
                child: Center(
                  child: CustomPaint(
                    size: const Size(14, 8),
                    painter: _ChatBubbleTailPainter(
                      faceColor: top,
                      pointsUp: true,
                    ),
                  ),
                ),
              ),
              bubbleBody,
            ],
          )
        : Stack(
            clipBehavior: Clip.none,
            children: [
              bubbleBody,
              Positioned(
                bottom: -6,
                left: 0,
                right: 0,
                child: Center(
                  child: CustomPaint(
                    size: const Size(14, 8),
                    painter: _ChatBubbleTailPainter(
                      faceColor: bottom,
                      pointsUp: false,
                    ),
                  ),
                ),
              ),
            ],
          );

    final wobble = AnimatedBuilder(
      animation: _wobbleController,
      builder: (context, child) {
        final t = _wobbleController.value;
        final dx = math.sin(t * math.pi * 7) * 3.2 * (1.0 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: withTail,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_scaleController, _fadeController]),
      builder: (context, child) {
        final outOpacity = 1.0 - _fadeController.value;
        final inOpacity = _scaleController.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: outOpacity * (0.2 + 0.8 * inOpacity),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Padding(
              padding: widget.tailPointsUp
                  ? const EdgeInsets.only(top: AppDimensions.xs)
                  : const EdgeInsets.only(bottom: AppDimensions.xs),
              child: child,
            ),
          ),
        );
      },
      child: wobble,
    );
  }
}

class _ChatBubbleTailPainter extends CustomPainter {
  _ChatBubbleTailPainter({required this.faceColor, required this.pointsUp});

  final Color faceColor;
  final bool pointsUp;

  @override
  void paint(Canvas canvas, Size size) {
    final path = pointsUp
        ? (Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height)
          ..close())
        : (Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0)
          ..close());
    final paint = Paint()
      ..color = faceColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleTailPainter oldDelegate) =>
      oldDelegate.faceColor != faceColor || oldDelegate.pointsUp != pointsUp;
}
