import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/models/game_event.dart';
import '../../../../core/models/game_state.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/providers/game_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../gameplay/presentation/screens/table_screen.dart';
import '../../../../screens/tournament_screen.dart';

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
  final _nameController = TextEditingController();
  bool _isReady = false;
  String? _roomCode;
  bool _pendingJoin = false;
  final List<PlayerModel> _lobbyPlayers = [];
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
      setState(() => _roomCode = e.roomCode);
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
      if (e is PlayerLeftEvent) {
        setState(() => _lobbyPlayers.removeWhere((p) => p.id == e.playerId));
      }
    });
  }

  @override
  void dispose() {
    _roomCreatedSub?.cancel();
    _stateSnapshotSub?.cancel();
    _lobbyEventsSub?.cancel();
    _codeController.dispose();
    _nameController.dispose();
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
                        'STACK & FLOW',
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

                      // Player name
                      _GoldTextField(
                        theme: theme,
                        controller: _nameController,
                        label: 'Your Name',
                        hintText: 'Enter display name',
                      ),

                      const SizedBox(height: AppDimensions.md),

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
                        isReady: _isReady,
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

  void _onJoin() {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a room code first')),
      );
      return;
    }
    setState(() => _pendingJoin = true);
    final wsClient = ref.read(wsClientProvider);
    wsClient.connect();
    Future.delayed(const Duration(milliseconds: 500), () {
      wsClient.send(jsonEncode({
        'type': 'join_room',
        'roomCode': code,
        'displayName': _nameController.text.trim(),
      }));
    });
    // If no response after 8s, show hint (wrong server IP or room code).
    Future.delayed(const Duration(seconds: 8), () {
      if (!mounted || !_pendingJoin) return;
      setState(() => _pendingJoin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not join. Check the room code and that this device is using the host\'s IP (e.g. run with WS_URL=ws://HOST_IP:8080/game).',
          ),
          duration: Duration(seconds: 5),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
    });
  }

  void _onCreate() {
    final wsClient = ref.read(wsClientProvider);
    wsClient.connect();
    Future.delayed(const Duration(milliseconds: 500), () {
      wsClient.send(jsonEncode({
        'type': 'create_room',
        'displayName': _nameController.text.trim(),
      }));
    });
    // Navigation happens when room_created is received (see initState listener).
  }

  void _toggleReady() {
    setState(() => _isReady = !_isReady);
    final wsClient = ref.read(wsClientProvider);
    wsClient.send(jsonEncode({'type': 'ready'}));
  }

  void _enterSelectedMode() {
    final displayName = _nameController.text.trim();
    final effectiveName = displayName.isEmpty ? 'You' : displayName;

    if (widget.onlineMode == OnlineMode.tournament) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TournamentScreen(
            isOnline: true,
            onlineLocalDisplayName: effectiveName,
          ),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TableScreen(totalPlayers: 4),
      ),
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
    required this.isReady,
    required this.theme,
    required this.players,
    required this.pendingJoin,
  });

  final bool isReady;
  final AppThemeData theme;
  final List<PlayerModel> players;
  final bool pendingJoin;

  @override
  Widget build(BuildContext context) {
    final hasPlayers = players.isNotEmpty;
    final list = hasPlayers
        ? players
            .map((p) => _PlayerEntry(
                  name: p.displayName,
                  isReady: false,
                  theme: theme,
                  isPlaceholder: false,
                ))
            .toList()
        : [
            _PlayerEntry(name: 'You', isReady: isReady, theme: theme),
            _PlayerEntry(
                name: 'Waiting...', isReady: false, isPlaceholder: true, theme: theme),
            _PlayerEntry(
                name: 'Waiting...', isReady: false, isPlaceholder: true, theme: theme),
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
