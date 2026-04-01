import 'dart:async';

import 'package:async/async.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
