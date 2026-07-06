import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/card.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/shadow_blur.dart';
import 'card_back_widget.dart';
import 'card_widget.dart';

/// The central discard pile widget.
///
/// Shows the [topCard] prominently with subtle stacked card layers behind it
/// that scale with [discardPileCount]. Animates in new cards via [AnimatedSwitcher].
///
/// When the top card is a Joker that has been declared ([CardModel.jokerDeclaredSuit]
/// and [CardModel.jokerDeclaredRank] are set), the card renders as the declared face
/// and shows a looping animated gold outline to signal it is a Joker in disguise.
class DiscardPileWidget extends ConsumerStatefulWidget {
  const DiscardPileWidget({
    super.key,
    this.topCard,
    this.secondCard,
    this.discardPileHistory,
    this.cardWidth = AppDimensions.cardWidthDiscardTop,
    this.discardPileCount = 0,
  });

  final CardModel? topCard;
  final CardModel? secondCard;

  /// Cards under the top (2nd, 3rd, ...) for visual stacking hints.
  /// When null, falls back to [secondCard] for layer 1.
  final List<CardModel>? discardPileHistory;
  final double cardWidth;

  /// Number of cards currently in the discard pile. Used to compute stack depth.
  final int discardPileCount;

  @override
  ConsumerState<DiscardPileWidget> createState() => _DiscardPileWidgetState();
}

/// Slight alternating rotation for stacked history layers — a loosely
/// scattered "played pile" look rather than a squared-off twin of the draw
/// pile. Layer 1 (closest to top) tilts one way, layer 2 the other, etc.
double _historyLayerRotation(int layerIndex) {
  const angles = [-0.09, 0.07, -0.05, 0.04];
  return angles[(layerIndex - 1) % angles.length];
}

/// Maps a card count to the number of visible stack layers behind the top card.
/// 0 cards → 0 layers, 1–10 → 1, 11–20 → 2, 21–30 → 3, 31–40 → 4, 40+ → 5.
int _stackLayers(int count) {
  if (count <= 0) return 0;
  if (count <= 10) return 1;
  if (count <= 20) return 2;
  if (count <= 30) return 3;
  if (count <= 40) return 4;
  return 5;
}

/// Warm red for hearts/diamonds, cool blue-white for spades/clubs; Jokers use gold.
Color _discardHoverGlow(CardModel? top) {
  if (top == null) return AppColors.goldPrimary;
  if (top.isJoker) return AppColors.goldPrimary;
  return top.suit.isRed
      ? const Color(0xFFE53935)
      : const Color(0xFF90CAF9);
}

class _DiscardPileWidgetState extends ConsumerState<DiscardPileWidget> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final height = AppDimensions.cardHeight(widget.cardWidth);
    // No hover lift — keeps the face-up pile visually stable (layout + UX).
    final targetOffset = Offset.zero;

    // How many subtle card-back layers to show behind the top card
    final layers = _stackLayers(widget.discardPileCount);
    const layerOffset = 2.5; // px per layer

    // Determine if the top card is a Joker with a declared face
    final topCard = widget.topCard;
    final isJokerDisguised = topCard != null &&
        topCard.isJoker &&
        topCard.jokerDeclaredSuit != null &&
        topCard.jokerDeclaredRank != null;

    // When disguised, create a synthetic card that displays the declared face.
    // We keep the original id so AnimatedSwitcher key/Hero tag remain stable.
    final displayCard = isJokerDisguised
        ? topCard.copyWith(
            rank: topCard.jokerDeclaredRank!,
            suit: topCard.jokerDeclaredSuit!,
            // Clear declaration fields so CardWidget renders it as a normal card,
            // not as a Joker again.
            jokerDeclaredRank: null,
            jokerDeclaredSuit: null,
          )
        : topCard;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: SizedBox(
        width: widget.cardWidth + 16,
        height: height + 16,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft accent-coloured glow pool — makes this pile read as the
            // "stage" where cards land, rather than a mirrored twin of the
            // draw pile's tidy stack.
            if (topCard != null)
              Positioned(
                bottom: 2,
                child: IgnorePointer(
                  child: Container(
                    width: widget.cardWidth * 1.15,
                    height: 14,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: RadialGradient(
                        colors: [
                          theme.accentPrimary.withValues(alpha: 0.35),
                          theme.accentPrimary.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Zone label (visible when pile is empty)
            if (topCard == null)
              _EmptyPileLabel(
                width: widget.cardWidth,
                height: height,
                theme: theme,
              ),

            // Dynamic stacked layers (furthest first) — loosely rotated card
            // faces/backs peeking out, like a scattered played pile.
            if (topCard != null)
              for (int i = layers; i >= 1; i--)
                Positioned(
                  top: 8 + i * layerOffset,
                  left: 8 + i * layerOffset,
                  child: Opacity(
                    opacity: (1 - i * 0.15).clamp(0.2, 0.8),
                    child: Transform.rotate(
                      angle: _historyLayerRotation(i),
                      child: _buildLayerCard(i),
                    ),
                  ),
                ),

            // Top card — hover lift + animated switcher for smooth transitions
            if (topCard != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                transform: Matrix4.translationValues(
                    targetOffset.dx, targetOffset.dy, 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: Hero(
                    key: ValueKey(topCard.id),
                    tag: 'card-${topCard.id}',
                    child: _ClippedCardWithRing(
                      cardWidth: widget.cardWidth,
                      isHovering: _isHovering,
                      isJokerDisguised: isJokerDisguised,
                      hoverGlow: _discardHoverGlow(topCard),
                      ringColor: theme.accentDark,
                      child: CardWidget(
                        card: displayCard!,
                        width: widget.cardWidth,
                        faceUp: true,
                        // Active special card on the table gets the gold shimmer.
                        shimmer: displayCard.isSpecial,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Builds a single stacked layer — card face when history available, else back.
  Widget _buildLayerCard(int layerIndex) {
    final effectiveHistory = widget.discardPileHistory ??
        (widget.secondCard != null ? [widget.secondCard!] : <CardModel>[]);
    final card = effectiveHistory.length >= layerIndex
        ? effectiveHistory[layerIndex - 1]
        : null;
    if (card != null) {
      return CardWidget(
        card: card,
        width: widget.cardWidth,
        faceUp: true,
      );
    }
    return CardBackWidget(width: widget.cardWidth);
  }
}

/// Wraps a card with a drop-shadow + gold ring border that is fully clipped to
/// the card's rounded corners — eliminating any rectangular box artefact.
///
/// When [isJokerDisguised] is true, an [AnimationController] drives a looping
/// pulsing gold glow so all players can see this is a Joker in disguise.
class _ClippedCardWithRing extends StatefulWidget {
  const _ClippedCardWithRing({
    required this.cardWidth,
    required this.isHovering,
    required this.isJokerDisguised,
    required this.hoverGlow,
    required this.ringColor,
    required this.child,
  });

  final double cardWidth;
  final bool isHovering;
  final bool isJokerDisguised;
  final Color hoverGlow;

  /// Default (non-hover, non-Joker) ring color — the active theme's accent,
  /// so the pile stops reading as permanently gold on every theme.
  final Color ringColor;
  final Widget child;

  @override
  State<_ClippedCardWithRing> createState() => _ClippedCardWithRingState();
}

class _ClippedCardWithRingState extends State<_ClippedCardWithRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    if (widget.isJokerDisguised) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_ClippedCardWithRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isJokerDisguised && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isJokerDisguised && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(
      AppDimensions.radiusCard * (widget.cardWidth / AppDimensions.cardWidthMedium),
    );

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        final pulse = _pulseAnimation.value; // 0.0 → 1.0 → 0.0 (looping)

        // Joker-disguised glow: gold border pulses between dim and bright,
        // and the shadow glow breathes softly in and out.
        final jokerBorderAlpha = widget.isJokerDisguised
            ? (0.55 + 0.45 * pulse) // 0.55 – 1.0
            : 0.0;
        final jokerGlowRadius = widget.isJokerDisguised
            ? (12.0 + 20.0 * pulse) // 12 – 32 px glow
            : 0.0;
        final jokerGlowAlpha = widget.isJokerDisguised
            ? (0.35 + 0.45 * pulse) // 0.35 – 0.80
            : 0.0;

        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
              if (widget.isHovering && !widget.isJokerDisguised)
                BoxShadow(
                  color: widget.hoverGlow.withValues(alpha: 0.5),
                  blurRadius: 25,
                  spreadRadius: 2,
                ),
              // Animated Joker glow — replaces hover glow when disguised
              if (widget.isJokerDisguised)
                BoxShadow(
                  color: AppColors.goldPrimary.withValues(alpha: jokerGlowAlpha),
                  blurRadius: nonNegativeShadowBlur(jokerGlowRadius),
                  spreadRadius: 3,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                child!,
                // Ring drawn INSIDE the clipped area — stays rounded, no rectangle
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(
                          color: widget.isJokerDisguised
                              ? AppColors.goldPrimary.withValues(alpha: jokerBorderAlpha)
                              : (widget.isHovering
                                  ? widget.hoverGlow
                                  : widget.ringColor),
                          width: widget.isJokerDisguised ? 3.5 : 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _EmptyPileLabel extends StatelessWidget {
  const _EmptyPileLabel({
    required this.width,
    required this.height,
    required this.theme,
  });

  final double width;
  final double height;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.5),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(
            AppDimensions.radiusCard * (width / AppDimensions.cardWidthMedium)),
        color: theme.surfacePanel.withValues(alpha: 0.4),
      ),
      child: Center(
        child: Text(
          'DISCARD',
          style: AppTypography.labelSmall.copyWith(
            letterSpacing: 2,
            color: theme.accentDark,
          ),
        ),
      ),
    );
  }
}
