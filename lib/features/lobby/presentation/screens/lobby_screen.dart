import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_page_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/game_event.dart';
import '../../../../core/models/game_state.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/providers/game_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../gameplay/presentation/screens/table_screen.dart';

enum OnlineMode { standard, tournament }

/// Room entry screen — players enter a room code, see the player list,
/// and mark themselves ready before the host starts the game.
class LobbyScreen extends ConsumerStatefulWidget {
  const LobbyScreen({
    this.onlineMode = OnlineMode.standard,
    super.key,
  });

  final OnlineMode onlineMode;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _codeController = TextEditingController();
  bool _isReady = false;
  String? _roomCode;
  String? _localPlayerId;
  bool _pendingJoin = false;
  final List<PlayerModel> _lobbyPlayers = [];
  final Map<String, bool> _playerReady = {};
  StreamSubscription<RoomCreatedEvent>? _roomCreatedSub;
  StreamSubscription<StateSnapshotEvent>? _stateSnapshotSub;
  StreamSubscription<GameEvent>? _lobbyEventsSub;

  @override
  void initState() {
    super.initState();
    // Ensure GameNotifier exists and is subscribed before any state_snapshot arrives,
    // so when we navigate to the table the provider already has the server state.
    ref.read(gameNotifierProvider);
    final handler = ref.read(gameEventHandlerProvider);
    _roomCreatedSub = handler.roomCreated.listen((e) {
      if (!mounted) return;
      setState(() {
        _roomCode = e.roomCode;
        if (e.playerId.isNotEmpty) _localPlayerId = e.playerId;
      });
      _codeController.text = e.roomCode;
    });
    _stateSnapshotSub = handler.stateSnapshots.listen((e) {
      if (!mounted) return;
      if (e.gameState.phase == GamePhase.playing) {
        _stateSnapshotSub?.cancel();
        _stateSnapshotSub = null;
        _enterSelectedMode();
      }
    });
    _lobbyEventsSub = handler.events.listen((e) {
      if (!mounted) return;
      if (e is ErrorEvent) {
        setState(() => _pendingJoin = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade800,
          ),
        );
        return;
      }
      if (e is PlayerJoinedEvent) {
        setState(() {
          _lobbyPlayers.removeWhere((p) => p.id == e.player.id);
          _lobbyPlayers.add(e.player);
          if (_pendingJoin) {
            _pendingJoin = false;
            _localPlayerId ??= e.player.id;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Joined room! Tap READY when ready.'),
                backgroundColor: Color(0xFF2E7D32),
              ),
            );
          }
        });
        return;
      }
      if (e is RoomJoinedEvent) {
        setState(() => _localPlayerId = e.playerId);
        return;
      }
      if (e is PlayerReadyEvent) {
        setState(() => _playerReady[e.playerId] = true);
        return;
      }
      if (e is PlayerLeftEvent) {
        setState(() {
          _lobbyPlayers.removeWhere((p) => p.id == e.playerId);
          _playerReady.remove(e.playerId);
        });
      }
    });
  }

  @override
  void dispose() {
    _roomCreatedSub?.cancel();
    _stateSnapshotSub?.cancel();
    _lobbyEventsSub?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;

    return Scaffold(
      backgroundColor: theme.backgroundDeep,
      body: Stack(
        children: [
          // Theme-aware felt vignette background
          Positioned.fill(child: _FeltBackground(theme: theme)),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo / title
                      Text(
                        'LAST CARDS',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: theme.accentPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.xs),
                      Text(
                        'Premium Competitive Card Game',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.2,
                          color: theme.textSecondary,
                        ),
                      ),

                      const SizedBox(height: AppDimensions.xxl),

                      // Room code
                      _GoldTextField(
                        theme: theme,
                        controller: _codeController,
                        label: 'Room Code',
                        hintText: 'e.g. XKCD-42',
                        textCapitalization: TextCapitalization.characters,
                      ),

                      const SizedBox(height: AppDimensions.lg),

                      // Join / Create
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _onJoin,
                              child: const Text('JOIN ROOM'),
                            ),
                          ),
                          const SizedBox(width: AppDimensions.md),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _onCreate,
                              child: const Text('CREATE ROOM'),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppDimensions.xxl),
                      _Divider(theme: theme),
                      const SizedBox(height: AppDimensions.lg),

                      // Room code display (after create)
                      if (_roomCode != null) ...[
                        _RoomCodeCard(
                          roomCode: _roomCode!,
                          theme: theme,
                        ),
                        const SizedBox(height: AppDimensions.lg),
                      ],

                      // Lobby player list (real from server or placeholder)
                      _LobbyPlayerList(
                        localPlayerId: _localPlayerId,
                        localIsReady: _isReady,
                        playerReady: _playerReady,
                        theme: theme,
                        players: _lobbyPlayers,
                        pendingJoin: _pendingJoin,
                      ),

                      const SizedBox(height: AppDimensions.lg),

                      // Ready toggle
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _toggleReady,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isReady
                                ? theme.secondaryAccent
                                : theme.accentPrimary,
                          ),
                          child: Text(_isReady ? 'NOT READY' : 'READY'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onJoin() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a room code first')),
      );
      return;
    }
    setState(() => _pendingJoin = true);
    final wsClient = ref.read(wsClientProvider);
    final authService = ref.read(authServiceProvider);
    final idToken = await authService.getIdToken();
    try {
      await wsClient.connect();
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingJoin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection failed: $e'),
          backgroundColor: const Color(0xFFB71C1C),
        ),
      );
      return;
    }
    if (!mounted) return;
    wsClient.send(jsonEncode({
      'type': 'join_room',
      'roomCode': code,
      'displayName': ref.read(displayNameForGameProvider),
      if (idToken != null) 'idToken': idToken,
    }));
    // If no response after 8s, show hint (wrong server IP or room code).
    Future.delayed(const Duration(seconds: 8), () {
      if (!mounted || !_pendingJoin) return;
      setState(() => _pendingJoin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not join. Check the room code and try again.',
          ),
          duration: Duration(seconds: 5),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
    });
  }

  Future<void> _onCreate() async {
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
    wsClient.send(jsonEncode({
      'type': 'create_room',
      'displayName': ref.read(displayNameForGameProvider),
      if (idToken != null) 'idToken': idToken,
    }));
    // Navigation happens when room_created is received (see initState listener).
  }

  void _toggleReady() {
    final willBeReady = !_isReady;
    setState(() => _isReady = willBeReady);
    // Only send the 'ready' signal when toggling ON — the server has no
    // concept of un-readying, so sending on toggle-off would start the game
    // prematurely.
    if (willBeReady) {
      final wsClient = ref.read(wsClientProvider);
      wsClient.send(jsonEncode({'type': 'ready'}));
    }
  }

  Future<void> _enterSelectedMode() async {
    if (widget.onlineMode == OnlineMode.tournament) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Coming soon'),
          content: const Text('Online tournaments are coming soon!'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.of(context).push(
      AppPageRoutes.fadeSlide((_) => const TableScreen(totalPlayers: 4)),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _GoldTextField extends StatelessWidget {
  const _GoldTextField({
    required this.theme,
    required this.controller,
    required this.label,
    required this.hintText,
    this.textCapitalization = TextCapitalization.none,
  });

  final AppThemeData theme;
  final TextEditingController controller;
  final String label;
  final String hintText;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: theme.textSecondary,
    );
    final inputStyle = GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      color: theme.textPrimary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        const SizedBox(height: AppDimensions.xs),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          style: inputStyle,
          cursorColor: theme.accentPrimary,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: inputStyle.copyWith(
              color: theme.textSecondary.withValues(alpha: 0.5),
            ),
            filled: true,
            fillColor: theme.backgroundMid,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.md,
              vertical: AppDimensions.sm + 4,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
              borderSide: BorderSide(color: theme.accentDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
              borderSide: BorderSide(color: theme.accentPrimary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    final labelStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: theme.textSecondary,
    );

    return Row(
      children: [
        Expanded(child: Divider(color: theme.accentDark, thickness: 0.5)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.md),
          child: Text('LOBBY', style: labelStyle),
        ),
        Expanded(child: Divider(color: theme.accentDark, thickness: 0.5)),
      ],
    );
  }
}

class _RoomCodeCard extends StatelessWidget {
  const _RoomCodeCard({
    required this.roomCode,
    required this.theme,
  });

  final String roomCode;
  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.lg,
        vertical: AppDimensions.md,
      ),
      decoration: BoxDecoration(
        color: theme.backgroundMid,
        borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
        border: Border.all(color: theme.accentDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Room code',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.2,
              color: theme.textSecondary,
            ),
          ),
          const SizedBox(height: AppDimensions.xs),
          SelectableText(
            roomCode,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 4,
              color: theme.accentPrimary,
            ),
          ),
          const SizedBox(height: AppDimensions.xs),
          Text(
            'Share this code with others to join',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: theme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LobbyPlayerList extends StatelessWidget {
  const _LobbyPlayerList({
    required this.localPlayerId,
    required this.localIsReady,
    required this.playerReady,
    required this.theme,
    required this.players,
    required this.pendingJoin,
  });

  final String? localPlayerId;
  final bool localIsReady;
  final Map<String, bool> playerReady;
  final AppThemeData theme;
  final List<PlayerModel> players;
  final bool pendingJoin;

  @override
  Widget build(BuildContext context) {
    final hasPlayers = players.isNotEmpty;
    final list = hasPlayers
        ? players
            .map((p) {
              final isMe = p.id == localPlayerId;
              final ready = isMe
                  ? localIsReady
                  : (playerReady[p.id] ?? false);
              return _PlayerEntry(
                name: p.displayName,
                isReady: ready,
                theme: theme,
                isPlaceholder: false,
              );
            })
            .toList()
        : [
            _PlayerEntry(name: 'You', isReady: localIsReady, theme: theme),
            _PlayerEntry(
                name: 'Waiting...',
                isReady: false,
                isPlaceholder: true,
                theme: theme),
            _PlayerEntry(
                name: 'Waiting...',
                isReady: false,
                isPlaceholder: true,
                theme: theme),
          ];

    return Column(
      children: [
        if (pendingJoin)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDimensions.sm),
            child: Text(
              'Joining room...',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: theme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        for (int i = 0; i < list.length; i++) ...[
          list[i],
          if (i < list.length - 1)
            Divider(height: 1, color: theme.accentDark, thickness: 0.3),
        ],
      ],
    );
  }
}

// ── Felt table background ─────────────────────────────────────────────────────

class _FeltBackground extends StatelessWidget {
  const _FeltBackground({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LobbyFeltPainter(
        backgroundDeep: theme.backgroundDeep,
        backgroundMid: theme.backgroundMid,
      ),
    );
  }
}

class _LobbyFeltPainter extends CustomPainter {
  const _LobbyFeltPainter({
    required this.backgroundDeep,
    required this.backgroundMid,
  });

  final Color backgroundDeep;
  final Color backgroundMid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundDeep,
    );

    // Subtle dot-grid micro-texture
    final dotPaint = Paint()
      ..color = backgroundMid.withValues(alpha: 0.07)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += 4) {
      for (double y = 0; y < size.height; y += 4) {
        if (((x ~/ 4) + (y ~/ 4)) % 3 == 0) {
          canvas.drawCircle(Offset(x, y), 0.7, dotPaint);
        }
      }
    }

    // Vignette
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.5)],
          stops: const [0.4, 1.0],
        ).createShader(
          Rect.fromLTWH(0, 0, size.width, size.height),
        ),
    );
  }

  @override
  bool shouldRepaint(_LobbyFeltPainter old) =>
      old.backgroundDeep != backgroundDeep ||
      old.backgroundMid != backgroundMid;
}

class _PlayerEntry extends StatelessWidget {
  const _PlayerEntry({
    required this.name,
    required this.isReady,
    required this.theme,
    this.isPlaceholder = false,
  });

  final String name;
  final bool isReady;
  final bool isPlaceholder;
  final AppThemeData theme;

  // Semantic status green — not a brand colour, kept as constant.
  static const Color _readyGreen = Color(0xFF27AE60);

  @override
  Widget build(BuildContext context) {
    final dotColor = isPlaceholder
        ? theme.accentDark
        : isReady
            ? _readyGreen
            : theme.accentPrimary;

    final nameStyle = GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: isPlaceholder ? theme.textSecondary : theme.textPrimary,
    );

    final statusStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: isReady ? _readyGreen : theme.suitRed,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimensions.sm),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: AppDimensions.sm),
          Text(name, style: nameStyle),
          const Spacer(),
          if (!isPlaceholder)
            Text(
              isReady ? 'READY' : 'NOT READY',
              style: statusStyle,
            ),
        ],
      ),
    );
  }
}
