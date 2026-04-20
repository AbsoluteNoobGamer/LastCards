import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/utils/shadow_blur.dart';
import '../../domain/entities/card.dart';

/// Visual container style for [AceSuitPickerSheet].
enum AceSuitPickerPresentation {
  /// Inset rounded card with margins (standard table bottom sheet).
  floating,

  /// Full-width panel with top radius (e.g. Bust mode).
  bottomSheet,
}

/// Suit chooser after an Ace play: themed surface, four suits in a horizontal
/// strip; accent pulse on the selected suit before popping.
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
  ConsumerState<AceSuitPickerSheet> createState() => _AceSuitPickerSheetState();
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
      duration: const Duration(milliseconds: 520),
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
    HapticFeedback.mediumImpact();
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
    final isMobile = (media.size.width < media.size.height
            ? media.size.width
            : media.size.height) <
        AppDimensions.breakpointMobile;
    final bottomInset =
        widget.presentation == AceSuitPickerPresentation.bottomSheet
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
        : BorderRadius.circular(22);

    final padding = EdgeInsets.fromLTRB(
      isMobile ? 16 : 24,
      widget.presentation == AceSuitPickerPresentation.floating
          ? (isMobile ? 18 : 22)
          : AppDimensions.md,
      isMobile ? 16 : 24,
      widget.presentation == AceSuitPickerPresentation.floating
          ? (isMobile ? 18 : 22)
          : AppDimensions.md,
    );

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.surfacePanel,
            Color.lerp(theme.surfacePanel, theme.backgroundMid, 0.22)!,
          ],
        ),
        borderRadius: radius,
        border: Border.all(
          color: theme.accentLight.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.12),
            blurRadius: nonNegativeShadowBlur(28),
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: nonNegativeShadowBlur(28),
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.presentation == AceSuitPickerPresentation.floating) ...[
            Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.accentDark.withValues(alpha: 0.2),
                    theme.accentPrimary.withValues(alpha: 0.65),
                    theme.accentDark.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: isMobile ? 48 : 54,
                height: isMobile ? 48 : 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.accentPrimary.withValues(alpha: 0.35),
                      theme.accentDark.withValues(alpha: 0.15),
                    ],
                  ),
                  border: Border.all(
                    color: theme.accentLight.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.accentPrimary.withValues(alpha: 0.25),
                      blurRadius: nonNegativeShadowBlur(12),
                    ),
                  ],
                ),
                child: Text(
                  'A',
                  style: TextStyle(
                    fontSize: isMobile ? 22 : 26,
                    fontWeight: FontWeight.w900,
                    color: theme.accentLight,
                    height: 1,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: isMobile ? 15 : 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: TextStyle(
                          color: theme.textSecondary.withValues(alpha: 0.95),
                          fontSize: isMobile ? 12 : 13,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) SizedBox(width: isMobile ? 8 : 10),
                Expanded(
                  child: _SuitStripButton(
                    slotIndex: i,
                    entrance: _entrance,
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
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SuitStripButton extends StatefulWidget {
  const _SuitStripButton({
    required this.slotIndex,
    required this.entrance,
    required this.suit,
    required this.symbol,
    required this.label,
    required this.isRed,
    required this.theme,
    required this.isMobile,
    required this.isPulsing,
    required this.onTap,
  });

  final int slotIndex;
  final AnimationController entrance;
  final Suit suit;
  final String symbol;
  final String label;
  final bool isRed;
  final AppThemeData theme;
  final bool isMobile;
  final bool isPulsing;
  final VoidCallback? onTap;

  @override
  State<_SuitStripButton> createState() => _SuitStripButtonState();
}

class _SuitStripButtonState extends State<_SuitStripButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _stagger;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.14, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 60,
      ),
    ]).animate(_pulse);

    final begin = (widget.slotIndex * 0.09).clamp(0.0, 0.82);
    final end = (0.42 + widget.slotIndex * 0.11).clamp(begin + 0.12, 1.0);
    _stagger = CurvedAnimation(
      parent: widget.entrance,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void didUpdateWidget(_SuitStripButton oldWidget) {
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
    final h = widget.isMobile ? 92.0 : 104.0;

    final suitColor =
        widget.isRed ? widget.theme.suitRed : widget.theme.suitBlack;
    final borderIdle = widget.isRed
        ? widget.theme.suitRed.withValues(alpha: 0.5)
        : widget.theme.accentDark.withValues(alpha: 0.48);
    final accent = widget.theme.accentPrimary;
    final canTap = widget.onTap != null;

    return AnimatedBuilder(
      animation: Listenable.merge([_stagger, _scale]),
      builder: (context, child) {
        final enter = _stagger.value.clamp(0.0, 1.0);
        final pulseScale = widget.isPulsing ? _scale.value : 1.0;
        final hoverScale = _hover && canTap ? 1.04 : 1.0;
        return Transform.scale(
          scale: (0.82 + 0.18 * enter) * pulseScale * hoverScale,
          child: Opacity(
            opacity: enter,
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) {
          if (canTap) setState(() => _hover = true);
        },
        onExit: (_) => setState(() => _hover = false),
        cursor: canTap ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          elevation: widget.isPulsing ? 8 : (_hover && canTap ? 4 : 2),
          shadowColor: accent.withValues(alpha: 0.45),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(14),
            splashColor: accent.withValues(alpha: 0.28),
            highlightColor: accent.withValues(alpha: 0.12),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.theme.cardFace,
                    Color.lerp(
                          widget.theme.cardFace,
                          suitColor.withValues(alpha: 0.08),
                          0.35,
                        ) ??
                        widget.theme.cardFace,
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.isPulsing
                      ? accent
                      : (_hover && canTap
                          ? accent.withValues(alpha: 0.65)
                          : borderIdle),
                  width: widget.isPulsing ? 2.5 : (_hover ? 2.0 : 1.5),
                ),
                boxShadow: widget.isPulsing
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.5),
                          blurRadius: nonNegativeShadowBlur(22),
                          spreadRadius: 1,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: nonNegativeShadowBlur(8),
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: SizedBox(
                height: h,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth.clamp(48.0, 120.0);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.symbol,
                          style: TextStyle(
                            fontSize: w * 0.42,
                            color: suitColor,
                            fontWeight: FontWeight.w900,
                            shadows: [
                              Shadow(
                                color: suitColor.withValues(alpha: 0.35),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: w * 0.14,
                            fontWeight: FontWeight.w800,
                            color: suitColor.withValues(alpha: 0.92),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
