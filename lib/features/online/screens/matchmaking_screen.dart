import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/game_event.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/providers/game_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../tournament/providers/tournament_session_provider.dart';
import '../providers/online_session_provider.dart';
import 'lobby_ready_screen.dart';

/// Default MMR when no ranked_stats doc exists (from server trophy_recorder).
const _kInitialRating = 1000;

/// Full-screen matchmaking screen.
///
/// Shows an animated waiting indicator and player slots that fill in
/// as players "join" (simulated via a demo timer).
/// The only exit is the Cancel button which pops to root.
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotateController;
  late AnimationController _pulseController;
  late List<bool> _slotsJoined;
  StreamSubscription<GameEvent>? _eventSub;

  @override
  void initState() {
    super.initState();

    // Orbital ring rotation
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Slow pulse on the centre glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    final playerCount = ref.read(onlineSessionProvider).playerCount ?? 4;
    // Slot 0 = local player (always joined)
    _slotsJoined = List.generate(playerCount, (i) => i == 0);

    // Ensure GameNotifier is subscribed before any state_snapshot arrives,
    // so the snapshot is captured even during the navigation delay.
    ref.read(gameNotifierProvider);

    // Listen for real player_joined events from the server
    final handler = ref.read(gameEventHandlerProvider);
    int nextSlot = 1;
    _eventSub = handler.events.listen((event) {
      if (!mounted) return;
      if (event is PlayerJoinedEvent && nextSlot < playerCount) {
        setState(() => _slotsJoined[nextSlot] = true);
        nextSlot++;
        if (nextSlot >= playerCount) {
          _eventSub?.cancel();
          _eventSub = null;
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            _navigatedForward = true;
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const LobbyReadyScreen(),
                transitionDuration: const Duration(milliseconds: 500),
                transitionsBuilder: (_, animation, __, child) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              ),
            );
          });
        }
      }
    });

    // Connect to the server and send a quickplay matchmaking request.
    final isBust = ref.read(tournamentSessionProvider).subMode == GameSubMode.bust;
    final isRanked = ref.read(onlineSessionProvider).mode == OnlineGameMode.ranked;
    final displayName = ref.read(displayNameForGameProvider);
    _connectAndRequestMatch(playerCount, displayName: displayName, isBust: isBust, isRanked: isRanked);
  }

  Future<void> _connectAndRequestMatch(
    int playerCount, {
    required String displayName,
    bool isBust = false,
    bool isRanked = false,
  }) async {
    final wsClient = ref.read(wsClientProvider);
    final authService = ref.read(authServiceProvider);
    final idToken = await authService.getIdToken();
    try {
      await wsClient.connect();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: const Color(0xFFB71C1C),
        ),
      );
      return;
    }
    if (!mounted) return;

    String? gameMode;
    if (isBust) {
      gameMode = 'bust';
    } else if (isRanked) {
      gameMode = 'ranked';
    }

    wsClient.send(jsonEncode({
      'type': 'quickplay',
      'playerCount': playerCount,
      if (gameMode != null) 'gameMode': gameMode,
      'displayName': displayName.isEmpty ? 'Player' : displayName,
      if (idToken != null) 'idToken': idToken,
    }));
  }

  bool _navigatedForward = false;

  @override
  void dispose() {
    _rotateController.dispose();
    _pulseController.dispose();
    _eventSub?.cancel();
    // Only disconnect if the user cancelled — not on forward navigation.
    if (!_navigatedForward) {
      ref.read(wsClientProvider).disconnect();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final session = ref.watch(onlineSessionProvider);
    final playerCount = session.playerCount ?? 4;
    final modeName = session.mode?.displayName ?? 'Quick Match';
    final joinedCount = _slotsJoined.where((s) => s).length;

    return PopScope(
      canPop: false, // Only Cancel button exits
      child: Scaffold(
        backgroundColor: theme.backgroundDeep,
        body: Stack(
          children: [
            // Background subtle dot texture
            Positioned.fill(
              child: CustomPaint(
                painter: _DotGridPainter(
                  dotColor: theme.accentPrimary.withValues(alpha: 0.04),
                ),
              ),
            ),

            // Radial vignette
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [
                      theme.backgroundDeep.withValues(alpha: 0.0),
                      theme.backgroundDeep.withValues(alpha: 0.85),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ),

            // Main content
            Positioned.fill(
              child: SafeArea(
                child: OrientationBuilder(
                  builder: (context, orientation) {
                    final isLandscape =
                        orientation == Orientation.landscape;
                    if (isLandscape) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.center,
                                  children: [
                                    ShaderMask(
                                      shaderCallback: (bounds) =>
                                          LinearGradient(
                                        colors: [
                                          theme.accentLight,
                                          theme.accentPrimary,
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ).createShader(bounds),
                                      child: Text(
                                        'Last Cards',
                                        style: GoogleFonts.cinzel(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$modeName · $playerCount Players',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: theme.textSecondary,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    if (session.mode == OnlineGameMode.ranked)
                                      _RankedMmrDisplay(theme: theme),
                                    const SizedBox(height: 16),
                                    _AnimatedWaitingIndicator(
                                      rotateController: _rotateController,
                                      pulseController: _pulseController,
                                      joinedCount: joinedCount,
                                      totalCount: playerCount,
                                    ),
                                    const SizedBox(height: 8),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                          milliseconds: 300),
                                      child: Text(
                                        'Finding players… ($joinedCount/$playerCount)',
                                        key: ValueKey(joinedCount),
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: theme.textSecondary,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 16,
                                    runSpacing: 12,
                                    children:
                                        List.generate(playerCount, (i) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6),
                                        child: _PlayerSlot(
                                          index: i,
                                          isJoined: _slotsJoined[i],
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 40),
                            child: _CancelButton(
                              onTap: () {
                                ref
                                    .read(onlineSessionProvider.notifier)
                                    .reset();
                                Navigator.of(context)
                                    .popUntil((r) => r.isFirst);
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 32),
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [
                              theme.accentLight,
                              theme.accentPrimary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: Text(
                            'Last Cards',
                            style: GoogleFonts.cinzel(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$modeName · $playerCount Players',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: theme.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (session.mode == OnlineGameMode.ranked)
                          _RankedMmrDisplay(theme: theme),
                        const Spacer(flex: 1),
                        _AnimatedWaitingIndicator(
                          rotateController: _rotateController,
                          pulseController: _pulseController,
                          joinedCount: joinedCount,
                          totalCount: playerCount,
                        ),
                        const SizedBox(height: 16),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            'Finding players… ($joinedCount/$playerCount)',
                            key: ValueKey(joinedCount),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: theme.textSecondary,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(playerCount, (i) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10),
                                child: _PlayerSlot(
                                  index: i,
                                  isJoined: _slotsJoined[i],
                                ),
                              );
                            }),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 40),
                          child: _CancelButton(
                            onTap: () {
                              ref
                                  .read(onlineSessionProvider.notifier)
                                  .reset();
                              Navigator.of(context)
                                  .popUntil((r) => r.isFirst);
                            },
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Animated Waiting Indicator ────────────────────────────────────────────────

class _AnimatedWaitingIndicator extends ConsumerWidget {
  const _AnimatedWaitingIndicator({
    required this.rotateController,
    required this.pulseController,
    required this.joinedCount,
    required this.totalCount,
  });

  final AnimationController rotateController;
  final AnimationController pulseController;
  final int joinedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;
    final accent = theme.accentPrimary;
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final size = (shortestSide * 0.36).clamp(110.0, 150.0);

    final centerSize = size * 0.46;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: Listenable.merge([rotateController, pulseController]),
        builder: (context, child) {
          final pulse = 0.85 + 0.15 * pulseController.value;

          return CustomPaint(
            painter: _WaitingRingPainter(
              angle: rotateController.value * 2 * math.pi,
              accent: accent,
              progress: joinedCount / totalCount,
            ),
            child: Center(
              child: Transform.scale(
                scale: pulse,
                child: Container(
                  width: centerSize,
                  height: centerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.10),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.30),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(
                            alpha: 0.20 + 0.15 * pulseController.value),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$joinedCount/$totalCount',
                      style: GoogleFonts.outfit(
                        fontSize: (centerSize * 0.35).clamp(12, 18),
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaitingRingPainter extends CustomPainter {
  const _WaitingRingPainter({
    required this.angle,
    required this.accent,
    required this.progress,
  });

  final double angle;
  final Color accent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Dim background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Progress arc
    final progressPaint = Paint()
      ..color = accent.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );

    // Spinning dots
    final dotPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      final dotAngle = angle + (2 * math.pi / 3) * i;
      final dx = center.dx + radius * math.cos(dotAngle);
      final dy = center.dy + radius * math.sin(dotAngle);
      final opacity = 0.4 + 0.6 * ((math.sin(dotAngle * 1.5) + 1) / 2);
      canvas.drawCircle(
        Offset(dx, dy),
        4,
        dotPaint..color = accent.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_WaitingRingPainter old) => true;
}

// ── Player Slot ───────────────────────────────────────────────────────────────

class _PlayerSlot extends ConsumerWidget {
  const _PlayerSlot({required this.index, required this.isJoined});

  final int index;
  final bool isJoined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isJoined
                  ? theme.accentPrimary.withValues(alpha: 0.18)
                  : theme.surfaceDark.withValues(alpha: 0.35),
              border: Border.all(
                color: isJoined
                    ? theme.accentPrimary
                    : theme.accentDark.withValues(alpha: 0.3),
                width: isJoined ? 2 : 1,
              ),
              boxShadow: isJoined
                  ? [
                      BoxShadow(
                        color: theme.accentPrimary.withValues(alpha: 0.30),
                        blurRadius: 14,
                        spreadRadius: 0,
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: isJoined
                    ? Icon(
                        index == 0
                            ? Icons.person_rounded
                            : Icons.person_outline_rounded,
                        key: const ValueKey('joined'),
                        color: theme.accentPrimary,
                        size: 26,
                      )
                    : Text(
                        '···',
                        key: const ValueKey('waiting'),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: theme.textSecondary.withValues(alpha: 0.4),
                          letterSpacing: 2,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isJoined ? (index == 0 ? 'You' : 'Player ${index + 1}') : '…',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: isJoined
                  ? theme.textPrimary
                  : theme.textSecondary.withValues(alpha: 0.4),
              fontWeight: isJoined ? FontWeight.w600 : FontWeight.w400,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cancel Button ─────────────────────────────────────────────────────────────

class _CancelButton extends ConsumerWidget {
  const _CancelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider).theme;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.textSecondary,
          side: BorderSide(
            color: theme.accentDark.withValues(alpha: 0.5),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          'Cancel',
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: theme.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

// ── Dot Grid Background Painter ───────────────────────────────────────────────

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.dotColor});

  final Color dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    for (double x = spacing / 2; x < size.width; x += spacing) {
      for (double y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.dotColor != dotColor;
}

// ── Ranked MMR display ────────────────────────────────────────────────────────

/// Shows current MMR when in ranked mode. Fetches from ranked_stats Firestore.
/// Defaults to 1000 MMR if no doc exists (trophy_recorder._kInitialRating).
class _RankedMmrDisplay extends StatelessWidget {
  const _RankedMmrDisplay({required this.theme});

  final AppThemeData theme;

  static const _defaultMmr = 1000;

  Future<int> _fetchMmr() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _defaultMmr;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('ranked_stats')
          .doc(uid)
          .get();
      if (!doc.exists) return _defaultMmr;
      final d = doc.data() as Map<String, dynamic>? ?? {};
      return (d['rating'] as num?)?.toInt() ?? _defaultMmr;
    } catch (_) {
      return _defaultMmr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _fetchMmr(),
      builder: (context, snap) {
        final mmr = snap.data ?? _defaultMmr;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$mmr MMR',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: theme.accentPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        );
      },
    );
  }
}
