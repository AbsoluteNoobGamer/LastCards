import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../widgets/opponent_splash_tile.dart';
import '../widgets/opponents_splash_fx.dart';

/// Called when the splash completes; [splashContext] is the mounted splash route.
typedef OpponentsSplashOnFinished = void Function(BuildContext splashContext);

/// Full-screen splash shown before a game starts, listing you and all opponents.
class OpponentsSplashScreen extends ConsumerStatefulWidget {
  const OpponentsSplashScreen({
    required this.participants,
    required this.onFinished,
    this.modeLabel,
    this.subtitle = 'Get ready to play!',
    this.duration = const Duration(milliseconds: 3200),
    this.showCountdown = true,
    this.holdCountdown = false,
    super.key,
  });

  final List<OpponentSplashParticipant> participants;
  final OpponentsSplashOnFinished onFinished;
  final String? modeLabel;
  final String subtitle;
  final Duration duration;

  /// When true, shows a 3→2→1→GO countdown before [onFinished].
  final bool showCountdown;

  /// When true, the countdown does not start until this becomes false (online sync).
  final bool holdCountdown;

  @override
  ConsumerState<OpponentsSplashScreen> createState() =>
      _OpponentsSplashScreenState();
}

class _OpponentsSplashScreenState extends ConsumerState<OpponentsSplashScreen>
    with TickerProviderStateMixin {
  static const _countdownStartDelay = Duration(milliseconds: 1400);

  int _countdown = 3;
  Timer? _countdownTimer;
  Timer? _finishTimer;
  bool _finished = false;
  bool _countdownVisible = false;
  bool _countdownScheduled = false;

  late AnimationController _intro;
  late AnimationController _countdownPop;
  late AnimationController _flash;
  late AnimationController _burst;
  late AnimationController _shimmer;
  late AnimationController _vsLine;
  late Animation<double> _backdropIntensity;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _countdownPop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _vsLine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _backdropIntensity = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final disable = MediaQuery.disableAnimationsOf(context);
      if (!disable) {
        _intro.forward();
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _vsLine.forward();
        });
      } else {
        _intro.value = 1;
        _vsLine.value = 1;
      }
    });

    if (widget.showCountdown && !widget.holdCountdown) {
      _scheduleCountdown();
    } else if (!widget.showCountdown) {
      _finishTimer = Timer(widget.duration, _complete);
    }
  }

  @override
  void didUpdateWidget(covariant OpponentsSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.holdCountdown &&
        !widget.holdCountdown &&
        widget.showCountdown &&
        !_countdownScheduled) {
      _scheduleCountdown();
    }
  }

  void _scheduleCountdown() {
    if (_countdownScheduled) return;
    _countdownScheduled = true;
    Future.delayed(_countdownStartDelay, () {
      if (!mounted || _finished) return;
      setState(() => _countdownVisible = true);
      _tickCountdown();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _countdown--);
        if (_countdown > 0) {
          _tickCountdown();
        } else {
          t.cancel();
          _tickGo();
          Future.delayed(const Duration(milliseconds: 650), _complete);
        }
      });
    });
  }

  void _tickCountdown() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    HapticFeedback.mediumImpact();
    _countdownPop.forward(from: 0);
    _flash.forward(from: 0);
    _burst.forward(from: 0);
  }

  void _tickGo() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    HapticFeedback.heavyImpact();
    _countdownPop.duration = const Duration(milliseconds: 680);
    _countdownPop.forward(from: 0);
    _flash.duration = const Duration(milliseconds: 520);
    _flash.forward(from: 0);
    _burst.forward(from: 0);
  }

  void _complete() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished(context);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _finishTimer?.cancel();
    _intro.dispose();
    _countdownPop.dispose();
    _flash.dispose();
    _burst.dispose();
    _shimmer.dispose();
    _vsLine.dispose();
    super.dispose();
  }

  List<OpponentSplashParticipant> get _sortedParticipants {
    final local =
        widget.participants.where((p) => p.isLocalPlayer).toList();
    final opponents =
        widget.participants.where((p) => !p.isLocalPlayer).toList();
    return [...local, ...opponents];
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final compact = widget.participants.length > 6;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final sorted = _sortedParticipants;
    final local = sorted.where((p) => p.isLocalPlayer).toList();
    final opponents = sorted.where((p) => !p.isLocalPlayer).toList();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.backgroundDeep,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _backdropIntensity,
              builder: (_, __) => OpponentsSplashBackdrop(
                theme: theme,
                intensity: disableAnim ? 1 : _backdropIntensity.value,
              ),
            ),
            OpponentsSplashFlashOverlay(
              progress: disableAnim ? 0 : _flash.value,
              color: _countdown <= 0 && _countdownVisible
                  ? theme.accentLight
                  : theme.accentPrimary,
            ),
            OpponentsSplashCountdownBurst(
              progress: disableAnim ? 0 : _burst.value,
              theme: theme,
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  _buildHeader(theme, disableAnim),
                  const SizedBox(height: 12),
                  _buildVsDivider(theme, disableAnim),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 12 : 24,
                      ),
                      child: Column(
                        children: [
                          if (local.isNotEmpty)
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                for (var i = 0; i < local.length; i++)
                                  OpponentSplashTile(
                                    participant: local[i],
                                    index: i,
                                    compact: compact,
                                    totalCount: sorted.length,
                                  ),
                              ],
                            ),
                          if (local.isNotEmpty && opponents.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'VS',
                                style: GoogleFonts.cinzel(
                                  fontSize: compact ? 22 : 28,
                                  fontWeight: FontWeight.w900,
                                  color: theme.accentPrimary
                                      .withValues(alpha: 0.7),
                                  letterSpacing: 6,
                                ),
                              ),
                            ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: compact ? 10 : 18,
                            runSpacing: compact ? 10 : 14,
                            children: [
                              for (var i = 0; i < opponents.length; i++)
                                OpponentSplashTile(
                                  participant: opponents[i],
                                  index: i + local.length,
                                  compact: compact,
                                  totalCount: sorted.length,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.showCountdown && _countdownVisible) ...[
                    _buildCountdown(theme, disableAnim),
                    const SizedBox(height: 6),
                    _buildCountdownCaption(theme),
                  ] else if (!widget.showCountdown) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Dealing soon…',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: theme.textSecondary.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ] else
                    const SizedBox(height: 88),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppThemeData theme, bool disableAnim) {
    final header = Column(
      children: [
        if (widget.modeLabel != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: theme.accentPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.accentPrimary.withValues(alpha: 0.4),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.accentPrimary.withValues(alpha: 0.2),
                  blurRadius: 16,
                ),
              ],
            ),
            child: Text(
              widget.modeLabel!,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.accentPrimary,
                letterSpacing: 0.6,
              ),
            ),
          ),
        if (widget.modeLabel != null) const SizedBox(height: 14),
        _titleText(theme, disableAnim),
        const SizedBox(height: 8),
        Text(
          widget.subtitle.toUpperCase(),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.textSecondary,
            letterSpacing: 2.0,
          ),
        ),
      ],
    );

    if (disableAnim) return header;

    return FadeTransition(
      opacity: CurvedAnimation(parent: _intro, curve: Curves.easeOut),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.12),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic)),
        child: header,
      ),
    );
  }

  Widget _titleText(AppThemeData theme, bool disableAnim) {
    final style = GoogleFonts.cinzel(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      letterSpacing: 4,
    );

    if (disableAnim) {
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [theme.accentLight, theme.accentPrimary, theme.accentLight],
        ).createShader(bounds),
        child: Text('Last Cards', textAlign: TextAlign.center, style: style),
      );
    }

    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final t = _shimmer.value;
        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.2 + 2.4 * t, -0.5),
            end: Alignment(0.2 + 2.4 * t, 0.5),
            colors: [
              theme.accentLight,
              theme.accentPrimary,
              theme.accentLight,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: Text('Last Cards', textAlign: TextAlign.center, style: style),
        );
      },
    );
  }

  Widget _buildVsDivider(AppThemeData theme, bool disableAnim) {
    final line = Row(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: _vsLine,
            builder: (_, __) {
              final w = CurvedAnimation(
                parent: _vsLine,
                curve: Curves.easeOutCubic,
              ).value;
              return Align(
                alignment: Alignment.centerRight,
                child: Container(
                  height: 1.5,
                  width: MediaQuery.sizeOf(context).width * 0.32 * w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        theme.accentPrimary.withValues(alpha: 0.6),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'OPPONENTS',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: theme.accentPrimary.withValues(alpha: 0.9),
              letterSpacing: 2.0,
            ),
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _vsLine,
            builder: (_, __) {
              final w = CurvedAnimation(
                parent: _vsLine,
                curve: Curves.easeOutCubic,
              ).value;
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 1.5,
                  width: MediaQuery.sizeOf(context).width * 0.32 * w,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.accentPrimary.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );

    if (disableAnim) return line;
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _vsLine,
        curve: const Interval(0.2, 1, curve: Curves.easeOut),
      ),
      child: line,
    );
  }

  Widget _buildCountdown(AppThemeData theme, bool disableAnim) {
    final isGo = _countdown <= 0;
    final label = isGo ? 'GO!' : '$_countdown';

    Widget number = ShaderMask(
      key: ValueKey(label),
      shaderCallback: (bounds) => LinearGradient(
        colors: isGo
            ? [Colors.white, theme.accentLight, theme.accentPrimary]
            : [theme.accentLight, theme.accentPrimary],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(bounds),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: isGo ? 88 : 80,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          letterSpacing: isGo ? 2 : -4,
          shadows: [
            Shadow(
              color: theme.accentPrimary.withValues(alpha: 0.65),
              blurRadius: 24,
            ),
          ],
        ),
      ),
    );

    if (!disableAnim) {
      number = AnimatedBuilder(
        animation: _countdownPop,
        builder: (context, child) {
          final t = CurvedAnimation(
            parent: _countdownPop,
            curve: isGo ? Curves.elasticOut : Curves.easeOutBack,
          ).value;
          final scale = isGo
              ? Tween<double>(begin: 2.2, end: 1.0).transform(t)
              : Tween<double>(begin: 1.8, end: 1.0).transform(t);
          final opacity = Tween<double>(begin: 0, end: 1)
              .transform(Curves.easeOut.transform(t.clamp(0.0, 1.0)));
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: number,
      );
    }

    return SizedBox(
      height: 100,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: number,
        ),
      ),
    );
  }

  Widget _buildCountdownCaption(AppThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: Text(
        _countdown > 0 ? 'Stand by…' : 'Deal the cards!',
        key: ValueKey(_countdown > 0),
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: theme.textSecondary.withValues(alpha: 0.75),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
