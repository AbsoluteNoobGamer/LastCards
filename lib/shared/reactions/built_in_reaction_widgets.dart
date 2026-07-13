import 'package:flutter/material.dart';

/// Renders a [ReactionVisualKind.builtIn] reaction — a small looping
/// animation drawn purely in code (no bundled GIF/image asset).
///
/// Used at every size a reaction can appear at: the Locker preview tile
/// (~22px), the in-game picker slot (~34px), and the floating chat bubble
/// (~38-54px), so each sub-animation favors bold simple shapes over fine
/// detail that wouldn't read at the smallest size.
class BuiltInReactionIcon extends StatefulWidget {
  const BuiltInReactionIcon({required this.builtInId, required this.size, super.key});

  final String builtInId;
  final double size;

  @override
  State<BuiltInReactionIcon> createState() => _BuiltInReactionIconState();
}

class _BuiltInReactionIconState extends State<BuiltInReactionIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: switch (widget.builtInId) {
        'spinning_joker' => _SpinningJoker(controller: _controller, size: widget.size),
        'card_flip' => _CardFlip(controller: _controller, size: widget.size),
        'last_card_flare' => _LastCardFlare(controller: _controller, size: widget.size),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// A rotating 🃏 with a pulsing gold glow behind it.
class _SpinningJoker extends StatelessWidget {
  const _SpinningJoker({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        // Triangle wave 0 -> 1 -> 0 over one cycle, for a pulsing glow.
        final wave = 1 - (2 * t - 1).abs();
        final glow = 0.5 + 0.5 * wave;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size * 1.1,
              height: size * 1.1,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFE8CC7A).withValues(alpha: 0.55 * glow),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Transform.rotate(
              angle: t * 2 * 3.14159265,
              child: Text('🃏', style: TextStyle(fontSize: size * 0.72)),
            ),
          ],
        );
      },
    );
  }
}

/// Flips between ♠️ and ♥️ around the Y axis, like a card turning over.
class _CardFlip extends StatelessWidget {
  const _CardFlip({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        // Two flips per cycle: face -> edge-on -> other face -> edge-on -> face.
        final halfCycle = (t * 2) % 1.0; // 0..1 within each half-flip
        final showSecondFace = (t * 2).floor().isOdd;
        final scaleX = (1 - 2 * halfCycle).abs().clamp(0.08, 1.0);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(scaleX, 1.0, 1.0),
          child: Text(
            showSecondFace ? '♥️' : '♠️',
            style: TextStyle(fontSize: size * 0.72, color: showSecondFace ? Colors.redAccent : null),
          ),
        );
      },
    );
  }
}

/// A small card bearing a bold "1" that pulses urgently — this game's
/// namesake "down to your last card" moment.
class _LastCardFlare extends StatelessWidget {
  const _LastCardFlare({required this.controller, required this.size});

  final AnimationController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.value;
        // Triangle wave 0 -> 1 -> 0 over one cycle, for an urgent pulse.
        final wave = 1 - (2 * t - 1).abs();
        final scale = 0.9 + 0.18 * wave;
        final glowColor = Color.lerp(const Color(0xFFE8CC7A), const Color(0xFFCC2244), wave)!;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: size * 0.62,
            height: size * 0.86,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(size * 0.1),
              boxShadow: [
                BoxShadow(color: glowColor.withValues(alpha: 0.85), blurRadius: size * 0.35),
              ],
              border: Border.all(color: glowColor, width: size * 0.04),
            ),
            alignment: Alignment.center,
            child: Text(
              '1',
              style: TextStyle(
                fontSize: size * 0.5,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ),
        );
      },
    );
  }
}
