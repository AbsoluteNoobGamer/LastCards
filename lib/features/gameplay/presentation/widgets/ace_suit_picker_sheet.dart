import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../domain/entities/card.dart';

/// Visual container style for [AceSuitPickerSheet].
enum AceSuitPickerPresentation {
  /// Inset rounded card with margins (standard table bottom sheet).
  floating,

  /// Full-width panel with top radius (e.g. Bust mode).
  bottomSheet,
}

/// Radial suit chooser after an Ace play: themed surface, four suits on a ring,
/// gold/accent pulse on the selected suit before popping.
class AceSuitPickerSheet extends ConsumerStatefulWidget {
  const AceSuitPickerSheet({
    super.key,
    this.presentation = AceSuitPickerPresentation.floating,
    this.title = 'Ace Played!',
    this.subtitle = 'Choose the new active suit',
  });

  final AceSuitPickerPresentation presentation;
  final String title;
  final String subtitle;

  @override
  ConsumerState<AceSuitPickerSheet> createState() =>
      _AceSuitPickerSheetState();
}

class _AceSuitPickerSheetState extends ConsumerState<AceSuitPickerSheet>
    with TickerProviderStateMixin {
  static const _suits = [
    (Suit.spades, '♠', 'Spades', false),
    (Suit.clubs, '♣', 'Clubs', false),
    (Suit.hearts, '♥', 'Hearts', true),
    (Suit.diamonds, '♦', 'Diamonds', true),
  ];

  late final AnimationController _entrance;
  late final Animation<double> _entranceFade;
  Suit? _pulsingSuit;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _entranceFade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1.0;
      } else {
        _entrance.forward();
      }
    });
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _onSuitChosen(Suit suit) async {
    if (!mounted) return;
    setState(() => _pulsingSuit = suit);
    final reduce = MediaQuery.disableAnimationsOf(context);
    await Future<void>.delayed(
      reduce ? Duration.zero : const Duration(milliseconds: 460),
    );
    if (mounted) Navigator.of(context).pop(suit);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final media = MediaQuery.of(context);
    final isMobile = math.min(media.size.width, media.size.height) <
        AppDimensions.breakpointMobile;
    final bottomInset = widget.presentation == AceSuitPickerPresentation.bottomSheet
        ? media.padding.bottom
        : 0.0;

    final child = FadeTransition(
      opacity: _entranceFade,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: _panel(theme, isMobile, context),
      ),
    );

    if (widget.presentation == AceSuitPickerPresentation.bottomSheet) {
      return child;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: child,
    );
  }

  Widget _panel(AppThemeData theme, bool isMobile, BuildContext context) {
    final radius = widget.presentation == AceSuitPickerPresentation.bottomSheet
        ? const BorderRadius.vertical(
            top: Radius.circular(AppDimensions.radiusModal),
          )
        : BorderRadius.circular(20);

    final padding = EdgeInsets.fromLTRB(
      isMobile ? 16 : 24,
      widget.presentation == AceSuitPickerPresentation.floating
          ? (isMobile ? 16 : 24)
          : AppDimensions.md,
      isMobile ? 16 : 24,
      widget.presentation == AceSuitPickerPresentation.floating
          ? (isMobile ? 16 : 24)
          : AppDimensions.md,
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: radius,
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.presentation == AceSuitPickerPresentation.floating) ...[
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.accentDark.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'A',
                style: TextStyle(
                  fontSize: isMobile ? 24 : 28,
                  fontWeight: FontWeight.w900,
                  color: theme.accentPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: isMobile ? 14 : 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty)
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: isMobile ? 11 : 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: isMobile ? 220 : 260,
            height: isMobile ? 220 : 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  _RadialSuitButton(
                    angle: -math.pi / 2 + i * math.pi / 2,
                    radius: isMobile ? 78 : 92,
                    suit: _suits[i].$1,
                    symbol: _suits[i].$2,
                    label: _suits[i].$3,
                    isRed: _suits[i].$4,
                    theme: theme,
                    isMobile: isMobile,
                    isPulsing: _pulsingSuit == _suits[i].$1,
                    onTap: _pulsingSuit != null
                        ? null
                        : () => _onSuitChosen(_suits[i].$1),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _RadialSuitButton extends StatefulWidget {
  const _RadialSuitButton({
    required this.angle,
    required this.radius,
    required this.suit,
    required this.symbol,
    required this.label,
    required this.isRed,
    required this.theme,
    required this.isMobile,
    required this.isPulsing,
    required this.onTap,
  });

  final double angle;
  final double radius;
  final Suit suit;
  final String symbol;
  final String label;
  final bool isRed;
  final AppThemeData theme;
  final bool isMobile;
  final bool isPulsing;
  final VoidCallback? onTap;

  @override
  State<_RadialSuitButton> createState() => _RadialSuitButtonState();
}

class _RadialSuitButtonState extends State<_RadialSuitButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 60,
      ),
    ]).animate(_pulse);
  }

  @override
  void didUpdateWidget(_RadialSuitButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing && !oldWidget.isPulsing) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _pulse.value = 1.0;
      } else {
        _pulse.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.isMobile ? 72.0 : 82.0;
    final h = widget.isMobile ? 86.0 : 98.0;
    final dx = math.cos(widget.angle) * widget.radius;
    final dy = math.sin(widget.angle) * widget.radius;

    final suitColor =
        widget.isRed ? widget.theme.suitRed : widget.theme.suitBlack;
    final borderIdle = widget.isRed
        ? widget.theme.suitRed.withValues(alpha: 0.55)
        : widget.theme.accentDark.withValues(alpha: 0.5);

    return Transform.translate(
      offset: Offset(dx, dy),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) {
          return Transform.scale(
            scale: widget.isPulsing ? _scale.value : 1.0,
            child: child,
          );
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: widget.theme.cardFace,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isPulsing
                      ? widget.theme.accentPrimary
                      : borderIdle,
                  width: widget.isPulsing ? 2.2 : 1.5,
                ),
                boxShadow: widget.isPulsing
                    ? [
                        BoxShadow(
                          color: widget.theme.accentPrimary
                              .withValues(alpha: 0.45),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ]
                    : const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          spreadRadius: 0,
                        ),
                      ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.symbol,
                    style: TextStyle(
                      fontSize: w * 0.42,
                      color: suitColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: w * 0.13,
                      fontWeight: FontWeight.w700,
                      color: suitColor.withValues(alpha: 0.88),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
