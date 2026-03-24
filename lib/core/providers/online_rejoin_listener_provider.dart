import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_state.dart';
import 'auth_provider.dart';
import 'connection_provider.dart';
import 'game_provider.dart';
import 'online_rejoin_provider.dart';

/// Sends [rejoin_session] after an automatic reconnect while a live game exists.
Future<void> sendRejoinSessionIfNeeded(Ref ref) async {
  final client = ref.read(wsClientProvider);
  final creds = ref.read(onlineRejoinProvider);
  final roomCode = creds.roomCode;
  final playerId = creds.playerId;
  if (roomCode == null || playerId == null) return;
  final gs = ref.read(gameNotifierProvider).gameState;
  if (gs == null || gs.phase != GamePhase.playing) return;

  final token = await ref.read(authServiceProvider).getIdToken();
  final ok = client.send(jsonEncode({
    'type': 'rejoin_session',
    'roomCode': roomCode,
    'playerId': playerId,
    if (token != null) 'idToken': token,
  }));
  if (!ok) {
    ref.read(gameNotifierProvider.notifier).connectionSendFailed();
  }
}

/// Wires [WebSocketClient.onConnectedAfterReconnect] for session rejoin.
final onlineRejoinListenerProvider = Provider<Object?>((ref) {
  final client = ref.watch(wsClientProvider);
  void onReconnect() {
    unawaited(sendRejoinSessionIfNeeded(ref));
  }
  client.onConnectedAfterReconnect = onReconnect;
  ref.onDispose(() {
    if (client.onConnectedAfterReconnect == onReconnect) {
      client.onConnectedAfterReconnect = null;
    }
  });
  return null;
});
