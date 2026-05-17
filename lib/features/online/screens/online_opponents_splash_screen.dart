import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/game_event.dart';
import '../../../core/models/game_state.dart';
import '../../../core/providers/connection_provider.dart';
import '../../../core/providers/game_provider.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../gameplay/presentation/opponents_splash_helpers.dart';
import '../../gameplay/presentation/screens/opponents_splash_screen.dart';
import '../../gameplay/presentation/screens/table_screen.dart';
import '../../tournament/providers/tournament_session_provider.dart';
import '../providers/online_session_provider.dart';

/// Online pre-game splash: shows the matched roster, waits for [GamePhase.playing],
/// then navigates to [TableScreen] (or tournament/bust variants).
class OnlineOpponentsSplashScreen extends ConsumerStatefulWidget {
  const OnlineOpponentsSplashScreen({super.key});

  @override
  ConsumerState<OnlineOpponentsSplashScreen> createState() =>
      _OnlineOpponentsSplashScreenState();
}

class _OnlineOpponentsSplashScreenState
    extends ConsumerState<OnlineOpponentsSplashScreen> {
  StreamSubscription<StateSnapshotEvent>? _snapshotSub;
  bool _snapshotReceived = false;

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
  }

  @override
  void dispose() {
    _snapshotSub?.cancel();
    super.dispose();
  }

  void _navigateToGame(BuildContext splashContext) {
    if (!splashContext.mounted) return;
    _snapshotSub?.cancel();
    _snapshotSub = null;

    final playerCount = ref.read(onlineSessionProvider).playerCount ?? 4;
    final session = ref.read(tournamentSessionProvider);
    final isBust = session.subMode == GameSubMode.bust;
    final isTournament = session.format != null;

    ref.read(onlineSessionProvider.notifier).reset();

    final Widget destination;
    if (isBust) {
      destination = TableScreen(totalPlayers: playerCount);
    } else if (isTournament) {
      destination = TableScreen(
        totalPlayers: playerCount,
        isTournamentMode: true,
      );
    } else {
      destination = TableScreen(totalPlayers: playerCount);
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
    final onlineSession = ref.watch(onlineSessionProvider);
    final gameState = ref.watch(gameStateProvider);
    final localName = ref.watch(displayNameForGameProvider);
    final localAvatarUrl =
        ref.watch(userProfileProvider).valueOrNull?.avatarUrl;

    final ready = _snapshotReceived &&
        gameState != null &&
        gameState.phase == GamePhase.playing;

    final participants = gameState != null && gameState.players.isNotEmpty
        ? OpponentsSplashHelpers.fromGameState(
            gameState,
            localDisplayNameFallback: localName,
            localAvatarUrl: localAvatarUrl,
          )
        : OpponentsSplashHelpers.fromDisplayNames(
            List<String?>.generate(
              onlineSession.playerCount ?? 4,
              (i) => i == 0 ? localName : null,
            ),
            localSlotIndex: 0,
            localAvatarUrl: localAvatarUrl,
          );

    final modeLabel = onlineSession.mode?.displayName ?? 'Online';

    return OpponentsSplashScreen(
      modeLabel: '$modeLabel · ${participants.length} Players',
      subtitle: ready ? 'Everyone is in — let\'s play' : 'Syncing table…',
      participants: participants,
      holdCountdown: !ready,
      onFinished: _navigateToGame,
    );
  }
}
