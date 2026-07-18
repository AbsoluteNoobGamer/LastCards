import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_dimensions.dart';

/// Light mode strip — mode chips only, no tactical branding.
class MatchBroadcastHeader extends ConsumerWidget {
  const MatchBroadcastHeader({
    super.key,
    required this.modeLabel,
    this.showLive = false,
    this.isHardcore = false,
    this.compact = false,
    this.scale = 1.0,
  });

  final String modeLabel;
  final bool showLive;
  final bool isHardcore;
  final bool compact;
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final fontSize = (compact ? 10.0 : 11.0) * scale;
    final chipPadH = (compact ? 10.0 : 12.0) * scale;
    final chipPadV = (compact ? 4.0 : 5.0) * scale;
    final gap = 8.0 * scale;
    final height = (compact ? 34.0 : 40.0) * scale;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 12 * scale),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ModeChip(
                label: modeLabel,
                foreground: theme.textPrimary,
                background: theme.surfacePanel.withValues(alpha: 0.75),
                border: theme.accentPrimary.withValues(alpha: 0.55),
                fontSize: fontSize,
                padH: chipPadH,
                padV: chipPadV,
              ),
              if (showLive) ...[
                SizedBox(width: gap),
                _LiveChip(
                  fontSize: fontSize,
                  padH: chipPadH,
                  padV: chipPadV,
                  accent: theme.accentPrimary,
                  surface: theme.surfacePanel,
                ),
              ],
              if (isHardcore) ...[
                SizedBox(width: gap),
                _ModeChip(
                  label: '30s',
                  foreground: const Color(0xFFFF8A80),
                  background: theme.surfaceDark.withValues(alpha: 0.7),
                  border: const Color(0xFFE53935).withValues(alpha: 0.65),
                  fontSize: fontSize,
                  padH: chipPadH,
                  padV: chipPadV,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.fontSize,
    required this.padH,
    required this.padV,
  });

  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final double fontSize;
  final double padH;
  final double padV;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
        border: Border.all(color: border, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _LiveChip extends StatefulWidget {
  const _LiveChip({
    required this.fontSize,
    required this.padH,
    required this.padV,
    required this.accent,
    required this.surface,
  });

  final double fontSize;
  final double padH;
  final double padV;
  final Color accent;
  final Color surface;

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!MediaQuery.disableAnimationsOf(context)) {
        _pulse.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = MediaQuery.disableAnimationsOf(context) ? 1.0 : _pulse.value;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.padH,
            vertical: widget.padV,
          ),
          decoration: BoxDecoration(
            color: widget.surface.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
            border: Border.all(
              color: widget.accent.withValues(alpha: 0.5),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.fontSize * 0.7,
                height: widget.fontSize * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.accent.withValues(alpha: 0.45 + 0.4 * t),
                ),
              ),
              SizedBox(width: widget.fontSize * 0.4),
              Text(
                'Live',
                style: TextStyle(
                  color: widget.accent,
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Resolves the primary mode chip label for [MatchBroadcastHeader].
String resolveMatchModeLabel({
  required bool isOnline,
  required bool isTournamentMode,
  required bool isRanked,
  required bool isBust,
}) {
  if (isBust) return 'Bust';
  if (isTournamentMode) return 'Tournament';
  if (!isOnline) return 'Solo';
  if (isRanked) return 'Ranked';
  return 'Casual';
}
