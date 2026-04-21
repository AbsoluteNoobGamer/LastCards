import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/navigation/app_page_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/models/game_event.dart'
    show
        ErrorEvent,
        GameEvent,
        PlayerJoinedEvent,
        PlayerLeftEvent,
        PlayerReadyEvent,
        PrivateLobbySettingsEvent,
        RoomCreatedEvent,
        RoomJoinedEvent,
        StateSnapshotEvent;
import '../../../../core/models/game_state.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/friends_provider.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/providers/game_provider.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/models/ai_player_config.dart';
import '../../../gameplay/presentation/screens/table_screen.dart';
import '../../../social/widgets/invite_friends_sheet.dart';
import '../../../social/widgets/pending_friend_requests_banner.dart';
import '../../../tournament/providers/tournament_session_provider.dart';

enum OnlineMode { standard, tournament }

/// Host-selected private table type (mirrors server `gameVariant`).
enum PrivateGameVariant {
  standard,
  knockout,
  bust;

  String get wireName => switch (this) {
        PrivateGameVariant.standard => 'standard',
        PrivateGameVariant.knockout => 'knockout',
        PrivateGameVariant.bust => 'bust',
      };

  static PrivateGameVariant parse(String? s) => switch (s) {
        'bust' => PrivateGameVariant.bust,
        'knockout' => PrivateGameVariant.knockout,
        _ => PrivateGameVariant.standard,
      };
}

/// Matches server [GameSession.hostPlayerIdForPrivateLobby] (lowest `player-N`
/// among humans only).
String? _hostPlayerIdForRoster(List<PlayerModel> players) {
  final humans = players.where((p) => !p.isAi).toList();
  if (humans.isEmpty) return null;
  var bestId = humans.first.id;
  var bestN = _playerNumber(bestId);
  for (final p in humans.skip(1)) {
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
    this.initialRoomCodeToJoin,
    this.pendingGameInviteDocIdToDismiss,
    super.key,
  });

  final OnlineMode onlineMode;

  /// When set (e.g. from a friend invite), fills the code and attempts [join_room].
  final String? initialRoomCodeToJoin;

  /// Remove this Firestore invite doc after a successful join (`users/me/gameInvites/id`).
  final String? pendingGameInviteDocIdToDismiss;

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  final _codeController = TextEditingController();
  bool _isReady = false;
  String? _roomCode;
  String? _localPlayerId;
  bool _pendingJoin = false;

  /// Casual (false) vs hardcore (30s turns, stricter rules). Synced from server
  /// when in a room; used as create_room payload when hosting.
  bool _privateLobbyHardcore = false;

  /// True after we received [RoomCreatedEvent] for this session (not join).
  bool _isRoomCreator = false;

  /// Standard last-cards, knockout finish order, or bust elimination.
  PrivateGameVariant _privateGameVariant = PrivateGameVariant.standard;

  AiDifficulty _aiDifficulty = AiDifficulty.medium;
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
        _privateLobbyHardcore = e.isHardcore;
        _privateGameVariant = PrivateGameVariant.parse(e.gameVariant);
        _isRoomCreator = true;
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
    final joinCode = widget.initialRoomCodeToJoin?.trim();
    if (joinCode != null && joinCode.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _codeController.text = joinCode.toUpperCase();
        unawaited(_onJoin());
      });
    }

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
          if (e.player.isAi) {
            _playerReady[e.player.id] = true;
          }
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
      if (e is PrivateLobbySettingsEvent) {
        setState(() => _privateLobbyHardcore = e.isHardcore);
        return;
      }
      if (e is RoomJoinedEvent) {
        setState(() {
          _localPlayerId = e.playerId;
          _roomCode = e.roomCode;
          _codeController.text = e.roomCode;
          _privateLobbyHardcore = e.isHardcore;
          _privateGameVariant = PrivateGameVariant.parse(e.gameVariant);
          _isRoomCreator = false;
        });
        final pending = widget.pendingGameInviteDocIdToDismiss;
        if (pending != null) {
          unawaited(
            ref.read(friendsServiceProvider).deleteGameInvite(pending),
          );
        }
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PendingFriendRequestsBanner(),
                Expanded(
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
                            Text(
                              'LAST CARDS',
                              textAlign: TextAlign.center,
                              style: gameTitleTextStyle(
                                theme,
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: theme.accentPrimary,
                                shadows: [
                                  Shadow(
                                    color: theme.surfaceDark
                                        .withValues(alpha: 0.85),
                                    offset: const Offset(0, 2),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppDimensions.md),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppDimensions.md,
                                vertical: AppDimensions.xs + 2,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: theme.accentPrimary
                                      .withValues(alpha: 0.35),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    theme.accentPrimary.withValues(alpha: 0.14),
                                    theme.surfaceDark.withValues(alpha: 0.2),
                                  ],
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.lock_rounded,
                                    size: 18,
                                    color: theme.accentLight,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'PRIVATE TABLE',
                                    style: GoogleFonts.cinzel(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.4,
                                      color: theme.accentLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppDimensions.sm),
                            Text(
                              'Invite friends, pick the rules, deal the cards',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                height: 1.4,
                                letterSpacing: 0.2,
                                color: theme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppDimensions.xxl),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('JOIN OR CREATE',
                                  style: sectionTitleStyle),
                            ),
                            const SizedBox(height: AppDimensions.sm),
                            _LobbySectionCard(
                              theme: theme,
                              accentBorder: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _GoldTextField(
                                    theme: theme,
                                    controller: _codeController,
                                    label: 'Room Code',
                                    hintText: 'e.g. XKCD-42',
                                    textCapitalization:
                                        TextCapitalization.characters,
                                  ),
                                  if (_roomCode == null) ...[
                                    const SizedBox(height: AppDimensions.lg),
                                    _PrivateGameVariantPicker(
                                      theme: theme,
                                      sectionTitleStyle: sectionTitleStyle,
                                      variant: _privateGameVariant,
                                      enabled: true,
                                      subtitle:
                                          'Pick before you create — everyone plays this format.',
                                      onSelectVariant: _selectGameVariant,
                                    ),
                                    const SizedBox(height: AppDimensions.lg),
                                    _PrivateLobbyRulesPicker(
                                      theme: theme,
                                      sectionTitleStyle: sectionTitleStyle,
                                      isHardcore: _privateLobbyHardcore,
                                      enabled: true,
                                      subtitle:
                                          'Applies when you create a room — you are the host.',
                                      onSelectHardcore:
                                          _selectPrivateLobbyHardcore,
                                    ),
                                  ],
                                  const SizedBox(height: AppDimensions.lg),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _onJoin,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                theme.accentPrimary,
                                            side: BorderSide(
                                              color: theme.accentPrimary
                                                  .withValues(alpha: 0.85),
                                            ),
                                            minimumSize: const Size(
                                              0,
                                              AppDimensions.minTouchTarget,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
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
                                            backgroundColor:
                                                theme.accentPrimary,
                                            foregroundColor:
                                                theme.backgroundDeep,
                                            elevation: 0,
                                            minimumSize: const Size(
                                              0,
                                              AppDimensions.minTouchTarget,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
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
                              child: Text('PLAYERS', style: sectionTitleStyle),
                            ),
                            const SizedBox(height: AppDimensions.sm),
                            Text(
                              _privateGameVariant == PrivateGameVariant.bust
                                  ? '2–10 players in Bust. Ready up when you are set, '
                                      'or the host can start with two or more at the table.'
                                  : '2–7 players. Ready up when you are set, or the host '
                                      'can start with two or more at the table.',
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
                              accentBorder: _roomCode != null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_roomCode != null) ...[
                                    _RoomCodeCard(
                                      roomCode: _roomCode!,
                                      theme: theme,
                                    ),
                                    const SizedBox(height: AppDimensions.lg),
                                    _PrivateGameVariantPicker(
                                      theme: theme,
                                      sectionTitleStyle: sectionTitleStyle,
                                      variant: _privateGameVariant,
                                      enabled: false,
                                      subtitle:
                                          'Set when the room was created — everyone plays this format.',
                                      onSelectVariant: null,
                                    ),
                                    const SizedBox(height: AppDimensions.lg),
                                    _PrivateLobbyRulesPicker(
                                      theme: theme,
                                      sectionTitleStyle: sectionTitleStyle,
                                      isHardcore: _privateLobbyHardcore,
                                      enabled: _isPrivateHost,
                                      subtitle: _isPrivateHost
                                          ? 'Your guests see this before you start.'
                                          : 'The host sets table rules for this room.',
                                      onSelectHardcore: _isPrivateHost
                                          ? _selectPrivateLobbyHardcore
                                          : null,
                                    ),
                                    const SizedBox(height: AppDimensions.md),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _onInviteFriends,
                                            icon: Icon(
                                              Icons.share_rounded,
                                              color: theme.accentPrimary,
                                              size: 20,
                                            ),
                                            label: Text(
                                              'SHARE CODE',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  theme.accentPrimary,
                                              side: BorderSide(
                                                color: theme.accentPrimary
                                                    .withValues(alpha: 0.85),
                                              ),
                                              minimumSize: const Size(
                                                0,
                                                AppDimensions.minTouchTarget,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  AppDimensions.radiusModal,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: AppDimensions.md),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _onInviteFriendsInApp,
                                            icon: Icon(
                                              Icons.group_add_rounded,
                                              color: theme.accentPrimary,
                                              size: 20,
                                            ),
                                            label: Text(
                                              'FRIENDS',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor:
                                                  theme.accentPrimary,
                                              side: BorderSide(
                                                color: theme.accentPrimary
                                                    .withValues(alpha: 0.85),
                                              ),
                                              minimumSize: const Size(
                                                0,
                                                AppDimensions.minTouchTarget,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  AppDimensions.radiusModal,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppDimensions.lg),
                                  ],
                                  if (_roomCode != null && _isPrivateHost) ...[
                                    _PrivateLobbyAiPanel(
                                      theme: theme,
                                      sectionTitleStyle: sectionTitleStyle,
                                      aiDifficulty: _aiDifficulty,
                                      onAiDifficultyChanged: (d) =>
                                          setState(() => _aiDifficulty = d),
                                      maxTablePlayers: _privateGameVariant ==
                                              PrivateGameVariant.bust
                                          ? 10
                                          : 7,
                                      currentPlayers: _lobbyPlayers.length,
                                      onAddBot: _onAddPrivateLobbyBot,
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
                                    hostPlayerId:
                                        _hostPlayerIdForRoster(_lobbyPlayers),
                                    maxSlots: _privateGameVariant ==
                                            PrivateGameVariant.bust
                                        ? 10
                                        : 7,
                                    isPrivateHost: _isPrivateHost,
                                    onRemoveBot: _onRemovePrivateLobbyBot,
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
                                              borderRadius:
                                                  BorderRadius.circular(
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
                                          _hostPlayerIdForRoster(
                                                  _lobbyPlayers) ==
                                              _localPlayerId) ...[
                                        const SizedBox(width: AppDimensions.md),
                                        Expanded(
                                          child: ElevatedButton(
                                            onPressed: _onHostStartGame,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  theme.secondaryAccent,
                                              foregroundColor:
                                                  theme.textPrimary,
                                              elevation: 0,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: AppDimensions.md,
                                              ),
                                              minimumSize: const Size(
                                                0,
                                                AppDimensions.minTouchTarget +
                                                    2,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
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
              ],
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
      'isHardcore': _privateLobbyHardcore,
      'gameVariant': _privateGameVariant.wireName,
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
    final maxP = _privateGameVariant == PrivateGameVariant.bust ? 10 : 7;
    final text = 'Join me in Last Cards (private game). Room code: $code\n'
        'We need 2–$maxP players — open the app and use Join Room with this code.';
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Last Cards — room $code',
      ),
    );
  }

  Future<void> _onInviteFriendsInApp() async {
    final code = _roomCode;
    if (code == null) return;
    final theme = ref.read(themeProvider).theme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.backgroundDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => InviteFriendsSheet(
        roomCode: code,
        onInvited: () {},
      ),
    );
  }

  Future<void> _onAddPrivateLobbyBot() async {
    final wsClient = ref.read(wsClientProvider);
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
      'type': 'add_private_lobby_bot',
      'aiDifficulty': _aiDifficulty.name,
    }))) {
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

  Future<void> _onRemovePrivateLobbyBot(String botPlayerId) async {
    final wsClient = ref.read(wsClientProvider);
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
      'type': 'remove_private_lobby_bot',
      'playerId': botPlayerId,
    }))) {
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

  Future<void> _onHostStartGame() async {
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

  bool get _isPrivateHost {
    if (_roomCode == null || _localPlayerId == null) return false;
    final hostId = _hostPlayerIdForRoster(_lobbyPlayers);
    if (hostId != null) return hostId == _localPlayerId;
    // Roster not synced yet — only the creator is host.
    return _isRoomCreator;
  }

  void _selectGameVariant(PrivateGameVariant v) {
    setState(() => _privateGameVariant = v);
  }

  void _selectPrivateLobbyHardcore(bool hardcore) {
    setState(() => _privateLobbyHardcore = hardcore);
    if (_roomCode == null || !_isPrivateHost) return;
    final wsClient = ref.read(wsClientProvider);
    if (!wsClient.send(jsonEncode({
      'type': 'set_private_lobby_rules',
      'isHardcore': hardcore,
    }))) {
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

  void _syncTournamentSessionForPrivateTable() {
    final n = ref.read(tournamentSessionProvider.notifier);
    n.reset();
    switch (_privateGameVariant) {
      case PrivateGameVariant.standard:
        break;
      case PrivateGameVariant.knockout:
        n.setFormat(TournamentFormat.knockout);
        n.setSubMode(GameSubMode.knockout);
        break;
      case PrivateGameVariant.bust:
        n.setSubMode(GameSubMode.bust);
        break;
    }
  }

  Future<void> _enterSelectedMode({required int totalPlayers}) async {
    if (!mounted) return;
    _syncTournamentSessionForPrivateTable();
    final isKnockout = _privateGameVariant == PrivateGameVariant.knockout;
    Navigator.of(context).push(
      AppPageRoutes.fadeSlide(
        (_) => TableScreen(
          totalPlayers: totalPlayers,
          isTournamentMode:
              isKnockout || widget.onlineMode == OnlineMode.tournament,
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

/// Host: add server-controlled bots that play at the same online table as guests.
class _PrivateLobbyAiPanel extends StatelessWidget {
  const _PrivateLobbyAiPanel({
    required this.theme,
    required this.sectionTitleStyle,
    required this.aiDifficulty,
    required this.onAiDifficultyChanged,
    required this.maxTablePlayers,
    required this.currentPlayers,
    required this.onAddBot,
  });

  final AppThemeData theme;
  final TextStyle sectionTitleStyle;
  final AiDifficulty aiDifficulty;
  final ValueChanged<AiDifficulty> onAiDifficultyChanged;
  final int maxTablePlayers;
  final int currentPlayers;
  final Future<void> Function() onAddBot;

  @override
  Widget build(BuildContext context) {
    final canAdd = currentPlayers < maxTablePlayers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI OPPONENTS', style: sectionTitleStyle),
        const SizedBox(height: AppDimensions.xs),
        Text(
          'Each bot takes the next open seat in the list (after online players). '
          'They play on this server with everyone — same match, same rules, '
          'including Bust.',
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w400,
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimensions.md),
        Text(
          'Difficulty for new bots',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimensions.xs),
        Wrap(
          spacing: AppDimensions.sm,
          runSpacing: AppDimensions.xs,
          children: AiDifficulty.values.map((d) {
            final sel = aiDifficulty == d;
            return ChoiceChip(
              label: Text(d.displayName),
              selected: sel,
              onSelected: (_) => onAiDifficultyChanged(d),
              selectedColor: theme.accentPrimary.withValues(alpha: 0.22),
              labelStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? theme.accentLight : theme.textSecondary,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppDimensions.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: canAdd ? () => unawaited(onAddBot()) : null,
            icon: Icon(Icons.smart_toy_rounded, color: theme.accentPrimary),
            label: Text(
              canAdd ? 'ADD BOT' : 'TABLE FULL',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.accentPrimary,
              side: BorderSide(
                color: theme.accentPrimary.withValues(alpha: 0.85),
              ),
              minimumSize: const Size(0, AppDimensions.minTouchTarget),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Felt panel with border and shadow — lobby-only chrome.
class _LobbySectionCard extends StatelessWidget {
  const _LobbySectionCard({
    required this.theme,
    required this.child,
    this.accentBorder = false,
  });

  final AppThemeData theme;
  final Widget child;
  final bool accentBorder;

  @override
  Widget build(BuildContext context) {
    final borderColor = accentBorder
        ? theme.accentPrimary.withValues(alpha: 0.42)
        : theme.accentDark.withValues(alpha: 0.55);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.lg),
      decoration: BoxDecoration(
        color: theme.surfacePanel,
        borderRadius: BorderRadius.circular(AppDimensions.radiusModal),
        border: Border.all(color: borderColor, width: accentBorder ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: theme.surfaceDark.withValues(alpha: 0.72),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
          if (accentBorder)
            BoxShadow(
              color: theme.accentPrimary.withValues(alpha: 0.06),
              blurRadius: 22,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: child,
    );
  }
}

class _PrivateGameVariantPicker extends StatelessWidget {
  const _PrivateGameVariantPicker({
    required this.theme,
    required this.sectionTitleStyle,
    required this.variant,
    required this.enabled,
    required this.subtitle,
    required this.onSelectVariant,
  });

  final AppThemeData theme;
  final TextStyle sectionTitleStyle;
  final PrivateGameVariant variant;
  final bool enabled;
  final String subtitle;
  final ValueChanged<PrivateGameVariant>? onSelectVariant;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GAME TYPE', style: sectionTitleStyle),
        const SizedBox(height: AppDimensions.xs),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w400,
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimensions.md),
        _VariantTile(
          theme: theme,
          title: 'Standard',
          caption: 'Classic Last Cards — one winner when someone goes out',
          icon: Icons.style_outlined,
          selected: variant == PrivateGameVariant.standard,
          enabled: enabled && onSelectVariant != null,
          onTap: () => onSelectVariant?.call(PrivateGameVariant.standard),
        ),
        const SizedBox(height: AppDimensions.sm),
        _VariantTile(
          theme: theme,
          title: 'Knockout tournament',
          caption: 'Same table — finish order, qualify & place (online rules)',
          icon: Icons.emoji_events_outlined,
          selected: variant == PrivateGameVariant.knockout,
          enabled: enabled && onSelectVariant != null,
          onTap: () => onSelectVariant?.call(PrivateGameVariant.knockout),
        ),
        const SizedBox(height: AppDimensions.sm),
        _VariantTile(
          theme: theme,
          title: 'Bust',
          caption: 'Elimination rounds — up to 10 players at this table',
          icon: Icons.whatshot_outlined,
          selected: variant == PrivateGameVariant.bust,
          enabled: enabled && onSelectVariant != null,
          onTap: () => onSelectVariant?.call(PrivateGameVariant.bust),
        ),
      ],
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({
    required this.theme,
    required this.title,
    required this.caption,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppThemeData theme;
  final String title;
  final String caption;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? theme.accentPrimary.withValues(alpha: 0.85)
        : theme.accentDark.withValues(alpha: 0.45);
    final bg = selected
        ? theme.accentPrimary.withValues(alpha: 0.1)
        : theme.backgroundMid;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(AppDimensions.md),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? theme.accentLight : theme.textSecondary,
              ),
              const SizedBox(width: AppDimensions.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: theme.textPrimary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        height: 1.35,
                        fontWeight: FontWeight.w400,
                        color: theme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivateLobbyRulesPicker extends StatelessWidget {
  const _PrivateLobbyRulesPicker({
    required this.theme,
    required this.sectionTitleStyle,
    required this.isHardcore,
    required this.enabled,
    required this.subtitle,
    required this.onSelectHardcore,
  });

  final AppThemeData theme;
  final TextStyle sectionTitleStyle;
  final bool isHardcore;
  final bool enabled;
  final String subtitle;
  final ValueChanged<bool>? onSelectHardcore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TABLE RULES', style: sectionTitleStyle),
        const SizedBox(height: AppDimensions.xs),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w400,
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimensions.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _RuleModeChip(
                theme: theme,
                title: 'Casual',
                caption: '60s turns · standard Last Cards',
                icon: Icons.wb_sunny_outlined,
                selected: !isHardcore,
                enabled: enabled && onSelectHardcore != null,
                onTap: () => onSelectHardcore?.call(false),
              ),
            ),
            const SizedBox(width: AppDimensions.md),
            Expanded(
              child: _RuleModeChip(
                theme: theme,
                title: 'Hardcore',
                caption: '30s turns · stricter last-cards',
                icon: Icons.local_fire_department_outlined,
                selected: isHardcore,
                enabled: enabled && onSelectHardcore != null,
                onTap: () => onSelectHardcore?.call(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RuleModeChip extends StatelessWidget {
  const _RuleModeChip({
    required this.theme,
    required this.title,
    required this.caption,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final AppThemeData theme;
  final String title;
  final String caption;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final border = selected
        ? theme.accentPrimary.withValues(alpha: 0.85)
        : theme.accentDark.withValues(alpha: 0.45);
    final bg = selected
        ? theme.accentPrimary.withValues(alpha: 0.12)
        : theme.backgroundMid;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(AppDimensions.md),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
            border: Border.all(color: border, width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? theme.accentLight : theme.textSecondary,
              ),
              const SizedBox(height: AppDimensions.sm),
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.textPrimary,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                caption,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  height: 1.35,
                  fontWeight: FontWeight.w400,
                  color: theme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
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
        vertical: AppDimensions.md + 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(theme.backgroundMid, theme.accentPrimary, 0.06)!,
            theme.backgroundMid,
          ],
        ),
        border: Border.all(
          color: theme.accentPrimary.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.accentPrimary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 5,
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
    this.maxSlots = 7,
    this.isPrivateHost = false,
    this.onRemoveBot,
  });

  final String? localPlayerId;
  final bool localIsReady;
  final Map<String, bool> playerReady;
  final AppThemeData theme;
  final List<PlayerModel> players;
  final bool pendingJoin;
  final String? hostPlayerId;
  final int maxSlots;
  final bool isPrivateHost;
  final void Function(String botPlayerId)? onRemoveBot;

  @override
  Widget build(BuildContext context) {
    final sorted = List<PlayerModel>.from(players)
      ..sort((a, b) {
        if (a.isAi != b.isAi) {
          return a.isAi ? 1 : -1;
        }
        return _playerNumber(a.id).compareTo(_playerNumber(b.id));
      });

    final entries = <_PlayerEntry>[];
    for (var i = 0; i < maxSlots; i++) {
      if (i < sorted.length) {
        final p = sorted[i];
        final isMe = p.id == localPlayerId;
        final ready = p.isAi
            ? true
            : (isMe ? localIsReady : (playerReady[p.id] ?? false));
        entries.add(
          _PlayerEntry(
            name: p.displayName,
            isReady: ready,
            theme: theme,
            isVacantSeat: false,
            isHost: hostPlayerId != null && p.id == hostPlayerId,
            isAi: p.isAi,
            showRemoveBot: isPrivateHost && p.isAi && onRemoveBot != null,
            onRemoveBot: p.isAi ? () => onRemoveBot!(p.id) : null,
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
    final vignetteEdge = Color.lerp(theme.backgroundDeep, Colors.black, 0.44)!;
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
  bool shouldRepaint(covariant _LobbyFeltPainter old) =>
      old.theme.id != theme.id;
}

class _PlayerEntry extends StatelessWidget {
  const _PlayerEntry({
    required this.name,
    required this.isReady,
    required this.theme,
    this.isVacantSeat = false,
    this.isHost = false,
    this.isAi = false,
    this.showRemoveBot = false,
    this.onRemoveBot,
  });

  final String name;
  final bool isReady;
  final bool isVacantSeat;
  final bool isHost;
  final bool isAi;
  final bool showRemoveBot;
  final VoidCallback? onRemoveBot;
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
                if (isAi && !isVacantSeat) ...[
                  const SizedBox(width: 8),
                  Text(
                    'AI',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: theme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isVacantSeat) ...[
            if (showRemoveBot && onRemoveBot != null)
              IconButton(
                tooltip: 'Remove bot',
                onPressed: onRemoveBot,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: theme.textSecondary,
                ),
              ),
            Text(
              isReady ? 'READY' : 'NOT READY',
              style: statusStyle,
            ),
          ],
        ],
      ),
    );
  }
}
