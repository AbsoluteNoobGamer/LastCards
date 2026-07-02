import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/ai_player_config.dart';
import '../../../core/providers/game_provider.dart';
import '../../../core/providers/user_profile_provider.dart';
import '../../gameplay/presentation/opponents_splash_helpers.dart';
import '../../gameplay/presentation/screens/opponents_splash_screen.dart';
import '../../gameplay/presentation/screens/table_screen.dart';
import '../providers/single_player_session_provider.dart';

/// Opponents splash for single-player: shows you and every AI seat, then deals.
class GameLoadingScreen extends ConsumerWidget {
  const GameLoadingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(singlePlayerSessionProvider);
    final difficulty = session.difficulty;
    final playerCount = session.playerCount ?? 2;
    final localName = ref.watch(displayNameForGameProvider);
    final localAvatarUrl =
        ref.watch(userProfileProvider).valueOrNull?.avatarUrl;

    final aiConfigs = session.aiPlayerConfigs.isNotEmpty
        ? session.aiPlayerConfigs
        : AiPlayerConfig.generateForGame(
            count: playerCount - 1,
            seed: DateTime.now().millisecondsSinceEpoch,
          );

    final modeLabel = difficulty != null
        ? '${difficulty.emoji} ${difficulty.displayName}  ·  $playerCount Players'
        : '$playerCount Players';

    final participants = OpponentsSplashHelpers.fromAiConfigs(
      localDisplayName: localName,
      localAvatarUrl: localAvatarUrl,
      aiConfigs: aiConfigs,
    );

    return OpponentsSplashScreen(
      modeLabel: modeLabel,
      subtitle: 'Meet your opponents',
      participants: participants,
      onFinished: (splashContext) => _launchGame(splashContext, ref),
    );
  }

  void _launchGame(BuildContext context, WidgetRef ref) {
    if (!context.mounted) return;
    final session = ref.read(singlePlayerSessionProvider);
    final playerCount = session.playerCount ?? 2;
    final difficulty = session.difficulty;
    final aiConfigs = session.aiPlayerConfigs;

    ref.read(singlePlayerSessionProvider.notifier).reset();
    ref.read(gameNotifierProvider.notifier).clearOnlineState();

    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => TableScreen(
          totalPlayers: playerCount,
          aiDifficulty: difficulty,
          isOnline: false,
          preloadedAiPlayerConfigs:
              aiConfigs.isNotEmpty ? aiConfigs : null,
        ),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
      (route) => route.isFirst,
    );
  }
}
