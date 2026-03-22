import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/network/game_event_handler.dart';
import 'package:last_cards/core/network/websocket_client.dart';
import 'package:last_cards/core/providers/connection_provider.dart';

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
}
