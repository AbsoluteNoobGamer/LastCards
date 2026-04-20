import 'dart:math' as math;

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
    this.invalidPlayShakeTrigger,
  });

  final List<CardModel> cards;
  final String? selectedCardId;
  final ValueChanged<String>? onCardTap;

  /// Called when the user drops a card at a new position.
  /// [oldIndex] and [newIndex] are indices into the current [cards] list.
  final void Function(int oldIndex, int newIndex)? onReorder;

  final double cardWidth;
  final bool enabled;

  /// Increment (e.g. `notifier.value++`) to play a short horizontal shake after an invalid play.
  final ValueNotifier<int>? invalidPlayShakeTrigger;

  @override
  State<PlayerHandWidget> createState() => _PlayerHandWidgetState();
}

class _PlayerHandWidgetState extends State<PlayerHandWidget>
    with SingleTickerProviderStateMixin {
  /// Index of the card currently being dragged (into [widget.cards]).
  int? _draggingIndex;

  /// Where the dragged card would be inserted if dropped now.
  int? _insertIndex;

  bool _hoverWiden = false;

  late final AnimationController _shakeCtrl;
  VoidCallback? _shakeListener;
  int _lastShakeStamp = -1;

  /// Fixed horizontal offset between successive cards in the fan.
  static const double _fixedSpread = 45.0;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _attachShakeListener();
  }

  void _attachShakeListener() {
    final n = widget.invalidPlayShakeTrigger;
    if (n == null) return;
    void listener() {
      final v = n.value;
      if (v != _lastShakeStamp) {
        _lastShakeStamp = v;
        // Defer: [ValueNotifier.notifyListeners] can run synchronously during a
        // parent [setState]/layout; starting a ticker here has triggered
        // framework assertions ('_elements.contains(element)').
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _shakeCtrl.forward(from: 0);
        });
      }
    }

    _shakeListener = listener;
    n.addListener(listener);
    _lastShakeStamp = n.value;
  }

  @override
  void didUpdateWidget(PlayerHandWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invalidPlayShakeTrigger != widget.invalidPlayShakeTrigger) {
      if (oldWidget.invalidPlayShakeTrigger != null &&
          _shakeListener != null) {
        oldWidget.invalidPlayShakeTrigger!.removeListener(_shakeListener!);
      }
      _shakeListener = null;
      _attachShakeListener();
    }
  }

  @override
  void dispose() {
    if (_shakeListener != null && widget.invalidPlayShakeTrigger != null) {
      widget.invalidPlayShakeTrigger!.removeListener(_shakeListener!);
    }
    _shakeCtrl.dispose();
    super.dispose();
  }

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

        // Use shorter screen dimension: in landscape, width is the long axis.
        final media = MediaQuery.sizeOf(context);
        final isCompact =
            math.min(media.width, media.height) < AppDimensions.breakpointMobile;

        final minW = math.min(44.0, widget.cardWidth);
        final maxW = widget.cardWidth;
        final targetWidth =
            (maxWidth * (isCompact ? 0.14 : 0.11)).clamp(minW, maxW);
        final n = cards.length;
        const arcFactor = 0.03;
        const liftAmount = 8.0;
        final arcPad = n >= 3 ? 14.0 : 0.0;
        final cardH = AppDimensions.cardHeight(targetWidth) + 14 + arcPad;

        // ── Spread calculation ─────────────────────────────────────────
        final double spread;
        final bool useScroll;

        final baseSpread = _fixedSpread + (_hoverWiden ? 6.0 : 0.0);
        if (n <= 1) {
          spread = 0;
          useScroll = false;
        } else {
          spread = baseSpread;
          final totalContentWidth = targetWidth + (n - 1) * baseSpread;
          useScroll = totalContentWidth > maxWidth;
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
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    left: _leftFor(
                      visibleIndex: i,
                      spread: spread,
                      totalWidth: stackWidth,
                      targetWidth: targetWidth,
                      n: n,
                    ),
                    bottom: n >= 3
                        ? math.cos((i - (n - 1) / 2) * arcFactor) * liftAmount
                        : 0.0,
                    child: Transform.rotate(
                      angle: n >= 3 ? (i - (n - 1) / 2) * arcFactor : 0.0,
                      alignment: Alignment.bottomCenter,
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
                  ),
              ],
            );
          },
        );

        final wrappedStack = MouseRegion(
          onEnter: (_) => setState(() => _hoverWiden = true),
          onExit: (_) => setState(() => _hoverWiden = false),
          child: AnimatedBuilder(
            animation: _shakeCtrl,
            builder: (context, child) {
              if (MediaQuery.disableAnimationsOf(context)) {
                return child!;
              }
              final t = Curves.easeOutCubic.transform(_shakeCtrl.value);
              final damp = 1.0 - t;
              final dx = math.sin(_shakeCtrl.value * math.pi * 6.5) * 11 * damp;
              return Transform.translate(
                offset: Offset(dx, 0),
                child: child,
              );
            },
            child: cardStack,
          ),
        );

        // ── Outer SizedBox is always exactly maxWidth wide ─────────────
        if (!useScroll) {
          return SizedBox(
            width: maxWidth,
            height: cardH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: stackWidth,
                height: cardH,
                child: wrappedStack,
              ),
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
                child: wrappedStack,
              ),
            ),
          ),
        );
      },
    );
  }
}
