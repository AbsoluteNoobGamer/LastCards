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
/// Cards can be reordered via long-press drag. While a drag is in progress
/// the other cards shift to reveal an insertion gap.
class PlayerHandWidget extends StatefulWidget {
  const PlayerHandWidget({
    super.key,
    required this.cards,
    this.selectedCardId,
    this.onCardTap,
    this.onReorder,
    this.cardWidth = AppDimensions.cardWidthMedium,
    this.enabled = true,
  });

  final List<CardModel> cards;
  final String? selectedCardId;
  final ValueChanged<String>? onCardTap;

  /// Called when the user drops a card at a new position.
  /// [oldIndex] and [newIndex] are indices into the current [cards] list.
  final void Function(int oldIndex, int newIndex)? onReorder;

  final double cardWidth;
  final bool enabled;

  @override
  State<PlayerHandWidget> createState() => _PlayerHandWidgetState();
}

class _PlayerHandWidgetState extends State<PlayerHandWidget> {
  /// Index of the card currently being dragged (into [widget.cards]).
  int? _draggingIndex;

  /// Where the dragged card would be inserted if dropped now.
  int? _insertIndex;

  /// Fixed horizontal offset between consecutive cards (fans from the left).
  static const double _fixedSpreadDp = 45.0;

  // ── insert-index calculation ─────────────────────────────────────────────

  /// Given a drag position [dragX] within the hand area, return the index at
  /// which the dragged card should be inserted.
  int _calcInsertIndex(double dragX, double spread, int n) {
    if (n <= 1) return 0;
    for (int i = 0; i < n - 1; i++) {
      // Midpoint between card i and card i+1
      if (dragX < i * spread + spread / 2) return i;
    }
    return n - 1;
  }

  // ── adjusted left position ────────────────────────────────────────────────

  /// Returns the [left] offset for card at [visibleIndex] in the fanned stack,
  /// taking into account a potential insertion gap when dragging.
  ///
  /// When [_draggingIndex] and [_insertIndex] are non-null we open one extra
  /// [spread] unit of space at the target insertion slot so it looks like the
  /// other cards are making room.
  double _leftFor({
    required int visibleIndex,
    required double spread,
    required double totalWidth,
    required double targetWidth,
    required int n,
  }) {
    if (n <= 1) return (totalWidth - targetWidth) / 2;

    final di = _draggingIndex;
    final ii = _insertIndex;

    if (di == null || ii == null || di == ii) {
      return visibleIndex.toDouble() * spread;
    }

    // Shift cards to open a gap at the insertion point
    double base = visibleIndex.toDouble() * spread;
    // Cards that come after the insertion point (but are not the dragged card)
    // shift one extra spread to the right.
    if (visibleIndex != di && visibleIndex >= ii) {
      base += spread;
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // ── Available width ────────────────────────────────────────────
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        final isCompact = maxWidth < AppDimensions.breakpointMobile;

        final targetWidth =
            (maxWidth * (isCompact ? 0.14 : 0.11)).clamp(44.0, widget.cardWidth);
        final cardH = AppDimensions.cardHeight(targetWidth) + 14;

        final n = cards.length;

        // ── Spread calculation ─────────────────────────────────────────
        // Fixed offset per card so the hand fans from the left edge.
        // Scroll activates only when the natural hand width exceeds the
        // available container width (Option B).
        final double spread;
        final bool useScroll;

        if (n <= 1) {
          spread = 0;
          useScroll = false;
        } else {
          spread = _fixedSpreadDp;
          final naturalWidth = targetWidth + (n - 1) * spread;
          useScroll = naturalWidth > maxWidth;
        }

        final totalWidth =
            n <= 1 ? targetWidth : targetWidth + (n - 1) * spread;

        // Extra width needed when a gap is shown during drag
        final dragExtraWidth =
            (_draggingIndex != null && _insertIndex != null) ? spread : 0.0;
        final stackWidth = totalWidth + dragExtraWidth;

        // ── Card stack with drag-and-drop ──────────────────────────────
        final cardStack = DragTarget<int>(
          onMove: (details) {
            final localX = details.offset.dx;
            final newInsert = _calcInsertIndex(localX, spread, n);
            if (newInsert != _insertIndex) {
              setState(() => _insertIndex = newInsert);
            }
          },
          onAcceptWithDetails: (details) {
            final di = _draggingIndex;
            final ii = _insertIndex;
            if (di != null && ii != null && di != ii) {
              widget.onReorder?.call(di, ii);
            }
            setState(() {
              _draggingIndex = null;
              _insertIndex = null;
            });
          },
          onLeave: (_) {
            setState(() => _insertIndex = null);
          },
          builder: (context, candidateData, rejectedData) {
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                for (int i = 0; i < n; i++)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    left: _leftFor(
                      visibleIndex: i,
                      spread: spread,
                      totalWidth: stackWidth,
                      targetWidth: targetWidth,
                      n: n,
                    ),
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
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey('entry-${cards[i].id}'),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value.clamp(0.0, 1.0),
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - value)),
                              child: Transform.scale(
                                scale: 0.8 + (0.2 * value),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: LongPressDraggable<int>(
                          data: i,
                          delay: const Duration(milliseconds: 300),
                          onDragStarted: () {
                            setState(() {
                              _draggingIndex = i;
                              _insertIndex = i;
                            });
                          },
                          onDraggableCanceled: (_, __) {
                            setState(() {
                              _draggingIndex = null;
                              _insertIndex = null;
                            });
                          },
                          onDragEnd: (_) {
                            setState(() {
                              _draggingIndex = null;
                              _insertIndex = null;
                            });
                          },
                          feedback: Material(
                            color: Colors.transparent,
                            elevation: 10,
                            child: CardWidget(
                              card: cards[i],
                              width: targetWidth,
                              faceUp: true,
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.25,
                            child: CardWidget(
                              card: cards[i],
                              width: targetWidth,
                              faceUp: true,
                            ),
                          ),
                          child: CardWidget(
                            card: cards[i],
                            width: targetWidth,
                            faceUp: true,
                            isSelected: widget.selectedCardId == cards[i].id,
                            onTap: widget.enabled
                                ? () => widget.onCardTap?.call(cards[i].id)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );

        // ── Outer SizedBox is always exactly maxWidth wide ─────────────
        if (!useScroll) {
          return SizedBox(
            width: maxWidth,
            height: cardH,
            child: SizedBox(
              width: stackWidth,
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
                width: stackWidth,
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
