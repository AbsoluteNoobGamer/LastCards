import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../shared/reactions/reaction_catalog.dart';

/// Floating reaction bubble — Unicode emoji or animated GIF preset.
///
/// Wire index selects [kReactionDefinitions] (broadcast from server/offline pipeline).
class QuickChatBubble extends ConsumerStatefulWidget {
  const QuickChatBubble({
    required this.playerName,
    required this.reactionWireIndex,
    required this.isLocal,
    required this.onDismiss,
    this.tailPointsUp = false,
    super.key,
  });

  final String playerName;

  /// Index into shared [kReactionDefinitions] (`messageIndex` on wire).
  final int reactionWireIndex;
  final bool isLocal;
  final VoidCallback onDismiss;

  /// Outer padding tweak when bubble sits below vs above the speaker row.
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

  static const _wobbleUnicode = {'😂', '🔥', '💪', '😤', '🤞'};

  static bool _shouldWobble(ReactionDefinition def) {
    if (def.kind != ReactionVisualKind.unicode || def.unicodeLabel == null) {
      return false;
    }
    final t = def.unicodeLabel!.trim();
    return _wobbleUnicode.any((e) => e == t);
  }

  ReactionDefinition get _def {
    if (!isValidReactionWireIndex(widget.reactionWireIndex)) {
      return kReactionDefinitions[0];
    }
    return kReactionDefinitions[widget.reactionWireIndex];
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
      if (_shouldWobble(_def) && !MediaQuery.disableAnimationsOf(context)) {
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

    Widget inner;
    if (_def.kind == ReactionVisualKind.gifAsset &&
        _def.gifAssetPath != null) {
      inner = ClipOval(
        child: Image.asset(
          _def.gifAssetPath!,
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } else if (_def.unicodeLabel != null) {
      inner = Text(
        _def.unicodeLabel!,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 30, height: 1.0),
      );
    } else {
      inner = const SizedBox.shrink();
    }

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
      child: inner,
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
