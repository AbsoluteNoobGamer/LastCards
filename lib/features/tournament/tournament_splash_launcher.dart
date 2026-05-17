import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/offline_game_state.dart';
import '../../core/providers/user_profile_provider.dart';
import '../../tournament/tournament_engine.dart';
import '../gameplay/presentation/opponents_splash_helpers.dart';
import '../gameplay/presentation/screens/opponents_splash_screen.dart';
import 'providers/tournament_session_provider.dart';
import 'screens/tournament_coordinator.dart';

/// Pre-tournament opponents splash, then [TournamentCoordinator] with a fixed roster.
void pushOfflineTournamentWithSplash({
  required NavigatorState navigator,
  required WidgetRef ref,
  required int playerCount,
}) {
  final session = ref.read(tournamentSessionProvider);
  final engine = TournamentEngine.offline(
    players: [
      TournamentPlayer(
        id: OfflineGameState.localId,
        displayName: ref.read(displayNameForGameProvider),
        isAi: false,
      ),
    ],
    requiredPlayers: playerCount,
  );
  final roster = engine.allPlayers;
  engine.dispose();

  final localAvatarUrl =
      ref.read(userProfileProvider).valueOrNull?.avatarUrl;
  final participants = OpponentsSplashHelpers.fromTournamentPlayers(
    roster,
    localPlayerId: OfflineGameState.localId,
    localAvatarUrl: localAvatarUrl,
  );

  final diff = session.difficulty;
  final typeLabel = session.type?.displayName ?? 'Tournament';

  navigator.push(
    OpponentsSplashHelpers.splashRoute(
      child: OpponentsSplashScreen(
        participants: participants,
        modeLabel: diff != null
            ? '$typeLabel · ${diff.displayName} · $playerCount Players'
            : '$typeLabel · $playerCount Players',
        subtitle: 'The bracket is set',
        onFinished: (splashContext) {
          if (!splashContext.mounted) return;
          Navigator.of(splashContext).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => TournamentCoordinator(
                isOnline: false,
                playerCount: playerCount,
                aiDifficulty: session.difficulty,
                initialRoster: roster,
                skipOpeningSplash: true,
              ),
              transitionDuration: const Duration(milliseconds: 600),
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          );
        },
      ),
    ),
  );
}
