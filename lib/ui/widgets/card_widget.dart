import 'package:flutter/material.dart';

import '../../core/models/card_model.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'card_back_widget.dart';
import 'joker_card_widget.dart';

/// Renders a single playing card (face-up or face-down).
///
/// Pass [isSelected] to show the lifted + gold-shimmer selection state.
/// Pass [onTap] to make the card interactive.
class CardWidget extends StatefulWidget {
  const CardWidget({
    super.key,
    required this.card,
    this.width = AppDimensions.cardWidthMedium,
    this.faceUp = true,
    this.isSelected = false,
    this.onTap,
  });

  final CardModel card;
  final double width;
  final bool faceUp;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  State<CardWidget> createState() => _CardWidgetState();
}

class _CardWidgetState extends State<CardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selectController;
  late final Animation<double> _liftAnim;
  late final Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _selectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _liftAnim = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _selectController, curve: Curves.easeOut),
    );
    _shimmerAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _selectController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(CardWidget old) {
    super.didUpdateWidget(old);
    if (widget.isSelected != old.isSelected) {
      if (widget.isSelected) {
        _selectController.forward();
      } else {
        _selectController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _selectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.faceUp) return CardBackWidget(width: widget.width);
    if (widget.card.isJoker) {
      return JokerCardWidget(width: widget.width, onTap: widget.onTap);
    }

    final height = AppDimensions.cardHeight(widget.width);
    final suitColor = widget.card.suit.isRed
        ? AppColors.suitRed
        : AppColors.suitBlack;

    return AnimatedBuilder(
      animation: _selectController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _liftAnim.value),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: widget.width,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.cardFace,
                borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                  if (widget.isSelected)
                    BoxShadow(
                      color: AppColors.goldPrimary
                          .withValues(alpha: _shimmerAnim.value * 0.85),
                      blurRadius: 14,
                      spreadRadius: 2,
                    ),
                ],
                border: widget.isSelected
                    ? Border.all(
                        color: AppColors.goldLight
                            .withValues(alpha: _shimmerAnim.value),
                        width: 1.5,
                      )
                    : Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                        width: 0.5,
                      ),
              ),
              child: child,
            ),
          ),
        );
      },
      child: _CardFaceContent(
        card: widget.card,
        suitColor: suitColor,
        width: widget.width,
        height: height,
      ),
    );
  }
}

// ── Card face content ─────────────────────────────────────────────────────────

class _CardFaceContent extends StatelessWidget {
  const _CardFaceContent({
    required this.card,
    required this.suitColor,
    required this.width,
    required this.height,
  });

  final CardModel card;
  final Color suitColor;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final rankLabel = card.rank.displayLabel;
    final suitSymbol = card.suit.symbol;
    final cornerFontSize = width * 0.22;
    final centerFontSize = width * 0.38;

    return Stack(
      children: [
        // Top-left corner
        Positioned(
          top: 4,
          left: 5,
          child: _CornerPip(
            rank: rankLabel,
            suit: suitSymbol,
            color: suitColor,
            fontSize: cornerFontSize,
            flipped: false,
          ),
        ),

        // Centered suit
        Center(
          child: Text(
            suitSymbol,
            style: AppTypography.cardRank(
              color: suitColor,
              fontSize: centerFontSize,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        // Bottom-right corner (rotated 180°)
        Positioned(
          bottom: 4,
          right: 5,
          child: Transform.rotate(
            angle: 3.14159,
            child: _CornerPip(
              rank: rankLabel,
              suit: suitSymbol,
              color: suitColor,
              fontSize: cornerFontSize,
              flipped: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _CornerPip extends StatelessWidget {
  const _CornerPip({
    required this.rank,
    required this.suit,
    required this.color,
    required this.fontSize,
    required this.flipped,
  });

  final String rank;
  final String suit;
  final Color color;
  final double fontSize;
  final bool flipped;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          rank,
          style: AppTypography.cardRank(color: color, fontSize: fontSize),
        ),
        Text(
          suit,
          style: AppTypography.cardRank(
            color: color,
            fontSize: fontSize * 0.75,
          ),
        ),
      ],
    );
  }
}
