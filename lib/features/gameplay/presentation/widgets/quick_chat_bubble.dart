import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';

/// Floating emoji bubble for preset reactions (Clash Royale–style).
///
/// Shows a single emoji; player name stays near the avatar.
/// Animates in (scale 0.82 → 1.0) and out before removal.
///
/// [tailPointsUp] only affects outer padding when the bubble sits below vs
/// above the speaker row.
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
  /// Single emoji string (matches [kQuickMessages] entry).
  final String message;
  final bool isLocal;
  final VoidCallback onDismiss;

  /// When `true`, a bit more top padding — bubble visually below speaker.
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

  static const _wobbleEmoji = {'😂', '🔥', '💪', '😤', '🤞'};

  static bool _shouldWobble(String m) {
    final t = m.trim();
    return _wobbleEmoji.any((e) => e == t);
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
      if (_shouldWobble(widget.message) &&
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
        ? theme.accentPrimary.withValues(alpha: 0.92)
        : theme.surfacePanel.withValues(alpha: 0.96);
    final top = Color.lerp(base, Colors.white, widget.isLocal ? 0.14 : 0.1)!;
    final bottom = Color.lerp(base, Colors.black, 0.24)!;

    final bubbleBody = Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        widget.message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 30, height: 1.0),
      ),
    );

    final wobble = AnimatedBuilder(
      animation: _wobbleController,
      builder: (context, child) {
        final t = _wobbleController.value;
        final dx = math.sin(t * math.pi * 7) * 3.4 * (1.0 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: bubbleBody,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_scaleController, _fadeController]),
      builder: (context, child) {
        final outOpacity = 1.0 - _fadeController.value;
        final inOpacity = _scaleController.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: outOpacity * (0.25 + 0.75 * inOpacity),
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
