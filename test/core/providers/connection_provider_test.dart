import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:last_cards/core/network/websocket_client.dart';
import 'package:last_cards/core/providers/connection_provider.dart';

import '../helpers/network_mocks.mocks.dart';

class _TrackingConnectionState extends ValueNotifier<WsConnectionState> {
  _TrackingConnectionState(super.value);

  int listenerCount = 0;

  @override
  void addListener(VoidCallback listener) {
    listenerCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    listenerCount--;
    super.removeListener(listener);
  }
}

ProviderContainer _containerFor(MockWebSocketClient client) {
  return ProviderContainer(
    overrides: [wsClientProvider.overrideWithValue(client)],
  );
}

void main() {
  MockWebSocketClient mockClient({
    WsConnectionState initial = WsConnectionState.disconnected,
  }) {
    final client = MockWebSocketClient();
    final state = _TrackingConnectionState(initial);
    when(client.connectionState).thenReturn(state);
    return client;
  }

  _TrackingConnectionState connectionStateOf(MockWebSocketClient client) {
    return client.connectionState as _TrackingConnectionState;
  }

  test('emits initial connection state synchronously on first listen', () async {
    final client = mockClient();
    final container = _containerFor(client);
    addTearDown(container.dispose);

    container.listen(connectionStateProvider, (_, __) {}, fireImmediately: true);

    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      final async = container.read(connectionStateProvider);
      if (async.hasValue) {
        expect(async.requireValue, WsConnectionState.disconnected);
        return;
      }
    }
    fail('timeout waiting for initial connection state');
  });

  test('emits connected when WebSocketClient transitions to connected', () async {
    final client = mockClient();
    final connectionState = connectionStateOf(client);
    final container = _containerFor(client);
    addTearDown(container.dispose);

    final values = <WsConnectionState>[];
    container.listen(
      connectionStateProvider,
      (previous, next) {
        if (next.hasValue) values.add(next.requireValue);
      },
      fireImmediately: true,
    );

    connectionState.value = WsConnectionState.connected;
    await Future<void>.delayed(Duration.zero);

    expect(values, contains(WsConnectionState.disconnected));
    expect(values.last, WsConnectionState.connected);
  });

  test('emits disconnected when WebSocketClient transitions to disconnected',
      () async {
    final client = mockClient(initial: WsConnectionState.connected);
    final connectionState = connectionStateOf(client);
    final container = _containerFor(client);
    addTearDown(container.dispose);

    final values = <WsConnectionState>[];
    container.listen(
      connectionStateProvider,
      (previous, next) {
        if (next.hasValue) values.add(next.requireValue);
      },
      fireImmediately: true,
    );

    connectionState.value = WsConnectionState.disconnected;
    await Future<void>.delayed(Duration.zero);

    expect(values.last, WsConnectionState.disconnected);
  });

  test('dispose() removes listener and closes stream', () async {
    final client = mockClient();
    final connectionState = connectionStateOf(client);
    final container = _containerFor(client);

    final values = <WsConnectionState>[];
    final sub = container.listen(
      connectionStateProvider,
      (previous, next) {
        if (next.hasValue) values.add(next.requireValue);
      },
      fireImmediately: true,
    );

    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
      if (values.isNotEmpty) break;
    }
    expect(connectionState.listenerCount, 1);
    expect(values, contains(WsConnectionState.disconnected));

    sub.close();
    container.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(connectionState.listenerCount, 0);

    final countBefore = values.length;
    connectionState.value = WsConnectionState.connected;
    await Future<void>.delayed(Duration.zero);

    expect(values.length, countBefore);
  });
}
