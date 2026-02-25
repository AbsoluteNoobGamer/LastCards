import 'package:flutter/material.dart';

import '../../domain/entities/card.dart';
import '../../../../core/theme/app_dimensions.dart';
import 'card_widget.dart';

/// Displays the local player's hand as a fanned row that never overflows.
///
/// Layout strategy (Option A → Option B):
///
/// **Option A** – dynamic overlap scaling (preferred):
///   spread = (maxWidth − cardWidth) / (n − 1)
///   All n cards fit exactly in [maxWidth]. Minimum visible strip: 20 dp.
///
/// **Option B** – horizontal scroll with fade hints (fallback):
///   Activated automatically when the Option-A spread would be < 20 dp.
///   Cards are placed at a fixed 20 dp step inside a [SingleChildScrollView].
///   Left/right [ShaderMask] fades hint that the row is scrollable.
///
/// In both cases the widget always reports exactly [maxWidth] wide to its
/// parent. This prevents [PlayerZoneWidget]'s wrapping Container from
/// expanding beyond the viewport when constraints are loose.
class PlayerHandWidget extends StatelessWidget {
  const PlayerHandWidget({
    super.key,
    required this.cards,
    this.selectedCardIds = const {},
    this.onCardTap,
    this.cardWidth = AppDimensions.cardWidthMedium,
    this.enabled = true,
  });

  final List<CardModel> cards;
  final Set<String> selectedCardIds;
  final ValueChanged<String>? onCardTap;
  final double cardWidth;
  final bool enabled;

  /// Minimum visible horizontal strip per card before Option B takes over.
  static const double _minStripDp = 20.0;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // ── Available width ──────────────────────────────────────────────
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        final isCompact = maxWidth < AppDimensions.breakpointMobile;

        // Card width formula is unchanged from the original.
        final targetWidth =
            (maxWidth * (isCompact ? 0.14 : 0.11)).clamp(44.0, cardWidth);
        final cardH = AppDimensions.cardHeight(targetWidth) + 14;

        final n = cards.length;

        // ── Spread calculation ───────────────────────────────────────────
        //
        // We want: targetWidth + (n − 1) × spread == maxWidth
        //   ⟹ spread = (maxWidth − targetWidth) / (n − 1)
        //
        // This guarantees totalWidth == maxWidth for Option A
        // (verified: targetWidth + (n-1) × spread
        //          = targetWidth + (maxWidth − targetWidth) = maxWidth ✓).

        final double spread;
        final bool useScroll;

        if (n <= 1) {
          // Single card: centre it, no spread needed.
          spread = 0;
          useScroll = false;
        } else {
          final computedSpread = (maxWidth - targetWidth) / (n - 1);
          if (computedSpread >= _minStripDp) {
            // Option A: all cards fit with comfortable overlap.
            spread = computedSpread;
            useScroll = false;
          } else {
            // Option B: enforce minimum strip; activate scroll.
            spread = _minStripDp;
            useScroll = true;
          }
        }

        // For Option A: totalWidth == maxWidth (exact fit).
        // For Option B: totalWidth = targetWidth + (n-1) × 20 dp (scrollable).
        // For n == 1: totalWidth == targetWidth.
        final totalWidth =
            n <= 1 ? targetWidth : targetWidth + (n - 1) * spread;

        // ── Card stack ───────────────────────────────────────────────────
        final cardStack = Stack(
          alignment: Alignment.bottomCenter,
          children: [
            for (int i = 0; i < n; i++)
              Positioned(
                // Centre single card; otherwise fan from left edge.
                left: n == 1
                    ? (totalWidth - targetWidth) / 2
                    : i.toDouble() * spread,
                bottom: 0,
                child: Hero(
                  tag: 'card-${cards[i].id}',
                  flightShuttleBuilder: (flightContext, animation,
                      flightDirection, fromHeroContext, toHeroContext) {
                    final bounce = TweenSequence([
                      TweenSequenceItem(
                          tween: Tween(begin: 1.0, end: 1.1)
                              .chain(CurveTween(curve: Curves.easeOut)),
                          weight: 50),
                      TweenSequenceItem(
                          tween: Tween(begin: 1.1, end: 1.0)
                              .chain(CurveTween(curve: Curves.easeIn)),
                          weight: 50),
                    ]).animate(animation);

                    return ScaleTransition(
                      scale: bounce,
                      child: toHeroContext.widget,
                    );
                  },
                  child: CardWidget(
                    card: cards[i],
                    width: targetWidth,
                    faceUp: true,
                    isSelected: selectedCardIds.contains(cards[i].id),
                    onTap: enabled ? () => onCardTap?.call(cards[i].id) : null,
                  ),
                ),
              ),
          ],
        );

        // ── Outer SizedBox is always exactly maxWidth wide ───────────────
        //
        // This is the critical fix: by pinning the widget's reported width to
        // maxWidth, PlayerZoneWidget's inner Column never exceeds screen bounds
        // regardless of how large totalWidth grows (Option B content).

        if (!useScroll) {
          // Option A: stack fits inside maxWidth exactly — no scroll needed.
          return SizedBox(
            width: maxWidth,
            height: cardH,
            child: SizedBox(
              width: totalWidth,
              height: cardH,
              child: cardStack,
            ),
          );
        }

        // Option B: scrollable content with left/right fade-gradient hints.
        return SizedBox(
          width: maxWidth,
          height: cardH,
          child: ShaderMask(
            shaderCallback: (Rect bounds) => const LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.04, 0.96, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: SizedBox(
                width: totalWidth,
                height: cardH,
                child: cardStack,
              ),
            ),
          ),
        );
      },
    );
  }
}
