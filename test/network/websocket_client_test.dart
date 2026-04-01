import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/network/websocket_client.dart';

import '../helpers/memory_websocket_channel.dart';

void main() {
  test('send returns false when not connected', () async {
    final client = WebSocketClient(uri: Uri.parse('ws://localhost:0'));
    expect(client.send('{}'), isFalse);
    await client.dispose();
  });

  test('disconnect sets state to disconnected', () async {
    final client = WebSocketClient(uri: Uri.parse('ws://localhost:0'));
    await client.disconnect();
    expect(client.connectionState.value, WsConnectionState.disconnected);
    await client.dispose();
  });

  test('factory connect succeeds and messages stream receives server strings',
      () async {
    late MemoryWebSocketChannel memory;
    final client = WebSocketClient(
      uri: Uri.parse('ws://fake'),
      channelFactory: (_) {
        memory = MemoryWebSocketChannel();
        return memory;
      },
    );

    await client.connect();
    expect(client.connectionState.value, WsConnectionState.connected);

    final next = client.messages.first;
    memory.pushFromServer('{"type":"ping"}');
    expect(await next, '{"type":"ping"}');

    await client.dispose();
  });

  test('send forwards payload when connected', () async {
    late MemoryWebSocketChannel memory;
    final client = WebSocketClient(
      uri: Uri.parse('ws://fake'),
      channelFactory: (_) {
        memory = MemoryWebSocketChannel();
        return memory;
      },
    );

    await client.connect();
    expect(client.send('ping'), isTrue);
    expect(memory.sentByClient, contains('ping'));

    await client.dispose();
  });

  test('server close sets disconnected', () async {
    late MemoryWebSocketChannel memory;
    final client = WebSocketClient(
      uri: Uri.parse('ws://fake'),
      channelFactory: (_) {
        memory = MemoryWebSocketChannel();
        return memory;
      },
    );

    await client.connect();
    memory.closeServerSide();
    await Future<void>.delayed(Duration.zero);
    expect(client.connectionState.value, WsConnectionState.disconnected);

    await client.dispose();
  });

  test('reconnectExhausted after repeated connection failures', () {
    // [_doConnect] rethrows after each failure; scheduled retries use the same
    // path — absorb those async errors so the test can assert final state.
    runZonedGuarded(() {
      fakeAsync((async) {
        var attempts = 0;
        final client = WebSocketClient(
          uri: Uri.parse('ws://fake'),
          channelFactory: (_) {
            attempts++;
            throw Exception('fail');
          },
        );

        client.connect().catchError((_) {});
        async.flushMicrotasks();
        // Backoff delays between attempts: 1s + 2s + 4s + 8s + 16s = 31s
        async.elapse(const Duration(seconds: 32));

        expect(client.reconnectExhausted.value, isTrue);
        expect(attempts, 6);
        client.dispose();
      });
    }, (error, stack) {});
  });

  test('disconnect aborts pending reconnect after failed connect', () {
    runZonedGuarded(() {
      fakeAsync((async) {
        var attempts = 0;
        final client = WebSocketClient(
          uri: Uri.parse('ws://fake'),
          channelFactory: (_) {
            attempts++;
            throw Exception('fail');
          },
        );

        client.connect().catchError((_) {});
        async.flushMicrotasks();
        client.disconnect();
        async.elapse(const Duration(seconds: 32));

        expect(client.reconnectExhausted.value, isFalse);
        expect(attempts, 1);
        client.dispose();
      });
    }, (error, stack) {});
  });

  test('onConnectedAfterReconnect fires after failure then success', () {
    runZonedGuarded(() {
      fakeAsync((async) {
        var calls = 0;
        var connectCount = 0;
        final client = WebSocketClient(
          uri: Uri.parse('ws://fake'),
          channelFactory: (_) {
            connectCount++;
            if (connectCount == 1) {
              throw Exception('fail');
            }
            return MemoryWebSocketChannel();
          },
        );
        client.onConnectedAfterReconnect = () => calls++;

        client.connect().catchError((_) {});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));

        expect(calls, 1);
        expect(client.connectionState.value, WsConnectionState.connected);
        client.dispose();
      });
    }, (error, stack) {});
  });
}
