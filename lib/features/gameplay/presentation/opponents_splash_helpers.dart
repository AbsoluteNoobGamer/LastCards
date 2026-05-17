import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/models/ai_player_config.dart';
import '../../../core/models/game_state.dart';
import '../../../core/models/offline_game_state.dart';
import '../../../core/models/player_model.dart';
import '../../../tournament/tournament_engine.dart';
import 'screens/opponents_splash_screen.dart';
import 'widgets/opponent_splash_tile.dart';

/// Builds [OpponentSplashParticipant] lists and pushes the shared splash route.
abstract final class OpponentsSplashHelpers {
  static PageRouteBuilder<void> splashRoute({
    required Widget child,
    Duration transitionDuration = const Duration(milliseconds: 400),
  }) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => child,
      transitionDuration: transitionDuration,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.05),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
    );
  }

  static Future<void> push(
    BuildContext context, {
    required List<OpponentSplashParticipant> participants,
    required OpponentsSplashOnFinished onFinished,
    String? modeLabel,
    String subtitle = 'Meet your opponents',
    bool showCountdown = true,
    bool holdCountdown = false,
  }) {
    return Navigator.of(context).push(
      splashRoute(
        child: OpponentsSplashScreen(
          participants: participants,
          modeLabel: modeLabel,
          subtitle: subtitle,
          showCountdown: showCountdown,
          holdCountdown: holdCountdown,
          onFinished: onFinished,
        ),
      ),
    );
  }

  static List<OpponentSplashParticipant> fromAiConfigs({
    required String localDisplayName,
    String? localAvatarUrl,
    required List<AiPlayerConfig> aiConfigs,
  }) {
    return [
      OpponentSplashParticipant(
        displayName: localDisplayName,
        isLocalPlayer: true,
        avatarUrl: localAvatarUrl,
      ),
      for (final c in aiConfigs)
        OpponentSplashParticipant(
          displayName: c.name,
          avatarColor: c.avatarColor,
          initials: c.initials,
          badgeLabel: c.personality.label,
        ),
    ];
  }

  static List<OpponentSplashParticipant> fromTournamentPlayers(
    List<TournamentPlayer> players, {
    required String localPlayerId,
    String? localAvatarUrl,
  }) {
    return [
      for (final p in players)
        OpponentSplashParticipant(
          displayName: p.displayName,
          isLocalPlayer: p.id == localPlayerId,
          avatarUrl: p.id == localPlayerId ? localAvatarUrl : null,
          avatarColor: p.aiConfig?.avatarColor,
          initials: p.aiConfig?.initials,
          badgeLabel: p.aiConfig?.personality.label,
        ),
    ];
  }

  static List<OpponentSplashParticipant> fromGameState(
    GameState gameState, {
    String? localPlayerId,
    String? localDisplayNameFallback,
    String? localAvatarUrl,
  }) {
    final resolvedLocalId =
        localPlayerId ?? resolveLocalPlayerId(gameState) ?? OfflineGameState.localId;

    return [
      for (final p in gameState.players)
        OpponentSplashParticipant(
          displayName: p.displayName.isNotEmpty
              ? p.displayName
              : (p.id == resolvedLocalId
                  ? (localDisplayNameFallback ?? 'You')
                  : 'Player'),
          isLocalPlayer: p.id == resolvedLocalId,
          avatarUrl: p.id == resolvedLocalId ? (p.avatarUrl ?? localAvatarUrl) : p.avatarUrl,
          avatarColor: p.isAi ? null : null,
          initials: p.isAi ? null : null,
        ),
    ];
  }

  static List<OpponentSplashParticipant> fromDisplayNames(
    List<String?> slotNames, {
    required int localSlotIndex,
    String? localAvatarUrl,
  }) {
    return [
      for (var i = 0; i < slotNames.length; i++)
        OpponentSplashParticipant(
          displayName: slotNames[i]?.isNotEmpty == true
              ? slotNames[i]!
              : 'Waiting…',
          isLocalPlayer: i == localSlotIndex,
          avatarUrl: i == localSlotIndex ? localAvatarUrl : null,
        ),
    ];
  }

  static List<OpponentSplashParticipant> fromRoundNames(
    List<String> names, {
    required String localDisplayName,
    String? localAvatarUrl,
  }) {
    return [
      for (final name in names)
        OpponentSplashParticipant(
          displayName: name,
          isLocalPlayer: name == localDisplayName,
          avatarUrl: name == localDisplayName ? localAvatarUrl : null,
        ),
    ];
  }

  static String? resolveLocalPlayerId(GameState gameState) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      for (final p in gameState.players) {
        if (p.firebaseUid == uid) return p.id;
      }
    }
    for (final p in gameState.players) {
      if (p.id == OfflineGameState.localId) return p.id;
    }
    return gameState.players.isNotEmpty ? gameState.players.first.id : null;
  }

  static PlayerModel? localPlayerIn(GameState gameState, {String? localPlayerId}) {
    final id = localPlayerId ?? resolveLocalPlayerId(gameState);
    if (id == null) return null;
    return gameState.players.where((p) => p.id == id).firstOrNull;
  }
}
