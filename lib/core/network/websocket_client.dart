import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Creates a [WebSocketChannel] for [uri]. Defaults to [WebSocketChannel.connect].
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// Connection states for the WebSocket.
enum WsConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Low-level WebSocket wrapper with automatic reconnection.
///
/// - Connects to [uri] on [connect].
/// - Exposes [messages] stream of raw JSON strings.
/// - Auto-reconnects with exponential back-off on unexpected disconnection.
/// - Use [send] to transmit JSON actions to the server.
class WebSocketClient {
  WebSocketClient({Uri? uri, WebSocketChannelFactory? channelFactory})
      : _uri = uri ?? _defaultUri,
        _channelFactory = channelFactory ?? WebSocketChannel.connect;

  static Uri get _defaultUri => Uri.parse(
        const String.fromEnvironment(
          'WS_URL',
          defaultValue: 'wss://lastcards.up.railway.app/game',
        ),
      );

  Uri _uri;

  final WebSocketChannelFactory _channelFactory;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  final _messageController = StreamController<String>.broadcast();
  final _stateNotifier =
      ValueNotifier<WsConnectionState>(WsConnectionState.disconnected);

  /// Stream of raw JSON strings from the server.
  Stream<String> get messages => _messageController.stream;

  /// Observable connection state.
  ValueListenable<WsConnectionState> get connectionState => _stateNotifier;

  int _retryCount = 0;
  static const int _maxRetries = 5;
  bool _manualDisconnect = false;

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<void> connect({Uri? uri}) async {
    if (uri != null) _uri = uri;
    _manualDisconnect = false;
    _retryCount = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    // User called disconnect() — don't reconnect (e.g. delayed callback from
    // a previous _handleDisconnect).
    if (_manualDisconnect) return;

    _stateNotifier.value = _retryCount == 0
        ? WsConnectionState.connecting
        : WsConnectionState.reconnecting;

    try {
      _channel = _channelFactory(_uri);
      await _channel!.ready;

      _stateNotifier.value = WsConnectionState.connected;
      _retryCount = 0;

      _subscription = _channel!.stream.listen(
        (data) {
          if (data is String) _messageController.add(data);
        },
        onError: (Object err) {
          debugPrint('[WS] Error: $err');
          _handleDisconnect();
        },
        onDone: _handleDisconnect,
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _handleDisconnect();
      rethrow;
    }
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  /// Sends [jsonPayload] to the server.
  ///
  /// If the socket is not connected, does nothing (no-op) and logs a debug
  /// line — callers should not crash on transient disconnects.
  void send(String jsonPayload) {
    if (_stateNotifier.value != WsConnectionState.connected ||
        _channel == null) {
      debugPrint('[WS] send skipped — not connected');
      return;
    }
    _channel!.sink.add(jsonPayload);
  }

  // ── Disconnect handling ────────────────────────────────────────────────────

  void _handleDisconnect() {
    _stateNotifier.value = WsConnectionState.disconnected;
    _subscription?.cancel();
    _channel = null;

    if (_manualDisconnect) return;
    if (_retryCount >= _maxRetries) {
      debugPrint('[WS] Max retries reached. Giving up.');
      return;
    }

    _retryCount++;
    final delay = Duration(milliseconds: 500 * (1 << _retryCount));
    debugPrint('[WS] Reconnecting in ${delay.inMilliseconds}ms '
        '(attempt $_retryCount/$_maxRetries)');
    Future.delayed(delay, _doConnect);
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    _manualDisconnect = true;
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _stateNotifier.value = WsConnectionState.disconnected;
  }

  Future<void> dispose() async {
    await disconnect();
    _messageController.close();
    _stateNotifier.dispose();
  }
}
