import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/theme_provider.dart';

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

/// Displays the single most recent move in the game with a fade+slide animation.
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

  LastMoveInfo? _displayed;
  bool _firstBuild = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(3 / 7, 1.0, curve: Curves.easeOut),
      ),
    );
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
      setState(() {
        _displayed = widget.lastMove;
        _firstBuild = false;
      });
      return;
    }
    _firstBuild = false;
    _controller.reset();
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

class _MoveLabel extends ConsumerWidget {
  const _MoveLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.surfacePanel.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: theme.accentLight,
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
