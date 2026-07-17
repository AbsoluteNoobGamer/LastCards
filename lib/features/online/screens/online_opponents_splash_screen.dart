import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/game_event.dart';
import '../../../core/models/game_state.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/game_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../../core/services/avatar_catalog_service.dart';
import '../../gameplay/presentation/opponents_splash_helpers.dart';
import '../../gameplay/presentation/screens/opponents_splash_screen.dart';
import '../../gameplay/presentation/screens/table_screen.dart';
import '../../tournament/providers/tournament_session_provider.dart';
import '../providers/online_session_provider.dart';

/// Online pre-game splash: shows the matched roster, waits for [GamePhase.playing],
/// then navigates to [TableScreen] (or tournament/bust variants).
///
/// Public casual matches may open a short knockout vote before the deal.
class OnlineOpponentsSplashScreen extends ConsumerStatefulWidget {
  const OnlineOpponentsSplashScreen({super.key});

  @override
  ConsumerState<OnlineOpponentsSplashScreen> createState() =>
      _OnlineOpponentsSplashScreenState();
}

class _OnlineOpponentsSplashScreenState
    extends ConsumerState<OnlineOpponentsSplashScreen> {
  StreamSubscription<StateSnapshotEvent>? _snapshotSub;
  StreamSubscription<GameEvent>? _eventSub;
  bool _snapshotReceived = false;

  bool _voteOpen = false;
  bool _hasVoted = false;
  int _secondsRemaining = 15;
  int _yesCount = 0;
  int _noCount = 0;
  int _votedCount = 0;
  int _totalVoters = 0;
  Timer? _countdownTicker;
  bool? _voteResultKnockout;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(gameNotifierProvider).gameState;
    if (existing != null && existing.phase == GamePhase.playing) {
      _snapshotReceived = true;
    }

    final handler = ref.read(gameEventHandlerProvider);
    _snapshotSub = handler.stateSnapshots.listen((e) {
      if (!mounted) return;
      if (e.gameState.phase == GamePhase.playing) {
        _snapshotReceived = true;
        setState(() {});
      }
    });
    _eventSub = handler.events.listen(_onGameEvent);
  }

  void _onGameEvent(GameEvent event) {
    if (!mounted) return;
    if (event is TournamentVoteOpenEvent) {
      _countdownTicker?.cancel();
      setState(() {
        _voteOpen = true;
        _hasVoted = false;
        _secondsRemaining = event.secondsRemaining;
        _totalVoters = event.totalVoters;
        _yesCount = 0;
        _noCount = 0;
        _votedCount = 0;
        _voteResultKnockout = null;
      });
      _countdownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() {
          _secondsRemaining =
              _secondsRemaining > 0 ? _secondsRemaining - 1 : 0;
        });
        if (_secondsRemaining <= 0) t.cancel();
      });
    } else if (event is TournamentVoteUpdateEvent) {
      setState(() {
        _yesCount = event.yesCount;
        _noCount = event.noCount;
        _votedCount = event.votedCount;
        _totalVoters = event.totalVoters;
      });
    } else if (event is TournamentVoteResultEvent) {
      _countdownTicker?.cancel();
      if (event.isKnockoutTournament) {
        final n = ref.read(tournamentSessionProvider.notifier);
        n.setFormat(TournamentFormat.knockout);
        n.setSubMode(GameSubMode.knockout);
      }
      setState(() {
        _voteOpen = false;
        _voteResultKnockout = event.isKnockoutTournament;
      });
    } else if (event is SessionConfigEvent && event.isKnockoutTournament) {
      final n = ref.read(tournamentSessionProvider.notifier);
      n.setFormat(TournamentFormat.knockout);
      n.setSubMode(GameSubMode.knockout);
    }
  }

  void _castVote(bool wantTournament) {
    if (_hasVoted || !_voteOpen) return;
    final ws = ref.read(wsClientProvider);
    if (!ws.send(jsonEncode({
      'type': 'vote_tournament',
      'wantTournament': wantTournament,
    }))) {
      return;
    }
    setState(() => _hasVoted = true);
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    _eventSub?.cancel();
    _countdownTicker?.cancel();
    super.dispose();
  }

  void _navigateToGame(BuildContext splashContext) {
    if (!splashContext.mounted) return;
    _snapshotSub?.cancel();
    _snapshotSub = null;
    _eventSub?.cancel();
    _eventSub = null;

    final playerCount = ref.read(onlineSessionProvider).playerCount ?? 4;
    final session = ref.read(tournamentSessionProvider);
    final isBust = session.subMode == GameSubMode.bust;
    final isTournament = session.format != null ||
        ref.read(gameNotifierProvider).isKnockoutTournamentSession ||
        _voteResultKnockout == true;

    // Deliberately NOT resetting onlineSessionProvider here — a rematch from
    // TableScreen reopens MatchmakingScreen expecting this session's mode
    // (and then preparePublicRematch sets select-table + playerCount). It
    // gets cleared when the player leaves (_leaveOnlineMatch) or starts a
    // fresh mode selection from the menu.

    final Widget destination;
    if (isBust) {
      destination = TableScreen(totalPlayers: playerCount, isOnline: true);
    } else if (isTournament) {
      destination = TableScreen(
        totalPlayers: playerCount,
        isTournamentMode: true,
        isOnline: true,
      );
    } else {
      destination = TableScreen(totalPlayers: playerCount, isOnline: true);
    }

    Navigator.of(splashContext).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
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
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider).theme;
    final onlineSession = ref.watch(onlineSessionProvider);
    final gameState = ref.watch(gameStateProvider);
    final localName = ref.watch(displayNameForGameProvider);
    final localAvatarUrl =
        ref.watch(userProfileProvider).valueOrNull?.avatarUrl;

    final ready = !_voteOpen &&
        _snapshotReceived &&
        gameState != null &&
        gameState.phase == GamePhase.playing;

    final localCosmetic =
        AvatarCatalogService.instance.equippedCosmeticId;
    final participants = gameState != null && gameState.players.isNotEmpty
        ? OpponentsSplashHelpers.fromGameState(
            gameState,
            localDisplayNameFallback: localName,
            localAvatarUrl: localAvatarUrl,
            localAvatarCosmeticId: localCosmetic,
          )
        : OpponentsSplashHelpers.fromDisplayNames(
            List<String?>.generate(
              onlineSession.playerCount ?? 4,
              (i) => i == 0 ? localName : null,
            ),
            localSlotIndex: 0,
            localAvatarUrl: localAvatarUrl,
            localAvatarCosmeticId: localCosmetic,
          );

    final modeLabel = onlineSession.mode?.displayName ?? 'Online';
    final subtitle = _voteOpen
        ? 'Vote: knockout tournament? (${_secondsRemaining}s)'
        : ready
            ? (_voteResultKnockout == true
                ? 'Knockout it is — let\'s play'
                : 'Everyone is in — let\'s play')
            : 'Syncing table…';

    return Stack(
      children: [
        OpponentsSplashScreen(
          modeLabel: '$modeLabel · ${participants.length} Players',
          subtitle: subtitle,
          participants: participants,
          holdCountdown: !ready,
          onFinished: _navigateToGame,
        ),
        if (_voteOpen)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.surfacePanel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.accentPrimary.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Knockout tournament?',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cinzel(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: theme.accentPrimary,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Same table — finish order decides placement. '
                                'Majority vote wins.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  height: 1.4,
                                  color: theme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Yes $_yesCount · No $_noCount'
                                ' · $_votedCount/$_totalVoters voted'
                                ' · ${_secondsRemaining}s',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: theme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (_hasVoted)
                                Text(
                                  'Vote sent — waiting for others…',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: theme.textSecondary,
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => _castVote(false),
                                        child: const Text('No'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => _castVote(true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: theme.accentPrimary,
                                          foregroundColor: theme.backgroundDeep,
                                        ),
                                        child: const Text('Yes'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
