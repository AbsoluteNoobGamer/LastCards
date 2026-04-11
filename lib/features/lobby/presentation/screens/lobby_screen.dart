import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_page_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/models/game_event.dart';
import '../../../../core/models/game_state.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/providers/game_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../gameplay/presentation/screens/table_screen.dart';

enum OnlineMode { standard, tournament }

/// Matches server [GameSession.hostPlayerIdForPrivateLobby] (lowest `player-N`).
String? _hostPlayerIdForRoster(List<PlayerModel> players) {
  if (players.isEmpty) return null;
  var bestId = players.first.id;
  var bestN = _playerNumber(bestId);
  for (final p in players.skip(1)) {
    final n = _playerNumber(p.id);
    if (n < bestN) {
      bestN = n;
      bestId = p.id;
    }
  }
  return bestId;
}

int _playerNumber(String playerId) {
  final m = RegExp(r'^player-(\d+)$').firstMatch(playerId);
  return m != null ? int.parse(m.group(1)!) : 1 << 30;
}

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

  /// Cached for dispose — cannot use [ref] after the widget is disposed.
  WebSocketClient? _wsClientToDisconnectOnDispose;

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
        _enterSelectedMode(totalPlayers: e.gameState.players.length);
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
        setState(() {
          _localPlayerId = e.playerId;
          _roomCode = e.roomCode;
          _codeController.text = e.roomCode;
        });
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
    // Leaving the lobby must drop the socket so the server removes this client
    // from the room; otherwise re-entry stacks duplicate "players".
    _wsClientToDisconnectOnDispose?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _wsClientToDisconnectOnDispose = ref.read(wsClientProvider);

    final theme = ref.watch(themeProvider).theme;

    final sectionTitleStyle = GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 2.2,
      color: theme.textSecondary,
    );

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.xl,
                    vertical: AppDimensions.lg,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo / title
                      Text(
                        'LAST CARDS',
                        textAlign: TextAlign.center,
                        style: gameTitleTextStyle(
                          theme,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                          color: theme.accentPrimary,
                          shadows: [
                            Shadow(
                              color: theme.surfaceDark.withValues(alpha: 0.85),
                              offset: const Offset(0, 2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Text(
                        'Premium Competitive Card Game',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.35,
                          color: theme.textSecondary,
                        ),
                      ),

                      const SizedBox(height: AppDimensions.xxl),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('JOIN OR CREATE', style: sectionTitleStyle),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      _LobbySectionCard(
                        theme: theme,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _GoldTextField(
                              theme: theme,
                              controller: _codeController,
                              label: 'Room Code',
                              hintText: 'e.g. XKCD-42',
                              textCapitalization: TextCapitalization.characters,
                            ),
                            const SizedBox(height: AppDimensions.lg),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _onJoin,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: theme.accentPrimary,
                                      side: BorderSide(
                                        color: theme.accentPrimary
                                            .withValues(alpha: 0.85),
                                      ),
                                      minimumSize: const Size(
                                        0,
                                        AppDimensions.minTouchTarget,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppDimensions.radiusModal,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'JOIN ROOM',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppDimensions.md),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _onCreate,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.accentPrimary,
                                      foregroundColor: theme.backgroundDeep,
                                      elevation: 0,
                                      minimumSize: const Size(
                                        0,
                                        AppDimensions.minTouchTarget,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppDimensions.radiusModal,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'CREATE ROOM',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppDimensions.xl),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('LOBBY', style: sectionTitleStyle),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Text(
                        'Private games support 2–7 players. Everyone can tap '
                        'Ready to start when all are ready, or the host can tap '
                        'Start with at least two players in the room.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w400,
                          color: theme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),
                      _LobbySectionCard(
                        theme: theme,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_roomCode != null) ...[
                              _RoomCodeCard(
                                roomCode: _roomCode!,
                                theme: theme,
                              ),
                              const SizedBox(height: AppDimensions.md),
                              OutlinedButton.icon(
                                onPressed: _onInviteFriends,
                                icon: Icon(
                                  Icons.share_rounded,
                                  color: theme.accentPrimary,
                                  size: 20,
                                ),
                                label: Text(
                                  'INVITE',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.accentPrimary,
                                  side: BorderSide(
                                    color: theme.accentPrimary
                                        .withValues(alpha: 0.85),
                                  ),
                                  minimumSize: const Size(
                                    0,
                                    AppDimensions.minTouchTarget,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusModal,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppDimensions.lg),
                            ],
                            _LobbyPlayerList(
                              localPlayerId: _localPlayerId,
                              localIsReady: _isReady,
                              playerReady: _playerReady,
                              theme: theme,
                              players: _lobbyPlayers,
                              pendingJoin: _pendingJoin,
                              hostPlayerId: _hostPlayerIdForRoster(_lobbyPlayers),
                            ),
                            const SizedBox(height: AppDimensions.lg),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _toggleReady,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isReady
                                          ? theme.secondaryAccent
                                          : theme.accentPrimary,
                                      foregroundColor: _isReady
                                          ? theme.textPrimary
                                          : theme.backgroundDeep,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppDimensions.md,
                                      ),
                                      minimumSize: const Size(
                                        0,
                                        AppDimensions.minTouchTarget + 2,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppDimensions.radiusModal,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      _isReady ? 'NOT READY' : 'READY',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                if (_roomCode != null &&
                                    _localPlayerId != null &&
                                    _hostPlayerIdForRoster(_lobbyPlayers) ==
                                        _localPlayerId) ...[
                                  const SizedBox(width: AppDimensions.md),
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: _onHostStartGame,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: theme.secondaryAccent,
                                        foregroundColor: theme.textPrimary,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: AppDimensions.md,
                                        ),
                                        minimumSize: const Size(
                                          0,
                                          AppDimensions.minTouchTarget + 2,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppDimensions.radiusModal,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        'START',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Above scroll content so it stays tappable
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: theme.accentPrimary,
                  size: 26,
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
    if (!wsClient.send(jsonEncode({
      'type': 'join_room',
      'roomCode': code,
      'displayName': ref.read(displayNameForGameProvider),
      if (idToken != null) 'idToken': idToken,
    }))) {
      setState(() => _pendingJoin = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection lost. Reconnecting — try again.'),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
      return;
    }
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
    if (!wsClient.send(jsonEncode({
      'type': 'create_room',
      'displayName': ref.read(displayNameForGameProvider),
      if (idToken != null) 'idToken': idToken,
    }))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection lost. Reconnecting — try again.'),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
      return;
    }
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
      if (!wsClient.send(jsonEncode({'type': 'ready'}))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Connection lost. Reconnecting — try again.'),
              backgroundColor: Color(0xFFB71C1C),
            ),
          );
        }
      }
    }
  }

  Future<void> _onInviteFriends() async {
    final code = _roomCode;
    if (code == null) return;
    final text = 'Join me in Last Cards (private game). Room code: $code\n'
        'We need 2–7 players — open the app and use Join Room with this code.';
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Last Cards — room $code',
      ),
    );
  }

  void _onHostStartGame() {
    if (_lobbyPlayers.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'At least two players must be in the room before you can start.',
          ),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
      return;
    }
    final wsClient = ref.read(wsClientProvider);
    if (!wsClient.send(jsonEncode({'type': 'start_game'}))) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection lost. Reconnecting — try again.'),
            backgroundColor: Color(0xFFB71C1C),
          ),
        );
      }
    }
  }

  Future<void> _enterSelectedMode({required int totalPlayers}) async {
    if (!mounted) return;
    Navigator.of(context).push(
      AppPageRoutes.fadeSlide(
        (_) => TableScreen(
          totalPlayers: totalPlayers,
          isTournamentMode: widget.onlineMode == OnlineMode.tournament,
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Felt panel with border and shadow — lobby-only chrome.
class _LobbySectionCard extends StatelessWidget {
  const _LobbySectionCard({
    required this.theme,
    required this.child,
  });

  final AppThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.lg),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.surfaceDark.withValues(alpha: 0.72),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

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
              borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
              borderSide: BorderSide(color: theme.accentDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
              borderSide: BorderSide(color: theme.accentPrimary, width: 1.5),
            ),
          ),
        ),
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
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.75),
        ),
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
    required this.hostPlayerId,
  });

  static const int _maxSlots = 7;

  final String? localPlayerId;
  final bool localIsReady;
  final Map<String, bool> playerReady;
  final AppThemeData theme;
  final List<PlayerModel> players;
  final bool pendingJoin;
  final String? hostPlayerId;

  @override
  Widget build(BuildContext context) {
    final sorted = List<PlayerModel>.from(players)
      ..sort((a, b) => _playerNumber(a.id).compareTo(_playerNumber(b.id)));

    final entries = <_PlayerEntry>[];
    for (var i = 0; i < _maxSlots; i++) {
      if (i < sorted.length) {
        final p = sorted[i];
        final isMe = p.id == localPlayerId;
        final ready =
            isMe ? localIsReady : (playerReady[p.id] ?? false);
        entries.add(
          _PlayerEntry(
            name: p.displayName,
            isReady: ready,
            theme: theme,
            isVacantSeat: false,
            isHost: hostPlayerId != null && p.id == hostPlayerId,
          ),
        );
      } else {
        entries.add(
          _PlayerEntry(
            name: 'Open seat',
            isReady: false,
            theme: theme,
            isVacantSeat: true,
            isHost: false,
          ),
        );
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.sm,
        vertical: AppDimensions.xs,
      ),
      decoration: BoxDecoration(
        color: Color.lerp(theme.surfacePanel, theme.backgroundDeep, 0.38)!,
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        border: Border.all(
          color: theme.accentDark.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          if (pendingJoin)
            Padding(
              padding: const EdgeInsets.only(
                top: AppDimensions.sm,
                bottom: AppDimensions.sm,
              ),
              child: Text(
                'Joining room...',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: theme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          for (int i = 0; i < entries.length; i++) ...[
            entries[i],
            if (i < entries.length - 1)
              Divider(
                height: 1,
                color: theme.accentDark.withValues(alpha: 0.45),
                thickness: 0.5,
              ),
          ],
        ],
      ),
    );
  }
}

// ── Felt table background ─────────────────────────────────────────────────────

class _FeltBackground extends StatelessWidget {
  const _FeltBackground({required this.theme});

  final AppThemeData theme;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _LobbyFeltPainter(theme: theme));
  }
}

/// Full-screen lobby backdrop driven by [AppThemeData] — gradients and texture
/// use each preset's surfaces and accents (not only the default green felt).
class _LobbyFeltPainter extends CustomPainter {
  const _LobbyFeltPainter({required this.theme});

  final AppThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Base diagonal depth: backgroundDeep → surfacePanel → dark/mid blend
    final baseGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        theme.backgroundDeep,
        Color.lerp(theme.backgroundDeep, theme.surfacePanel, 0.42)!,
        Color.lerp(theme.surfaceDark, theme.backgroundMid, 0.38)!,
      ],
      stops: const [0.0, 0.52, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = baseGradient.createShader(rect));

    // Soft upper accent bloom (gold / silver / sapphire per theme)
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.52),
          radius: 1.08,
          colors: [
            theme.accentPrimary.withValues(alpha: 0.088),
            Colors.transparent,
          ],
          stops: const [0.0, 0.58],
        ).createShader(rect),
    );

    // Vertical wash using theme mid-tone
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.backgroundMid.withValues(alpha: 0.15),
            Colors.transparent,
          ],
          stops: const [0.0, 0.48],
        ).createShader(rect),
    );

    // Dot texture: blend accentDark with felt mid so hue tracks the preset
    final dotBase = Color.lerp(theme.accentDark, theme.backgroundMid, 0.52)!;
    final dotPaint = Paint()
      ..color = dotBase.withValues(alpha: 0.088)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < size.width; x += 4) {
      for (double y = 0; y < size.height; y += 4) {
        if (((x ~/ 4) + (y ~/ 4)) % 3 == 0) {
          canvas.drawCircle(Offset(x, y), 0.7, dotPaint);
        }
      }
    }

    // Vignette: darken toward theme-hued edge (avoids flat neutral black)
    final vignetteEdge =
        Color.lerp(theme.backgroundDeep, Colors.black, 0.44)!;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 1.0,
          colors: [
            Colors.transparent,
            vignetteEdge.withValues(alpha: 0.58),
          ],
          stops: const [0.38, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _LobbyFeltPainter old) => old.theme.id != theme.id;
}

class _PlayerEntry extends StatelessWidget {
  const _PlayerEntry({
    required this.name,
    required this.isReady,
    required this.theme,
    this.isVacantSeat = false,
    this.isHost = false,
  });

  final String name;
  final bool isReady;
  final bool isVacantSeat;
  final bool isHost;
  final AppThemeData theme;

  /// Ready/readability green, lightly mixed with the theme accent highlight.
  Color get _readyTint => Color.lerp(
        const Color(0xFF27AE60),
        theme.accentLight,
        0.14,
      )!;

  @override
  Widget build(BuildContext context) {
    final dotColor = isVacantSeat
        ? theme.accentDark
        : isReady
            ? _readyTint
            : theme.accentPrimary;

    final nameStyle = GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.3,
      color: isVacantSeat ? theme.textSecondary : theme.textPrimary,
    );

    final statusStyle = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.2,
      color: isReady ? _readyTint : theme.suitRed,
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
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: nameStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isHost && !isVacantSeat) ...[
                  const SizedBox(width: 8),
                  Text(
                    'HOST',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: theme.accentLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isVacantSeat)
            Text(
              isReady ? 'READY' : 'NOT READY',
              style: statusStyle,
            ),
        ],
      ),
    );
  }
}
