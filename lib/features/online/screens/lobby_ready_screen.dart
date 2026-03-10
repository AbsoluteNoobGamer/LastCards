import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/game_event.dart';
import '../../../../core/models/game_state.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../features/gameplay/presentation/screens/table_screen.dart';
import '../../../../features/tournament/providers/tournament_session_provider.dart';
import '../../../../screens/tournament_screen.dart';
import '../providers/online_session_provider.dart';

/// Full-screen lobby ready screen.
///
/// Shown once all player slots are filled. Displays a 3→2→1 countdown
/// then auto-navigates to [TableScreen].
class LobbyReadyScreen extends ConsumerStatefulWidget {
  const LobbyReadyScreen({super.key});

  @override
  ConsumerState<LobbyReadyScreen> createState() => _LobbyReadyScreenState();
}

class _LobbyReadyScreenState extends ConsumerState<LobbyReadyScreen>
    with TickerProviderStateMixin {
  int _countdown = 3;
  Timer? _countdownTimer;
  late AnimationController _countdownAnim;
  late AnimationController _pulseAnim;
  StreamSubscription<StateSnapshotEvent>? _snapshotSub;
  bool _snapshotReceived = false;
  bool _countdownDone = false;

  @override
  void initState() {
    super.initState();

    _countdownAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Listen for the state_snapshot with phase == playing from the server.
    // Navigation fires only once both the countdown has finished AND the
    // server has confirmed the game is live (whichever comes last).
    final handler = ref.read(gameEventHandlerProvider);
    _snapshotSub = handler.stateSnapshots.listen((e) {
      if (!mounted) return;
      if (e.gameState.phase == GamePhase.playing && !_snapshotReceived) {
        _snapshotReceived = true;
        if (_countdownDone) _navigateToGame();
      }
    });

    // Brief pause before countdown kicks in
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _startCountdown();
    });
  }

  void _startCountdown() {
    _pulseOnce();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown > 0) {
        _pulseOnce();
      } else {
        t.cancel();
        _countdownDone = true;
        if (_snapshotReceived) {
          _navigateToGame();
        }
        // Otherwise wait — _snapshotSub listener will call _navigateToGame()
        // once the server's state_snapshot arrives.
      }
    });
  }

  void _pulseOnce() {
    _countdownAnim.forward(from: 0);
  }

  void _navigateToGame() {
    if (!mounted) return;
    _snapshotSub?.cancel();
    _snapshotSub = null;

    final playerCount = ref.read(onlineSessionProvider).playerCount ?? 4;
    final isTournament = ref.read(tournamentSessionProvider).format != null;

    ref.read(onlineSessionProvider.notifier).reset();

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => isTournament
            ? const TournamentScreen(isOnline: true)
            : TableScreen(totalPlayers: playerCount),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _snapshotSub?.cancel();
    _countdownAnim.dispose();
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final session = ref.watch(onlineSessionProvider);
    final playerCount = session.playerCount ?? 4;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: theme.backgroundDeep,
        body: Stack(
          children: [
            // Subtle radial glow from centre
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      theme.accentPrimary.withValues(alpha: 0.06),
                      theme.backgroundDeep,
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // ── All players ready badge ─────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.accentPrimary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.accentPrimary.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: theme.accentPrimary,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'All players ready',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.accentPrimary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Last Cards title ────────────────────────────────────
                  ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      colors: [theme.accentLight, theme.accentPrimary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Text(
                      'Last Cards',
                      style: GoogleFonts.cinzel(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 3,
                      ),
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Get ready to play!',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: theme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Player avatars ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 20,
                      runSpacing: 16,
                      children: List.generate(playerCount, (i) {
                        return _ConfirmedPlayerAvatar(
                          index: i,
                          isLocalPlayer: i == 0,
                        );
                      }),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Countdown ──────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _countdownAnim,
                    builder: (context, child) {
                      final scale = Tween<double>(begin: 1.4, end: 1.0)
                          .evaluate(CurvedAnimation(
                              parent: _countdownAnim,
                              curve: Curves.easeOutBack));
                      final opacity = Tween<double>(begin: 1.0, end: 0.85)
                          .evaluate(_countdownAnim);

                      return Opacity(
                        opacity: opacity,
                        child: Transform.scale(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: ShaderMask(
                      key: ValueKey(_countdown),
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [theme.accentLight, theme.accentPrimary],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(bounds),
                      child: Text(
                        _countdown > 0 ? '$_countdown' : 'GO!',
                        style: GoogleFonts.outfit(
                          fontSize: 96,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -4,
                        ),
                      ),
                    ),
                  ),

                  Text(
                    'Starting automatically…',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.textSecondary.withValues(alpha: 0.6),
                      letterSpacing: 0.3,
                    ),
                  ),

                  const Spacer(flex: 3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confirmed Player Avatar ───────────────────────────────────────────────────

class _ConfirmedPlayerAvatar extends ConsumerStatefulWidget {
  const _ConfirmedPlayerAvatar({
    required this.index,
    required this.isLocalPlayer,
  });

  final int index;
  final bool isLocalPlayer;

  @override
  ConsumerState<_ConfirmedPlayerAvatar> createState() =>
      _ConfirmedPlayerAvatarState();
}

class _ConfirmedPlayerAvatarState
    extends ConsumerState<_ConfirmedPlayerAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _entryAnim;

  @override
  void initState() {
    super.initState();
    _entryAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    Future.delayed(Duration(milliseconds: 100 * widget.index), () {
      if (mounted) _entryAnim.forward();
    });
  }

  @override
  void dispose() {
    _entryAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    return AnimatedBuilder(
      animation: _entryAnim,
      builder: (context, child) {
        final value = CurvedAnimation(
          parent: _entryAnim,
          curve: Curves.easeOutBack,
        ).value;
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.5 + 0.5 * value,
            child: child,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.accentPrimary.withValues(alpha: 0.12),
              border: Border.all(
                color: widget.isLocalPlayer
                    ? theme.accentPrimary
                    : theme.accentPrimary.withValues(alpha: 0.45),
                width: widget.isLocalPlayer ? 2.5 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.accentPrimary.withValues(
                      alpha: widget.isLocalPlayer ? 0.30 : 0.12),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Center(
              child: Icon(
                widget.isLocalPlayer
                    ? Icons.person_rounded
                    : Icons.person_outline_rounded,
                color: theme.accentPrimary,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.isLocalPlayer ? 'You' : 'Player ${widget.index + 1}',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight:
                  widget.isLocalPlayer ? FontWeight.w700 : FontWeight.w500,
              color: widget.isLocalPlayer
                  ? theme.textPrimary
                  : theme.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          if (widget.isLocalPlayer) ...[
            const SizedBox(height: 2),
            Text(
              '★ Host',
              style: GoogleFonts.inter(
                fontSize: 9,
                color: theme.accentPrimary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
