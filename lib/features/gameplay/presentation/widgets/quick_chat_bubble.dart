import 'dart:async';

import 'package:flutter/material.dart';

/// A chat bubble for quick chat messages.
/// Shows only the message (player name is already visible below the avatar).
/// Green background for local player, dark grey for opponents.
/// Animates in (scale 0.8 → 1.0) and out (opacity 1.0 → 0.0) before removal.
class QuickChatBubble extends StatefulWidget {
  const QuickChatBubble({
    required this.playerName,
    required this.message,
    required this.isLocal,
    required this.onDismiss,
    super.key,
  });

  final String playerName;
  final String message;
  final bool isLocal;
  final VoidCallback onDismiss;

  static const _localColor = Color(0xFF2E7D32);
  static const _opponentColor = Color(0xFF424242);

  @override
  State<QuickChatBubble> createState() => _QuickChatBubbleState();
}

class _QuickChatBubbleState extends State<QuickChatBubble>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
    _scaleController.forward();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isLocal
        ? QuickChatBubble._localColor
        : QuickChatBubble._opponentColor;

    return AnimatedBuilder(
      animation: Listenable.merge([_scaleController, _fadeController]),
      builder: (context, child) {
        final opacity = 1.0 - _fadeController.value;
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          widget.message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
