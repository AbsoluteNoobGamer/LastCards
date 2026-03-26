import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/game_event.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/models/table_position_layout.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/providers/game_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../tournament/providers/tournament_session_provider.dart';
import '../providers/online_session_provider.dart';
import 'lobby_ready_screen.dart';

/// Full-screen matchmaking screen (all online quickplay entry points use this).
///
/// Shows a progress ring and player slots that fill from
/// [QuickplayQueueUpdateEvent] while waiting, then advances when the roster is
/// complete. The only exit is the Cancel button which pops to root.
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen>
    with TickerProviderStateMixin {
  late AnimationController _rotateController;
  late AnimationController _pulseController;

  /// Per-slot display name; `null` = still waiting for that seat.
  late List<String?> _slotNames;

  /// Queue / roster index of the local player (highlighted avatar).
  late int _yourSlotIndex;

  final Map<String, PlayerModel> _matchedPlayers = {};
  StreamSubscription<GameEvent>? _eventSub;
  bool _lobbyNavigationScheduled = false;

  @override
  void initState() {
    super.initState();

    // Smooth highlight travel along the ring
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Slow, subtle pulse on the centre orb
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    final playerCount = ref.read(onlineSessionProvider).playerCount ?? 4;
    final local = ref.read(displayNameForGameProvider);
    final localLabel = local.isEmpty ? 'Player' : local;
    _slotNames = List<String?>.generate(
      playerCount,
      (i) => i == 0 ? localLabel : null,
    );
    _yourSlotIndex = 0;

    // Ensure GameNotifier is subscribed before any state_snapshot arrives,
    // so the snapshot is captured even during the navigation delay.
    ref.read(gameNotifierProvider);

    final handler = ref.read(gameEventHandlerProvider);
    _eventSub = handler.events.listen((event) {
      if (!mounted) return;
      if (event is QuickplayQueueUpdateEvent) {
        _onQueueUpdate(event);
      } else if (event is PlayerJoinedEvent) {
        _onPlayerJoined(event);
      }
    });

    // Connect to the server and send a quickplay matchmaking request.
    final isBust = ref.read(tournamentSessionProvider).subMode == GameSubMode.bust;
    final isRanked = ref.read(onlineSessionProvider).mode == OnlineGameMode.ranked;
    final displayName = ref.read(displayNameForGameProvider);
    _connectAndRequestMatch(playerCount, displayName: displayName, isBust: isBust, isRanked: isRanked);
  }

  void _onQueueUpdate(QuickplayQueueUpdateEvent e) {
    final playerCount = ref.read(onlineSessionProvider).playerCount ?? 4;
    if (e.playerCount != playerCount) return;
    setState(() {
      final you = e.yourIndex.clamp(0, playerCount - 1);
      _yourSlotIndex = you;
      for (var i = 0; i < playerCount; i++) {
        _slotNames[i] =
            i < e.displayNames.length ? e.displayNames[i] : null;
      }
    });
  }

  void _onPlayerJoined(PlayerJoinedEvent e) {
    final playerCount = ref.read(onlineSessionProvider).playerCount ?? 4;
    _matchedPlayers[e.player.id] = e.player;
    _applyMatchedPlayersToSlots(playerCount);
    if (_matchedPlayers.length >= playerCount) {
      _scheduleNavigateToLobby();
    }
  }

  /// Maps session roster to the linear matchmaking slots (seat order).
  void _applyMatchedPlayersToSlots(int playerCount) {
    if (_matchedPlayers.isEmpty) return;
    final bySeat = <TablePosition, PlayerModel>{};
    for (final p in _matchedPlayers.values) {
      bySeat[p.tablePosition] = p;
    }
    setState(() {
      for (var s = 0; s < playerCount; s++) {
        final p = bySeat[tablePositionForSeatIndex(s)];
        if (p != null) {
          _slotNames[s] = p.displayName;
        }
      }
    });
  }

  void _scheduleNavigateToLobby() {
    if (_lobbyNavigationScheduled) return;
    _lobbyNavigationScheduled = true;
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

    if (!wsClient.send(jsonEncode({
      'type': 'quickplay',
      'playerCount': playerCount,
      if (gameMode != null) 'gameMode': gameMode,
      'displayName': displayName.isEmpty ? 'Player' : displayName,
      if (idToken != null) 'idToken': idToken,
    }))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection lost. Reconnecting — try again.'),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
      return;
    }
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
    final joinedCount = _slotNames.where((n) => n != null).length;

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
                                        textAlign: TextAlign.center,
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
                                          label: _slotNames[i] ?? '…',
                                          isFilled: _slotNames[i] != null,
                                          isLocalSlot: i == _yourSlotIndex,
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
                        Center(
                          child: ShaderMask(
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
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$modeName · $playerCount Players',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: theme.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (session.mode == OnlineGameMode.ranked)
                          Center(child: _RankedMmrDisplay(theme: theme)),
                        const Spacer(flex: 1),
                        Center(
                          child: _AnimatedWaitingIndicator(
                            rotateController: _rotateController,
                            pulseController: _pulseController,
                            joinedCount: joinedCount,
                            totalCount: playerCount,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              'Finding players… ($joinedCount/$playerCount)',
                              key: ValueKey(joinedCount),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: theme.textSecondary,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 14,
                            children: List.generate(playerCount, (i) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: _PlayerSlot(
                                  label: _slotNames[i] ?? '…',
                                  isFilled: _slotNames[i] != null,
                                  isLocalSlot: i == _yourSlotIndex,
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
          final pulse = 0.97 + 0.03 * pulseController.value;
          final highlightLift = 0.65 +
              0.35 *
                  (1 + math.sin(pulseController.value * math.pi)) /
                  2;
          final denom = math.max(1, totalCount);

          return CustomPaint(
            painter: _WaitingRingPainter(
              highlightAngle: rotateController.value * 2 * math.pi,
              accent: accent,
              progress: joinedCount / denom,
              highlightIntensity: highlightLift,
            ),
            child: Center(
              child: Transform.scale(
                scale: pulse,
                child: Container(
                  width: centerSize,
                  height: centerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Color.lerp(accent, Colors.white, 0.22)!,
                        accent.withValues(alpha: 0.14),
                        accent.withValues(alpha: 0.06),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                      center: const Alignment(-0.4, -0.45),
                      radius: 1.05,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(
                            alpha: 0.12 + 0.16 * pulseController.value),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 6),
                      ),
                    ],
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
    required this.highlightAngle,
    required this.accent,
    required this.progress,
    required this.highlightIntensity,
  });

  /// Radians; soft specular travels the ring.
  final double highlightAngle;
  final Color accent;
  final double progress;
  final double highlightIntensity;

  static const _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accent.withValues(alpha: 0.11)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      center,
      radius - 1.5,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (sweep > 0) {
      canvas.drawArc(
        rect,
        _startAngle,
        sweep,
        false,
        Paint()
          ..color = accent.withValues(alpha: 0.14)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );

      canvas.drawArc(
        rect,
        _startAngle,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(accent, Colors.white, 0.12)!,
      );

      final brightSweep = (sweep * 0.22).clamp(0.0, sweep);
      if (brightSweep > 0.02) {
        canvas.drawArc(
          rect,
          _startAngle + sweep - brightSweep,
          brightSweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.2
            ..strokeCap = StrokeCap.round
            ..color = Color.lerp(accent, Colors.white, 0.45)!,
        );
      }

      if (sweep > 0.04) {
        final tip = _startAngle + sweep;
        final tipPos = Offset(
          center.dx + radius * math.cos(tip),
          center.dy + radius * math.sin(tip),
        );
        canvas.drawCircle(
          tipPos,
          4.2,
          Paint()
            ..color = Color.lerp(accent, Colors.white, 0.55)!
                .withValues(alpha: 0.95)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          tipPos,
          2,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55)
            ..style = PaintingStyle.fill,
        );
      }
    }

    final hx = center.dx + radius * math.cos(highlightAngle);
    final hy = center.dy + radius * math.sin(highlightAngle);
    final hi = 0.35 + 0.65 * highlightIntensity;
    canvas.drawCircle(
      Offset(hx, hy),
      5,
      Paint()
        ..color = accent.withValues(alpha: 0.08 * hi)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset(hx, hy),
      3,
      Paint()
        ..color = Color.lerp(accent, Colors.white, 0.35)!
            .withValues(alpha: 0.55 * hi),
    );
  }

  @override
  bool shouldRepaint(_WaitingRingPainter old) =>
      old.highlightAngle != highlightAngle ||
      old.progress != progress ||
      old.accent != accent ||
      old.highlightIntensity != highlightIntensity;
}

// ── Player Slot ───────────────────────────────────────────────────────────────

class _PlayerSlot extends ConsumerWidget {
  const _PlayerSlot({
    required this.label,
    required this.isFilled,
    required this.isLocalSlot,
  });

  final String label;
  final bool isFilled;
  final bool isLocalSlot;

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
              color: isFilled
                  ? theme.accentPrimary.withValues(alpha: 0.18)
                  : theme.surfaceDark.withValues(alpha: 0.35),
              border: Border.all(
                color: isFilled
                    ? theme.accentPrimary
                    : theme.accentDark.withValues(alpha: 0.3),
                width: isFilled ? 2 : 1,
              ),
              boxShadow: isFilled
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
                child: isFilled
                    ? Icon(
                        isLocalSlot
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
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: isFilled
                  ? theme.textPrimary
                  : theme.textSecondary.withValues(alpha: 0.4),
              fontWeight: isFilled ? FontWeight.w600 : FontWeight.w400,
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
class _RankedMmrDisplay extends StatefulWidget {
  const _RankedMmrDisplay({required this.theme});

  final AppThemeData theme;

  @override
  State<_RankedMmrDisplay> createState() => _RankedMmrDisplayState();
}

class _RankedMmrDisplayState extends State<_RankedMmrDisplay> {
  static const _defaultMmr = 1000;

  late final Future<int> _mmrFuture = _fetchMmr();

  Future<int> _fetchMmr() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _defaultMmr;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('ranked_stats')
          .doc(uid)
          .get();
      if (!doc.exists) return _defaultMmr;
      final d = doc.data() ?? <String, dynamic>{};
      final v = d['rating'];
      return v is num ? v.toInt() : _defaultMmr;
    } catch (_) {
      return _defaultMmr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _mmrFuture,
      builder: (context, snap) {
        final mmr = snap.data ?? _defaultMmr;
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '$mmr MMR',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: widget.theme.accentPrimary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        );
      },
    );
  }
}
