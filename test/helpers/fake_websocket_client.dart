import 'dart:async';

import 'package:last_cards/core/network/websocket_client.dart';

/// Test double with a controllable [messages] stream and recorded [sentMessages].
class FakeWebSocketClient extends WebSocketClient {
  FakeWebSocketClient() : super(uri: Uri.parse('ws://fake'));

  final _controller = StreamController<String>.broadcast();
  final List<String> sentMessages = [];

  @override
  Stream<String> get messages => _controller.stream;

  void injectServerMessage(String json) => _controller.add(json);

  @override
  void send(String jsonPayload) => sentMessages.add(jsonPayload);

  @override
  Future<void> dispose() async {
    await _controller.close();
    await super.dispose();
  }
}
