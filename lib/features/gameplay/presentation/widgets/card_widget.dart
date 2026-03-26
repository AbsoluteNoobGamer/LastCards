import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/card.dart';
import '../../../../services/audio_service.dart' as game_audio;
import '../../../../services/game_sound.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/shadow_blur.dart';
import '../../../../core/services/card_back_service.dart';
import 'card_back_widget.dart';
import 'joker_card_widget.dart';

/// Renders a single playing card (face-up or face-down).
///
/// Pass [isSelected] to show the lifted + gold-shimmer selection state.
/// Pass [onTap] to make the card interactive.
/// Pass [onTap] to make the card interactive.
class CardWidget extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (!faceUp) return CardBackWidget(width: width);
    if (card.isJoker) {
      return JokerCardWidget(
        width: width,
        isRedJoker: card.suit.isRed,
        onTap: onTap,
      );
    }

    final height = AppDimensions.cardHeight(width);
    final suitColor = card.suit.isRed ? AppColors.suitRed : AppColors.suitBlack;

    // Use implicit Tweens to drive lift and shimmer over a fast 150ms bounce
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: isSelected ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      builder: (context, val, innerChild) {
        // easeOutCubic keeps values in [0,1]; clamp aligns with selection visuals
        // and keeps shadow math safe if this curve ever changes.
        final v = val.clamp(0.0, 1.0);
        final liftY = -12.0 * v; // Lifts higher now!
        final scale = 1.0 + (0.10 * v); // Scale 1.0 -> 1.1

        return MouseRegion(
          cursor: onTap != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: GestureDetector(
            onTap: () {
              if (onTap != null) {
                HapticFeedback.selectionClick();
                game_audio.AudioService.instance.playSound(GameSound.cardSelect);
                onTap!();
              }
            },
            onPanStart: onTap != null
                ? (_) {
                    game_audio.AudioService.instance.playSound(GameSound.cardDraw);
                  }
                : null,
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
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusCard),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                            alpha: (0.35 + (0.15 * v)).clamp(0.0, 1.0)),
                        blurRadius:
                            nonNegativeShadowBlur(8 + (8 * v)), // expands on lift
                        offset: Offset(0, 4 + (4 * v)),
                      ),
                      if (v > 0)
                        BoxShadow(
                          color: AppColors.goldPrimary
                              .withValues(alpha: v * 0.85),
                          blurRadius: nonNegativeShadowBlur(16 * v),
                          spreadRadius: 3 * v,
                        ),
                    ],
                    border: Border.all(
                      color: isSelected
                          ? AppColors.goldLight.withValues(alpha: v)
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
      child: ValueListenableBuilder<String>(
        valueListenable: CardBackService.instance.selectedCardFaceSetId,
        builder: (context, faceSetId, _) {
          final assetPath = CardBackService.cardFaceAssetPathFor(
              faceSetId, card.rank, card.suit);
          if (assetPath != null) {
            return RepaintBoundary(
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppDimensions.radiusCard),
                child: Image.asset(
                  assetPath,
                  width: width,
                  height: height,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _CardFaceContent(
                    card: card,
                    suitColor: suitColor,
                    width: width,
                    height: height,
                  ),
                ),
              ),
            );
          }
          return RepaintBoundary(
            child: _CardFaceContent(
              card: card,
              suitColor: suitColor,
              width: width,
              height: height,
            ),
          );
        },
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
