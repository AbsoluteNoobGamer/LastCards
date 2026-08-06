import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
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
        SetWagerConfigAction,
        StateSnapshotEvent,
        TextChatAction,
        TextChatEvent,
        WagerStateEvent;
import '../../../chat/presentation/widgets/live_text_chat_panel.dart';
import '../../../../core/models/game_state.dart';
import '../../../../core/models/player_model.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/block_provider.dart';
import '../../../../core/providers/friends_provider.dart';
import '../../../../core/providers/connection_provider.dart';
import '../../../../core/network/websocket_client.dart';
import '../../../../core/providers/user_profile_provider.dart';
import '../../../../core/providers/game_provider.dart';
import '../../../../core/providers/online_rejoin_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/services/avatar_catalog_service.dart';
import '../../../../core/theme/app_dimensions.dart';
import '../../../../core/theme/app_theme_data.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/models/ai_player_config.dart';
import '../../../gameplay/presentation/opponents_splash_helpers.dart';
import '../../../gameplay/presentation/screens/table_screen.dart';
import '../../../gameplay/presentation/widgets/wager_challenge_banner.dart';
import '../../../../widgets/side_bet_challenge_sheet.dart';
import '../../../social/widgets/invite_friends_sheet.dart';
import '../../../social/widgets/pending_friend_requests_banner.dart';
import '../../../social/widgets/report_block_sheet.dart';
import '../../../tournament/providers/tournament_session_provider.dart';
import '../../../voice/widgets/ptt_chrome_fab.dart';

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
    this.challengeToUid,
    this.challengeToDisplayName,
    super.key,
  });

  final OnlineMode onlineMode;

  /// When set (e.g. from a friend invite), fills the code and attempts [join_room].
  final String? initialRoomCodeToJoin;

  /// Remove this Firestore invite doc after a successful join (`users/me/gameInvites/id`).
  final String? pendingGameInviteDocIdToDismiss;

  /// When set (e.g. from a leaderboard "Challenge" tap), auto-hosts a private
  /// room on open and sends this uid an in-app game invite once it exists.
  final String? challengeToUid;

  /// Shown in the "Challenge sent" confirmation snackbar.
  final String? challengeToDisplayName;

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

  /// Guards against sending [widget.challengeToUid] more than one invite.
  bool _challengeInviteSent = false;

  /// Standard last-cards, knockout finish order, or bust elimination.
  PrivateGameVariant _privateGameVariant = PrivateGameVariant.standard;

  AiDifficulty _aiDifficulty = AiDifficulty.medium;
  final List<PlayerModel> _lobbyPlayers = [];
  final Map<String, bool> _playerReady = {};

  /// Active table wager (whole-table pot or targeted 1v1 side-bet), synced
  /// from [WagerStateEvent]. Null [_wagerMode] means no wager is currently
  /// proposed.
  String? _wagerMode;
  int? _wagerStakeCoins;
  String? _wagerInitiatorPlayerId;
  String? _wagerTargetPlayerId;
  bool _wagerLocked = false;
  Map<String, String> _wagerAcceptStatus = {};
  StreamSubscription<RoomCreatedEvent>? _roomCreatedSub;
  StreamSubscription<StateSnapshotEvent>? _stateSnapshotSub;
  StreamSubscription<GameEvent>? _lobbyEventsSub;
  StreamSubscription<TextChatEvent>? _textChatSub;

  final List<LiveChatLine> _chatMessages = [];

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
      _syncVoiceSession(
        roomCode: e.roomCode,
        playerId: e.playerId.isNotEmpty ? e.playerId : _localPlayerId,
      );
      final challengeUid = widget.challengeToUid;
      if (challengeUid != null && !_challengeInviteSent) {
        _challengeInviteSent = true;
        unawaited(_sendChallengeInvite(challengeUid, e.roomCode));
      }
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
    final challengeUid = widget.challengeToUid;
    if (joinCode == null && challengeUid != null && challengeUid.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_onCreate());
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
          // Host receives player_joined before room_created; learn our id early
          // so the seat list uses local ready state instead of waiting on map.
          _localPlayerId ??= e.player.id;
          if (e.player.isAi) {
            _playerReady[e.player.id] = true;
          }
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
        _syncVoiceSession(
          roomCode: _roomCode,
          playerId: _localPlayerId,
        );
        return;
      }
      if (e is PrivateLobbySettingsEvent) {
        setState(() => _privateLobbyHardcore = e.isHardcore);
        return;
      }
      if (e is WagerStateEvent) {
        setState(() {
          _wagerMode = e.mode;
          _wagerStakeCoins = e.stakeCoins;
          _wagerInitiatorPlayerId = e.initiatorPlayerId;
          _wagerTargetPlayerId = e.targetPlayerId;
          _wagerLocked = e.locked;
          _wagerAcceptStatus = e.acceptStatus;
        });
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
        _syncVoiceSession(roomCode: e.roomCode, playerId: e.playerId);
        final pending = widget.pendingGameInviteDocIdToDismiss;
        if (pending != null) {
          AnalyticsService.instance.logInviteAccepted();
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
        return;
      }
    });

    _textChatSub = handler.textChats.listen((e) {
      if (!mounted) return;
      if (e.playerId != _localPlayerId && _isBlockedSender(e.playerId)) {
        return;
      }
      _appendChatLine(
        playerId: e.playerId,
        displayName: e.displayName,
        text: e.text,
      );
    });
  }

  void _appendChatLine({
    required String playerId,
    required String displayName,
    required String text,
  }) {
    setState(() {
      _chatMessages.add(
        LiveChatLine(
          playerId: playerId,
          displayName: displayName,
          text: text,
          isLocal: playerId == _localPlayerId,
        ),
      );
      if (_chatMessages.length > 80) {
        _chatMessages.removeRange(0, _chatMessages.length - 80);
      }
    });
  }

  /// True when [playerId]'s Firebase uid (if any) is on the local blocklist.
  bool _isBlockedSender(String playerId) {
    final uid = _lobbyPlayers.firstWhereOrNull((p) => p.id == playerId)?.firebaseUid;
    if (uid == null) return false;
    return (ref.read(blockedUidSetProvider).value ?? const {}).contains(uid);
  }

  void _showReportOrBlockSheet(LiveChatLine line) {
    final uid =
        _lobbyPlayers.firstWhereOrNull((p) => p.id == line.playerId)?.firebaseUid;
    final isBlocked = uid != null &&
        (ref.read(blockedUidSetProvider).value ?? const {}).contains(uid);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReportBlockSheet(
        firebaseUid: uid,
        displayName: line.displayName,
        messageText: line.text,
        roomCode: _roomCode,
        isBlocked: isBlocked,
      ),
    );
  }

  void _syncVoiceSession({String? roomCode, String? playerId}) {
    final rejoin = ref.read(onlineRejoinProvider.notifier);
    final code = roomCode ?? _roomCode;
    final id = playerId ?? _localPlayerId;
    if (code != null && code.isNotEmpty) {
      rejoin.setRoomCode(code);
    }
    if (id != null && id.isNotEmpty) {
      rejoin.setPlayerId(id);
    }
  }

  void _sendLobbyChat(String text) {
    if (_roomCode == null) return;
    final handler = ref.read(gameEventHandlerProvider);
    final ok = handler.sendTextChat(TextChatAction(text: text));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not connected — rejoin the room to chat.'),
          backgroundColor: Color(0xFFB71C1C),
        ),
      );
    }
  }

  @override
  void dispose() {
    _roomCreatedSub?.cancel();
    _stateSnapshotSub?.cancel();
    _lobbyEventsSub?.cancel();
    _textChatSub?.cancel();
    _codeController.dispose();
    // Leaving the lobby must drop the socket so the server removes this client
    // from the room; otherwise re-entry stacks duplicate "players".
    // Note: do not clear [onlineRejoinProvider] here — navigating into the
    // table also disposes this screen and must keep room/player ids.
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
                                  if (_roomCode != null &&
                                      _privateGameVariant !=
                                          PrivateGameVariant.bust) ...[
                                    _WagerPotPanel(
                                      theme: theme,
                                      sectionTitleStyle: sectionTitleStyle,
                                      isHost: _isPrivateHost,
                                      localPlayerId: _localPlayerId,
                                      players: _lobbyPlayers,
                                      stakeCoins: _wagerMode == 'pot'
                                          ? _wagerStakeCoins
                                          : null,
                                      initiatorPlayerId:
                                          _wagerInitiatorPlayerId,
                                      acceptStatus: _wagerAcceptStatus,
                                      onPropose: _proposePotWager,
                                      onCancel: _cancelPotWager,
                                      onAccept: _acceptWager,
                                      onDecline: _declineWager,
                                    ),
                                    const SizedBox(height: AppDimensions.lg),
                                  ],
                                  if (_buildSideBetChallengeBanner(theme)
                                      case final banner?) ...[
                                    banner,
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
                                    allowSideBetChallenge:
                                        _privateGameVariant !=
                                            PrivateGameVariant.bust,
                                    onChallengeSideBet: _onOpenSideBetSheet,
                                  ),
                                  if (_roomCode != null) ...[
                                    const SizedBox(height: AppDimensions.lg),
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: LiveTextChatPanel(
                                            theme: theme,
                                            messages: _chatMessages,
                                            onSend: _sendLobbyChat,
                                            tall: true,
                                            enabled: true,
                                            onReportOrBlock:
                                                _showReportOrBlockSheet,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        const PttChromeFab(),
                                      ],
                                    ),
                                  ],
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
    final avatarUrl = ref.read(userProfileProvider).valueOrNull?.avatarUrl;
    final avatarCosmeticId =
        AvatarCatalogService.instance.equippedCosmeticId;
    if (!wsClient.send(jsonEncode({
      'type': 'join_room',
      'roomCode': code,
      'displayName': ref.read(displayNameForGameProvider),
      if (idToken != null) 'idToken': idToken,
      if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
      if (avatarCosmeticId != null) 'avatarCosmeticId': avatarCosmeticId,
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
    final createAvatarUrl =
        ref.read(userProfileProvider).valueOrNull?.avatarUrl;
    final createCosmeticId =
        AvatarCatalogService.instance.equippedCosmeticId;
    if (!wsClient.send(jsonEncode({
      'type': 'create_room',
      'displayName': ref.read(displayNameForGameProvider),
      'isHardcore': _privateLobbyHardcore,
      'gameVariant': _privateGameVariant.wireName,
      if (idToken != null) 'idToken': idToken,
      if (createAvatarUrl != null && createAvatarUrl.isNotEmpty)
        'avatarUrl': createAvatarUrl,
      if (createCosmeticId != null) 'avatarCosmeticId': createCosmeticId,
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
    AnalyticsService.instance.logShareTapped();
    AnalyticsService.instance.logInviteSent(channel: 'share_sheet');
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Last Cards — room $code',
      ),
    );
  }

  Future<void> _sendChallengeInvite(String toUid, String roomCode) async {
    final fromName = ref.read(displayNameForGameProvider);
    final targetName = widget.challengeToDisplayName ?? 'Player';
    try {
      await ref.read(friendsServiceProvider).sendGameInvite(
            toUid: toUid,
            roomCode: roomCode,
            fromDisplayName: fromName,
            isChallenge: true,
          );
      AnalyticsService.instance.logInviteSent(channel: 'challenge');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Challenge sent to $targetName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send challenge: $e')),
        );
      }
    }
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
    // A table-pot wager needs everyone's explicit accept before it's fair
    // to charge stakes — this mirrors the server's own gate in
    // GameSession._lockInWagerStakes, so the host gets an immediate,
    // specific reason instead of a generic connection-style error.
    if (_wagerMode == 'pot') {
      final unaccepted = _lobbyPlayers.where((p) =>
          p.id != _wagerInitiatorPlayerId &&
          _wagerAcceptStatus[p.id] != 'accepted');
      if (unaccepted.isNotEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Waiting for everyone to accept the wager.'),
            backgroundColor: Color(0xFFB71C1C),
          ),
        );
        return;
      }
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

  void _proposePotWager(int stakeCoins) {
    ref.read(gameEventHandlerProvider).sendSetWagerConfig(
          SetWagerConfigAction(mode: 'pot', stakeCoins: stakeCoins),
        );
  }

  void _cancelPotWager() {
    ref.read(gameEventHandlerProvider).sendSetWagerConfig(
          const SetWagerConfigAction(mode: 'pot', stakeCoins: 0),
        );
  }

  void _acceptWager() {
    ref.read(gameEventHandlerProvider).sendAcceptWager();
  }

  void _declineWager() {
    ref.read(gameEventHandlerProvider).sendDeclineWager();
  }

  void _withdrawSideBetWager() {
    ref.read(gameEventHandlerProvider).sendSetWagerConfig(
          const SetWagerConfigAction(mode: 'sideBet', stakeCoins: 0),
        );
  }

  /// Builds the active/pending side-bet status banner for the local player
  /// — the target's only way to accept a challenge before this fix, since
  /// [_WagerPotPanel] only ever renders its host-only propose form for a
  /// side-bet (its accept/decline UI is pot-only). Null if there's nothing
  /// to show (no proposal, or the local player isn't one of its two
  /// participants).
  Widget? _buildSideBetChallengeBanner(AppThemeData theme) {
    if (_wagerMode != 'sideBet') return null;
    final localId = _localPlayerId;
    final initiatorId = _wagerInitiatorPlayerId;
    final targetId = _wagerTargetPlayerId;
    if (localId == null || initiatorId == null || targetId == null) {
      return null;
    }
    if (localId != initiatorId && localId != targetId) return null;
    final isInitiator = localId == initiatorId;
    final opponentId = isInitiator ? targetId : initiatorId;
    final opponentName = _lobbyPlayers
            .firstWhereOrNull((p) => p.id == opponentId)
            ?.displayName ??
        'Opponent';
    return WagerChallengeBanner(
      theme: theme,
      opponentName: opponentName,
      stakeCoins: _wagerStakeCoins ?? 0,
      locked: _wagerLocked,
      isInitiator: isInitiator,
      onAccept: _acceptWager,
      onDecline: _declineWager,
      onWithdraw: _withdrawSideBetWager,
    );
  }

  /// Sends a targeted 1v1 side-bet challenge to [targetPlayerId]. Unlike the
  /// table pot, a side-bet never blocks the rest of the table from starting
  /// (see server GameSession.startGameFromHost) — if [targetPlayerId] never
  /// accepts, it's silently dropped at match start.
  void _onChallengeSideBet(String targetPlayerId, int stakeCoins) {
    ref.read(gameEventHandlerProvider).sendSetWagerConfig(
          SetWagerConfigAction(
            mode: 'sideBet',
            stakeCoins: stakeCoins,
            targetPlayerId: targetPlayerId,
          ),
        );
  }

  Future<void> _onOpenSideBetSheet(String targetPlayerId, String targetName) {
    final theme = ref.read(themeProvider).theme;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.backgroundDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SideBetChallengeSheet(
        theme: theme,
        targetName: targetName,
        onConfirm: (stakeCoins) {
          _onChallengeSideBet(targetPlayerId, stakeCoins);
          Navigator.of(ctx).pop();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Side-bet challenge sent to $targetName.'),
              backgroundColor: theme.accentPrimary,
            ),
          );
        },
      ),
    );
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
    final gameState = ref.read(gameNotifierProvider).gameState;
    final localName = ref.read(displayNameForGameProvider);
    final localAvatarUrl =
        ref.read(userProfileProvider).valueOrNull?.avatarUrl;
    final localCosmetic =
        AvatarCatalogService.instance.equippedCosmeticId;

    final participants = gameState != null && gameState.players.isNotEmpty
        ? OpponentsSplashHelpers.fromGameState(
            gameState,
            localPlayerId: _localPlayerId,
            localDisplayNameFallback: localName,
            localAvatarUrl: localAvatarUrl,
            localAvatarCosmeticId: localCosmetic,
          )
        : OpponentsSplashHelpers.fromDisplayNames(
            List<String?>.generate(totalPlayers, (i) => i == 0 ? localName : null),
            localSlotIndex: 0,
            localAvatarUrl: localAvatarUrl,
            localAvatarCosmeticId: localCosmetic,
          );

    final variantLabel = switch (_privateGameVariant) {
      PrivateGameVariant.standard => 'Private Game',
      PrivateGameVariant.knockout => 'Private Knockout',
      PrivateGameVariant.bust => 'Private Bust',
    };

    OpponentsSplashHelpers.push(
      context,
      participants: participants,
      modeLabel: '$variantLabel · $totalPlayers Players',
      subtitle: 'Your table is ready',
      onFinished: (splashContext) {
        if (!splashContext.mounted) return;
        Navigator.of(splashContext).pushReplacement(
          AppPageRoutes.fadeSlide(
            (_) => TableScreen(
              totalPlayers: totalPlayers,
              isTournamentMode:
                  isKnockout || widget.onlineMode == OnlineMode.tournament,
              isOnline: true,
            ),
          ),
        );
      },
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

/// Whole-table pot wager: host proposes a per-player stake, every other
/// seat accepts/declines, host can cancel. Visible to everyone once a pot
/// is proposed (not just the host) so guests can accept/decline.
class _WagerPotPanel extends StatefulWidget {
  const _WagerPotPanel({
    required this.theme,
    required this.sectionTitleStyle,
    required this.isHost,
    required this.localPlayerId,
    required this.players,
    required this.stakeCoins,
    required this.initiatorPlayerId,
    required this.acceptStatus,
    required this.onPropose,
    required this.onCancel,
    required this.onAccept,
    required this.onDecline,
  });

  final AppThemeData theme;
  final TextStyle sectionTitleStyle;
  final bool isHost;
  final String? localPlayerId;
  final List<PlayerModel> players;

  /// Null when no pot wager is currently proposed/active.
  final int? stakeCoins;
  final String? initiatorPlayerId;
  final Map<String, String> acceptStatus;
  final ValueChanged<int> onPropose;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  State<_WagerPotPanel> createState() => _WagerPotPanelState();
}

class _WagerPotPanelState extends State<_WagerPotPanel> {
  final _stakeController = TextEditingController(text: '25');

  @override
  void dispose() {
    _stakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return widget.stakeCoins == null
        ? _buildProposeForm(theme)
        : _buildActiveWager(theme);
  }

  Widget _buildProposeForm(AppThemeData theme) {
    if (!widget.isHost) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COIN WAGER', style: widget.sectionTitleStyle),
        const SizedBox(height: AppDimensions.xs),
        Text(
          'Everyone at the table stakes the same amount — winner takes the '
          'pot. Every seat must accept before you can start.',
          style: GoogleFonts.inter(
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w400,
            color: theme.textSecondary,
          ),
        ),
        const SizedBox(height: AppDimensions.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _stakeController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(
                    Icons.monetization_on_rounded,
                    color: theme.accentPrimary,
                    size: 20,
                  ),
                  hintText: 'Stake per player',
                  hintStyle: GoogleFonts.inter(color: theme.textSecondary),
                  filled: true,
                  fillColor: theme.backgroundDeep.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusModal),
                    borderSide: BorderSide(
                      color: theme.accentDark.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.sm),
            ElevatedButton(
              onPressed: () {
                final v = int.tryParse(_stakeController.text.trim());
                if (v != null && v > 0) widget.onPropose(v);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.accentPrimary,
                foregroundColor: theme.backgroundDeep,
                minimumSize: const Size(0, AppDimensions.minTouchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusModal),
                ),
              ),
              child: Text(
                'PROPOSE',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveWager(AppThemeData theme) {
    final isInitiator = widget.localPlayerId != null &&
        widget.localPlayerId == widget.initiatorPlayerId;
    final localStatus = widget.localPlayerId != null
        ? widget.acceptStatus[widget.localPlayerId]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COIN WAGER', style: widget.sectionTitleStyle),
        const SizedBox(height: AppDimensions.xs),
        Text(
          '${widget.stakeCoins} coins per player · winner takes the pot',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: theme.accentLight,
          ),
        ),
        const SizedBox(height: AppDimensions.sm),
        Wrap(
          spacing: AppDimensions.sm,
          runSpacing: AppDimensions.xs,
          children: widget.players.map((p) {
            final isInit = p.id == widget.initiatorPlayerId;
            final status = isInit ? 'set' : (widget.acceptStatus[p.id] ?? 'pending');
            final color = status == 'accepted'
                ? const Color(0xFF27AE60)
                : status == 'declined'
                    ? theme.suitRed
                    : theme.textSecondary;
            return Chip(
              backgroundColor: color.withValues(alpha: 0.14),
              side: BorderSide(color: color.withValues(alpha: 0.5)),
              label: Text(
                '${p.displayName} · $status',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppDimensions.md),
        if (isInitiator)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: widget.onCancel,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.textSecondary,
                side: BorderSide(color: theme.accentDark.withValues(alpha: 0.7)),
                minimumSize: const Size(0, AppDimensions.minTouchTarget),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusModal),
                ),
              ),
              child: Text(
                'CANCEL WAGER',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          )
        else if (widget.localPlayerId != null)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      localStatus == 'declined' ? null : widget.onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.suitRed,
                    side: BorderSide(
                      color: theme.suitRed.withValues(alpha: 0.7),
                    ),
                    minimumSize: const Size(0, AppDimensions.minTouchTarget),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusModal),
                    ),
                  ),
                  child: Text(
                    'DECLINE',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      localStatus == 'accepted' ? null : widget.onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF27AE60),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, AppDimensions.minTouchTarget),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusModal),
                    ),
                  ),
                  child: Text(
                    'ACCEPT',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
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
    this.allowSideBetChallenge = false,
    this.onChallengeSideBet,
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

  /// Whether a "challenge to side-bet" affordance may be shown at all
  /// (false in Bust mode, which doesn't support wagers).
  final bool allowSideBetChallenge;
  final Future<void> Function(String targetPlayerId, String targetName)?
      onChallengeSideBet;

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
        final isMe = localPlayerId != null && p.id == localPlayerId;
        final serverReady = playerReady[p.id] ?? false;
        final ready = p.isAi
            ? true
            : (isMe ? localIsReady : serverReady);
        final canChallenge = allowSideBetChallenge &&
            !isMe &&
            !p.isAi &&
            onChallengeSideBet != null &&
            (p.firebaseUid ?? '').isNotEmpty &&
            localPlayerId != null &&
            (players.firstWhereOrNull((me) => me.id == localPlayerId)
                        ?.firebaseUid ??
                    '')
                .isNotEmpty;
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
            showChallengeSideBet: canChallenge,
            onChallengeSideBet: canChallenge
                ? () => onChallengeSideBet!(p.id, p.displayName)
                : null,
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
    this.showChallengeSideBet = false,
    this.onChallengeSideBet,
  });

  final String name;
  final bool isReady;
  final bool isVacantSeat;
  final bool isHost;
  final bool isAi;
  final bool showRemoveBot;
  final VoidCallback? onRemoveBot;
  final bool showChallengeSideBet;
  final VoidCallback? onChallengeSideBet;
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
            if (showChallengeSideBet && onChallengeSideBet != null)
              IconButton(
                tooltip: 'Challenge to a side-bet',
                onPressed: onChallengeSideBet,
                icon: Icon(
                  Icons.monetization_on_outlined,
                  size: 20,
                  color: theme.accentPrimary,
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
