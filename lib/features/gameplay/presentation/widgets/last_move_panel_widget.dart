import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Data class representing the most recent move made by any player.
class LastMoveInfo {
  const LastMoveInfo({required this.playerName, this.cardLabel});

  /// The display name of the player who made the move.
  final String playerName;

  /// If a card was played, e.g. "7♠". Null means the player drew a card.
  final String? cardLabel;

  /// Human-readable description shown in the panel.
  String get description {
    if (cardLabel != null) {
      return '$playerName played $cardLabel';
    }
    return '$playerName drew a card';
  }

  @override
  bool operator ==(Object other) =>
      other is LastMoveInfo &&
      other.playerName == playerName &&
      other.cardLabel == cardLabel;

  @override
  int get hashCode => Object.hash(playerName, cardLabel);
}

/// Displays the single most recent move in the game.
///
/// When [lastMove] changes the old label fades out (300 ms) and the new one
/// fades in while sliding up from slightly below (400 ms).  The animation only
/// fires on updates — there is no entrance animation when the widget first
/// appears.
class LastMovePanelWidget extends StatefulWidget {
  const LastMovePanelWidget({super.key, required this.lastMove});

  final LastMoveInfo? lastMove;

  @override
  State<LastMovePanelWidget> createState() => _LastMovePanelWidgetState();
}

class _LastMovePanelWidgetState extends State<LastMovePanelWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  LastMoveInfo? _displayed; // currently displayed content
  bool _firstBuild = true;  // suppresses entrance animation

  @override
  void initState() {
    super.initState();

    // 300 ms fade-out + 400 ms fade-in → total rail is 700 ms.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Fade: 0→1 over the second half (fade-in phase, ms 300–700).
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(3 / 7, 1.0, curve: Curves.easeOut),
      ),
    );

    // Slide: from slightly below (0.2 of label height) to settled.
    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(3 / 7, 1.0, curve: Curves.easeOut),
      ),
    );

    _displayed = widget.lastMove;
  }

  @override
  void didUpdateWidget(LastMovePanelWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.lastMove == oldWidget.lastMove) return;

    if (_firstBuild || _displayed == null) {
      // No animation for the very first move shown.
      setState(() {
        _displayed = widget.lastMove;
        _firstBuild = false;
      });
      return;
    }

    _firstBuild = false;

    // Reset then run forward: the first 3/7 of the timeline is the "fade out"
    // phase where the OLD text already became invisible (we just hold the new
    // text hidden), then from 3/7 onward the new text fades in + slides up.
    _controller.reset();

    // Swap content at the midpoint (start of fade-in phase).
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _displayed = widget.lastMove);
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_displayed == null) return const SizedBox(height: 36);

    final isAnimating = _controller.isAnimating;

    Widget label = _MoveLabel(text: _displayed!.description);

    if (isAnimating) {
      label = FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(position: _slideAnim, child: label),
      );
    }

    return SizedBox(height: 36, child: Center(child: label));
  }
}

class _MoveLabel extends StatelessWidget {
  const _MoveLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.feltMid.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.goldDark.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.goldLight,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
