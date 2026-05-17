import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/widgets/gameplay_circle_avatar.dart';

/// One seat on the pre-game opponents splash (local human or AI).
class OpponentSplashParticipant {
  const OpponentSplashParticipant({
    required this.displayName,
    this.isLocalPlayer = false,
    this.avatarColor,
    this.avatarUrl,
    this.initials,
    this.badgeLabel,
  });

  final String displayName;
  final bool isLocalPlayer;
  final Color? avatarColor;
  final String? avatarUrl;
  final String? initials;
  final String? badgeLabel;
}

class OpponentSplashTile extends ConsumerStatefulWidget {
  const OpponentSplashTile({
    required this.participant,
    required this.index,
    this.compact = false,
    this.totalCount = 1,
    super.key,
  });

  final OpponentSplashParticipant participant;
  final int index;
  final bool compact;
  final int totalCount;

  @override
  ConsumerState<OpponentSplashTile> createState() => _OpponentSplashTileState();
}

class _OpponentSplashTileState extends ConsumerState<OpponentSplashTile>
    with TickerProviderStateMixin {
  late AnimationController _entry;
  late AnimationController _glow;
  late Animation<double> _slide;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<double> _nameOpacity;
  late Animation<Offset> _nameSlide;

  @override
  void initState() {
    super.initState();
    final isLocal = widget.participant.isLocalPlayer;
    final delayMs = isLocal ? 200 : 280 + widget.index * 110;

    _entry = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: isLocal ? 750 : 680),
    );
    _glow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    final curve = CurvedAnimation(
      parent: _entry,
      curve: Curves.easeOutBack,
    );
    _slide = Tween<double>(begin: isLocal ? 0.0 : (widget.index.isOdd ? 28 : -28), end: 0)
        .animate(curve);
    _scale = Tween<double>(begin: isLocal ? 0.3 : 0.15, end: isLocal ? 1.12 : 1.0)
        .animate(curve);
    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entry, curve: const Interval(0, 0.55, curve: Curves.easeOut)),
    );
    _nameOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _entry, curve: const Interval(0.45, 1, curve: Curves.easeOut)),
    );
    _nameSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
      CurvedAnimation(parent: _entry, curve: const Interval(0.45, 1, curve: Curves.easeOut)),
    );

    if (isLocal) {
      _glow.repeat(reverse: true);
    }

    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _entry.forward();
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    _glow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final p = widget.participant;
    final size = widget.compact ? 52.0 : (p.isLocalPlayer ? 72.0 : 64.0);

    return AnimatedBuilder(
      animation: Listenable.merge([_entry, _glow]),
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(_slide.value, (1 - _opacity.value) * 24),
            child: Transform.scale(
              scale: _scale.value,
              child: child,
            ),
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AvatarRing(
            theme: theme,
            size: size,
            participant: p,
            glowStrength: p.isLocalPlayer ? 0.35 + _glow.value * 0.35 : 0,
          ),
          SizedBox(height: widget.compact ? 4 : 8),
          FadeTransition(
            opacity: _nameOpacity,
            child: SlideTransition(
              position: _nameSlide,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: widget.compact ? 72 : (p.isLocalPlayer ? 100 : 88),
                    child: Text(
                      p.displayName,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: widget.compact
                            ? 10
                            : (p.isLocalPlayer ? 14 : 11),
                        fontWeight: p.isLocalPlayer
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: p.isLocalPlayer
                            ? theme.textPrimary
                            : theme.textSecondary,
                        letterSpacing: p.isLocalPlayer ? 0.4 : 0.2,
                      ),
                    ),
                  ),
                  if (p.isLocalPlayer) ...[
                    const SizedBox(height: 4),
                    _LocalYouBadge(theme: theme, compact: widget.compact),
                  ] else if (p.badgeLabel != null) ...[
                    const SizedBox(height: 3),
                    _PersonalityChip(
                      label: p.badgeLabel!,
                      color: p.avatarColor ?? theme.accentPrimary,
                      compact: widget.compact,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalYouBadge extends StatelessWidget {
  const _LocalYouBadge({required this.theme, required this.compact});

  final AppThemeData theme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [theme.accentLight, theme.accentPrimary],
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        'YOU',
        style: GoogleFonts.inter(
          fontSize: compact ? 8 : 9,
          fontWeight: FontWeight.w800,
          color: theme.backgroundDeep,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _PersonalityChip extends StatelessWidget {
  const _PersonalityChip({
    required this.label,
    required this.color,
    required this.compact,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: compact ? 8 : 9,
          color: color.withValues(alpha: 0.95),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({
    required this.theme,
    required this.size,
    required this.participant,
    this.glowStrength = 0,
  });

  final AppThemeData theme;
  final double size;
  final OpponentSplashParticipant participant;
  final double glowStrength;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final accent = p.avatarColor ?? theme.accentPrimary;
    final fill = p.isLocalPlayer
        ? theme.accentPrimary.withValues(alpha: 0.18)
        : accent.withValues(alpha: 0.38);
    final border = p.isLocalPlayer ? theme.accentLight : accent;

    return Container(
      width: size + 12,
      height: size + 12,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          if (glowStrength > 0)
            BoxShadow(
              color: theme.accentPrimary.withValues(alpha: glowStrength),
              blurRadius: 28,
              spreadRadius: 4,
            ),
          BoxShadow(
            color: border.withValues(alpha: p.isLocalPlayer ? 0.5 : 0.28),
            blurRadius: p.isLocalPlayer ? 20 : 14,
            spreadRadius: p.isLocalPlayer ? 1 : 0,
          ),
        ],
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(
            color: border,
            width: p.isLocalPlayer ? 3 : 2,
          ),
        ),
        child: ClipOval(
          child: GameplayCircleAvatar(
            radius: size / 2 - 2,
            displayName: p.displayName,
            avatarUrl: p.avatarUrl,
            initialsOverride: p.initials,
            foregroundTextStyle: TextStyle(
              color: Colors.white,
              fontSize: size * 0.28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
