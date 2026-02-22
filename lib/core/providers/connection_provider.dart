import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/game_event_handler.dart';
import '../network/websocket_client.dart';

// ── WebSocket client ─────────────────────────────────────────────────────────

/// Singleton WebSocket client. Override in tests with [ProviderScope] overrides.
final wsClientProvider = Provider<WebSocketClient>((ref) {
  final client = WebSocketClient();
  ref.onDispose(client.dispose);
  return client;
});

// ── Connection state ──────────────────────────────────────────────────────────

final connectionStateProvider = StreamProvider<WsConnectionState>((ref) {
  final client = ref.watch(wsClientProvider);
  final controller = StreamController<WsConnectionState>();

  void listener() {
    if (!controller.isClosed) {
      controller.add(client.connectionState.value);
    }
  }

  client.connectionState.addListener(listener);
  // Emit initial value immediately
  controller.add(client.connectionState.value);

  ref.onDispose(() {
    client.connectionState.removeListener(listener);
    controller.close();
  });

  return controller.stream;
});

// ── Event handler ─────────────────────────────────────────────────────────────

final gameEventHandlerProvider = Provider<GameEventHandler>((ref) {
  final client = ref.watch(wsClientProvider);
  final handler = GameEventHandler(client);
  ref.onDispose(handler.dispose);
  return handler;
});
