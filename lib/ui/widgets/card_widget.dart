import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/card_model.dart';
import '../../core/services/audio_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimensions.dart';
import '../../core/theme/app_typography.dart';
import 'card_back_widget.dart';
import 'joker_card_widget.dart';

/// Renders a single playing card (face-up or face-down).
///
/// Pass [isSelected] to show the lifted + gold-shimmer selection state.
/// Pass [onTap] to make the card interactive.
/// Pass [onTap] to make the card interactive.
class CardWidget extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    if (!faceUp) return CardBackWidget(width: width);
    if (card.isJoker) {
      return JokerCardWidget(width: width, onTap: onTap);
    }

    final height = AppDimensions.cardHeight(width);
    final suitColor = card.suit.isRed
        ? AppColors.suitRed
        : AppColors.suitBlack;

    // Use implicit Tweens to drive lift and shimmer over a fast 150ms bounce
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: isSelected ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      builder: (context, val, innerChild) {
        final liftY = -12.0 * val; // Lifts higher now!
        final scale = 1.0 + (0.10 * val); // Scale 1.0 -> 1.1

        return MouseRegion(
          cursor: onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: () {
              if (onTap != null) {
                ref.read(audioServiceProvider).playClick();
                onTap!();
              }
            },
            onPanStart: onTap != null ? (_) {
              ref.read(audioServiceProvider).playDrag();
            } : null,
            child: Transform.translate(
              // Provide Z-index layering or simple Matrix
              offset: Offset(0, liftY),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.cardFace,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35 + (0.15 * val)),
                        blurRadius: 8 + (8 * val), // Shadow expands on lift
                        offset: Offset(0, 4 + (4 * val)),
                      ),
                      if (val > 0)
                        BoxShadow(
                          color: AppColors.goldPrimary.withValues(alpha: val * 0.85),
                          blurRadius: 16 * val,
                          spreadRadius: 3 * val,
                        ),
                    ],
                    border: Border.all(
                      color: isSelected
                          ? AppColors.goldLight.withValues(alpha: val)
                          : Colors.black.withValues(alpha: 0.08),
                      width: isSelected ? 2.0 : 0.5,
                    ),
                  ),
                  child: innerChild,
                ),
              ),
            ),
          ),
        );
      },
      child: RepaintBoundary(
        child: _CardFaceContent(
          card: card,
          suitColor: suitColor,
          width: width,
          height: height,
        ),
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
