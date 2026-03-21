import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';

/// Subtle animated placeholder using theme [surfacePanel] and [accentPrimary].
class ThemedShimmer extends ConsumerStatefulWidget {
  const ThemedShimmer({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  ConsumerState<ThemedShimmer> createState() => _ThemedShimmerState();
}

class _ThemedShimmerState extends ConsumerState<ThemedShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _ctrl.value = 0.5;
      } else {
        _ctrl.repeat();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final base = theme.surfacePanel;
    final highlight = theme.accentPrimary.withValues(alpha: 0.35);

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(-1.2 + t * 2.4, 0),
                  end: Alignment(-0.2 + t * 2.4, 0),
                  colors: [
                    base,
                    highlight,
                    base,
                  ],
                  stops: const [0.25, 0.5, 0.75],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
