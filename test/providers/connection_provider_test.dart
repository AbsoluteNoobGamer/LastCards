import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/network/game_event_handler.dart';
import 'package:last_cards/core/network/websocket_client.dart';
import 'package:last_cards/core/providers/connection_provider.dart';

import '../helpers/memory_websocket_channel.dart';

void main() {
  test('connectionStateProvider emits initial disconnected state', () async {
    final fakeClient = WebSocketClient(uri: Uri.parse('ws://fake'));
    final container = ProviderContainer(
      overrides: [wsClientProvider.overrideWithValue(fakeClient)],
    );
    addTearDown(() async {
      container.dispose();
      await fakeClient.dispose();
    });

    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      final async = container.read(connectionStateProvider);
      if (async.hasValue) {
        expect(async.requireValue, WsConnectionState.disconnected);
        return;
      }
    }
    fail('timeout waiting for connection state');
  });

  test('connectionStateProvider emits connected after WebSocket connect', () async {
    final client = WebSocketClient(
      uri: Uri.parse('ws://fake'),
      channelFactory: (_) => MemoryWebSocketChannel(),
    );
    final container = ProviderContainer(
      overrides: [wsClientProvider.overrideWithValue(client)],
    );
    addTearDown(() async {
      container.dispose();
      await client.dispose();
    });

    // Subscribe before connect so stream emissions from the ValueNotifier are not missed.
    final sub = container.listen(
      connectionStateProvider,
      (_, __) {},
      fireImmediately: true,
    );

    await client.connect();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
      final async = container.read(connectionStateProvider);
      if (async.hasValue && async.requireValue == WsConnectionState.connected) {
        sub.close();
        return;
      }
    }
    sub.close();
    fail('timeout waiting for connected state');
  });

  test('gameEventHandlerProvider creates handler from wsClient', () {
    final fakeClient = WebSocketClient(uri: Uri.parse('ws://fake'));
    final container = ProviderContainer(
      overrides: [wsClientProvider.overrideWithValue(fakeClient)],
    );
    addTearDown(() async {
      container.dispose();
      await fakeClient.dispose();
    });

    final handler = container.read(gameEventHandlerProvider);
    expect(handler, isNotNull);
    expect(handler, isA<GameEventHandler>());
  });

  test('connectionStateProvider disposes cleanly after subscribe + connect',
      () async {
    final client = WebSocketClient(
      uri: Uri.parse('ws://fake'),
      channelFactory: (_) => MemoryWebSocketChannel(),
    );
    final container = ProviderContainer(
      overrides: [wsClientProvider.overrideWithValue(client)],
    );

    final sub = container.listen(
      connectionStateProvider,
      (_, __) {},
      fireImmediately: true,
    );

    await client.connect();
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
      final async = container.read(connectionStateProvider);
      if (async.hasValue && async.requireValue == WsConnectionState.connected) {
        break;
      }
    }

    sub.close();
    container.dispose();
    await client.disconnect();
    await client.dispose();
  });
}
