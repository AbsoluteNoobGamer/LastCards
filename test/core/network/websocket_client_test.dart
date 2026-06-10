import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/network/websocket_client.dart';

import '../../helpers/memory_websocket_channel.dart';

void main() {
  group('WebSocketClient', () {
    test('connect() success sets connection state to connected', () async {
      final client = WebSocketClient(
        uri: Uri.parse('ws://fake'),
        channelFactory: (_) => MemoryWebSocketChannel(),
      );
      addTearDown(() => client.dispose());

      await client.connect();
      expect(client.connectionState.value, WsConnectionState.connected);
    });

    test('connect() failure transitions to reconnecting then disconnected',
        () {
      runZonedGuarded(() {
        fakeAsync((async) {
          var attempts = 0;
          final client = WebSocketClient(
            uri: Uri.parse('ws://fake'),
            channelFactory: (_) {
              attempts++;
              throw Exception('connection refused');
            },
          );
          addTearDown(() => client.dispose());

          final states = <WsConnectionState>[];
          client.connectionState.addListener(
            () => states.add(client.connectionState.value),
          );

          client.connect().catchError((_) {});
          async.flushMicrotasks();

          expect(states, contains(WsConnectionState.connecting));
          expect(client.connectionState.value, WsConnectionState.disconnected);

          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();

          expect(states, contains(WsConnectionState.reconnecting));
          expect(client.connectionState.value, isNot(WsConnectionState.connected));
          expect(attempts, greaterThan(1));
        });
      }, (error, stack) {});
    });

    test('exponential backoff increases retry delay with each attempt', () {
      runZonedGuarded(() {
        fakeAsync((async) {
          final attemptTimes = <int>[];
          var attempts = 0;
          final client = WebSocketClient(
            uri: Uri.parse('ws://fake'),
            channelFactory: (_) {
              attempts++;
              attemptTimes.add(async.elapsed.inMilliseconds);
              throw Exception('fail');
            },
          );
          addTearDown(() => client.dispose());

          client.connect().catchError((_) {});
          async.flushMicrotasks();

          // Delays between attempts: 1s, 2s, 4s, 8s, 16s
          async.elapse(const Duration(seconds: 32));
          async.flushMicrotasks();

          expect(attempts, 6);
          expect(attemptTimes.length, 6);
          for (var i = 1; i < attemptTimes.length; i++) {
            final gap = attemptTimes[i] - attemptTimes[i - 1];
            final expectedMs = 500 * (1 << i);
            expect(gap, expectedMs);
          }
        });
      }, (error, stack) {});
    });

    test('retries stop after max retry count is reached', () {
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
          addTearDown(() => client.dispose());

          client.connect().catchError((_) {});
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 32));

          expect(client.reconnectExhausted.value, isTrue);
          expect(attempts, 6);
        });
      }, (error, stack) {});
    });

    test('send() is a no-op when disconnected', () async {
      final client = WebSocketClient(uri: Uri.parse('ws://fake'));
      addTearDown(() => client.dispose());

      expect(() => client.send('{"type":"ping"}'), returnsNormally);
      expect(client.send('{"type":"ping"}'), isFalse);
    });

    test('disconnect() sets manual disconnect flag and stops reconnect attempts',
        () {
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
          addTearDown(() => client.dispose());

          client.connect().catchError((_) {});
          async.flushMicrotasks();
          client.disconnect();
          async.elapse(const Duration(seconds: 32));

          expect(client.connectionState.value, WsConnectionState.disconnected);
          expect(client.reconnectExhausted.value, isFalse);
          expect(attempts, 1);
        });
      }, (error, stack) {});
    });
  });
}
