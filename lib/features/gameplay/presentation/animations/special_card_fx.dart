import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';

/// Special card visual effects — each one is a composable AnimatedWidget
/// that wraps whatever content is passed and applies its effect.
/// Effects here animate scale/opacity/gradients, not [BoxShadow] blur radii.

// ── Slam effect (2 / Black Jack) ──────────────────────────────────────────────

/// Applies a sharp deceleration slam + single surface ripple.
class SlamEffect extends StatefulWidget {
  const SlamEffect({super.key, required this.child, this.onComplete});

  final Widget child;
  final VoidCallback? onComplete;

  @override
  State<SlamEffect> createState() => _SlamEffectState();
}

class _SlamEffectState extends State<SlamEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _rippleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.06), weight: 30),
      TweenSequenceItem(
        tween: Tween(begin: 1.06, end: 1.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 70,
      ),
    ]).animate(_ctrl);

    _rippleAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.duration = Duration.zero;
      }
      _ctrl.forward().whenComplete(() => widget.onComplete?.call());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final theme = ref.watch(themeProvider).theme;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) => Stack(
            alignment: Alignment.center,
            children: [
              if (_rippleAnim.value < 0.9)
                Opacity(
                  opacity: (1 - _rippleAnim.value).clamp(0.0, 1.0),
                  child: Container(
                    width: 120 * _rippleAnim.value + 60,
                    height: 120 * _rippleAnim.value + 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.accentDark
                            .withValues(alpha: 0.6 * (1 - _rippleAnim.value)),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              Transform.scale(scale: _scaleAnim.value, child: child),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ── Red Jack pulse effect ─────────────────────────────────────────────────────

/// Warm red radial pulse emanating from the card on landing.
class RedJackPulseEffect extends StatefulWidget {
  const RedJackPulseEffect({super.key, required this.child, this.onComplete});

  final Widget child;
  final VoidCallback? onComplete;

  @override
  State<RedJackPulseEffect> createState() => _RedJackPulseEffectState();
}

class _RedJackPulseEffectState extends State<RedJackPulseEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.duration = Duration.zero;
      }
      _ctrl.forward().whenComplete(() => widget.onComplete?.call());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final theme = ref.watch(themeProvider).theme;
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, child) {
            final v = _ctrl.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: ((1 - v) * 0.7).clamp(0.0, 1.0),
                  child: Container(
                    width: 80 + 140 * v,
                    height: 80 + 140 * v,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          theme.secondaryAccent.withValues(alpha: 0.6 * (1 - v)),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          child: widget.child,
        );
      },
    );
  }
}

// ── King reverse effect ───────────────────────────────────────────────────────

/// Rotates a direction indicator arrow 180° to signal play reversal.
class KingReverseArrow extends StatefulWidget {
  const KingReverseArrow({
    super.key,
    this.clockwise = true,
    this.animate = false,
  });

  final bool clockwise;
  final bool animate;

  @override
  State<KingReverseArrow> createState() => _KingReverseArrowState();
}

class _KingReverseArrowState extends State<KingReverseArrow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _rotAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _rotAnim = Tween<double>(begin: 0, end: 3.14159).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.duration = Duration.zero;
      }
      if (widget.animate) _ctrl.forward();
    });
  }

  @override
  void didUpdateWidget(KingReverseArrow old) {
    super.didUpdateWidget(old);
    if (widget.animate && !old.animate) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.duration = Duration.zero;
      } else {
        _ctrl.duration = const Duration(milliseconds: 600);
      }
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final theme = ref.watch(themeProvider).theme;
        return AnimatedBuilder(
          animation: _rotAnim,
          builder: (_, __) => Transform.rotate(
            angle: widget.clockwise ? _rotAnim.value : -_rotAnim.value,
            child: Icon(
              Icons.rotate_right_rounded,
              color: theme.accentPrimary,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}

// ── Joker spotlight + declaration UI ─────────────────────────────────────────

/// Wraps the Joker card with a dramatic spotlight cone and
/// fades-in the declaration overlay.
class JokerSpotlightEffect extends StatefulWidget {
  const JokerSpotlightEffect({
    super.key,
    required this.child,
    required this.onDeclare,
  });

  final Widget child;
  final void Function(String suit, String rank) onDeclare;

  @override
  State<JokerSpotlightEffect> createState() => _JokerSpotlightEffectState();
}

class _JokerSpotlightEffectState extends State<JokerSpotlightEffect>
    with TickerProviderStateMixin {
  late final AnimationController _spotCtrl;
  late final AnimationController _uiCtrl;

  @override
  void initState() {
    super.initState();
    _spotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _uiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _spotCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed) _uiCtrl.forward();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _spotCtrl.duration = Duration.zero;
        _uiCtrl.duration = Duration.zero;
      }
      _spotCtrl.forward();
    });
  }

  @override
  void dispose() {
    _spotCtrl.dispose();
    _uiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final theme = ref.watch(themeProvider).theme;
        return Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _spotCtrl,
              builder: (_, __) {
                final v = _spotCtrl.value;
                return Container(
                  width: 160 * (1 - v * 0.5),
                  height: 200 * (1 - v * 0.3),
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      colors: [
                        theme.accentLight.withValues(alpha: 0.3 * v),
                        Colors.transparent,
                      ],
                    ),
                  ),
                );
              },
            ),
            widget.child,
            FadeTransition(
              opacity: _uiCtrl,
              child: _JokerDeclarationPanel(
                theme: theme,
                onDeclare: widget.onDeclare,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _JokerDeclarationPanel extends StatelessWidget {
  const _JokerDeclarationPanel({
    required this.theme,
    required this.onDeclare,
  });
  final AppThemeData theme;
  final void Function(String suit, String rank) onDeclare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surfacePanel.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentPrimary, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Declare Suit',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: theme.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final suit in ['spades', 'clubs', 'hearts', 'diamonds'])
                _SuitButton(
                  theme: theme,
                  suit: suit,
                  onTap: () => onDeclare(suit, 'joker'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuitButton extends StatelessWidget {
  const _SuitButton({
    required this.theme,
    required this.suit,
    required this.onTap,
  });
  final AppThemeData theme;
  final String suit;
  final VoidCallback onTap;

  static const _labels = {
    'spades': '♠',
    'clubs': '♣',
    'hearts': '♥',
    'diamonds': '♦',
  };

  @override
  Widget build(BuildContext context) {
    final isRed = suit == 'hearts' || suit == 'diamonds';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(6),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.backgroundMid,
          border: Border.all(color: theme.accentDark),
        ),
        child: Center(
          child: Text(
            _labels[suit] ?? suit,
            style: TextStyle(
              fontSize: 22,
              color: isRed ? theme.suitRed : theme.suitBlack,
            ),
          ),
        ),
      ),
    );
  }
}
