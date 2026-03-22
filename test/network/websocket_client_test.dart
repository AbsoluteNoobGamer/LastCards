import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:last_cards/core/network/websocket_client.dart';

/// In-memory [WebSocketChannel]: [pushFromServer] feeds the client [stream];
/// client [sink] sends to [sentByClient].
class MemoryWebSocketChannel extends StreamChannelMixin implements WebSocketChannel {
  MemoryWebSocketChannel()
      : _controller = StreamChannelController<String>(sync: true) {
    _readyCompleter.complete();
    _controller.local.stream.listen(
      sentByClient.add,
      onDone: () {},
      onError: (_) {},
    );
  }

  final StreamChannelController<String> _controller;
  final _readyCompleter = Completer<void>();
  final List<String> sentByClient = [];

  @override
  Future<void> get ready => _readyCompleter.future;

  @override
  Stream get stream => _controller.foreign.stream;

  @override
  WebSocketSink get sink => _MemoryWebSocketSink(_controller.foreign.sink);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  void pushFromServer(String data) => _controller.local.sink.add(data);

  void closeServerSide() => _controller.local.sink.close();
}

class _MemoryWebSocketSink extends DelegatingStreamSink implements WebSocketSink {
  _MemoryWebSocketSink(super.inner);

  @override
  Future close([int? closeCode, String? closeReason]) => super.close();
}

void main() {
  test('send is a no-op when not connected', () async {
    final client = WebSocketClient(uri: Uri.parse('ws://localhost:0'));
    expect(() => client.send('{}'), returnsNormally);
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
    client.send('ping');
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
}
