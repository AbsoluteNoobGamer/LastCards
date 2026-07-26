import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/block_provider.dart';
import '../../core/providers/connection_provider.dart';
import '../../core/providers/game_provider.dart';
import '../../core/providers/online_rejoin_provider.dart';
import '../settings/presentation/widgets/settings_modal.dart';
import 'voice_room_controller.dart';

/// Singleton voice controller for the app session.
final voiceRoomControllerProvider = Provider<VoiceRoomController>((ref) {
  final handler = ref.watch(gameEventHandlerProvider);
  final controller = VoiceRoomController(handler: handler);

  void sync() {
    final settings = ref.read(settingsProvider);
    final rejoin = ref.read(onlineRejoinProvider);
    final game = ref.read(gameStateProvider);
    final blocked = ref.read(blockedUidSetProvider).value ?? {};
    final idToUid = <String, String?>{
      if (game != null)
        for (final p in game.players) p.id: p.firebaseUid,
    };
    unawaited(
      controller.sync(
        voiceSettingEnabled: settings.voiceChatEnabled,
        roomCode: rejoin.roomCode,
        localPlayerId: rejoin.playerId,
        blockedUids: blocked,
        playerIdToFirebaseUid: idToUid,
      ),
    );
  }

  sync();
  ref.listen(settingsProvider, (_, __) => sync());
  ref.listen(onlineRejoinProvider, (_, __) => sync());
  ref.listen(gameStateProvider, (_, __) => sync());
  ref.listen(blockedUidSetProvider, (_, __) => sync());

  ref.onDispose(controller.dispose);
  return controller;
});
