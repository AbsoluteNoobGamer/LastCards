// HTTP helpers for the same host as the game WS_URL (WebSocket path `/game`).

/// JSON stats endpoint on the game server ([GET /stats]).
///
/// Uses the same `--dart-define=WS_URL=...` as [WebSocketClient] (default
/// production Railway URL).
Uri gameServerStatsUri() => _gameServerHttpUri('/stats');

/// `POST` endpoint that sends a friend-room-invite push notification (the
/// invite itself is still written directly to Firestore by the caller —
/// this only triggers the FCM side-effect). Requires an `Authorization`
/// header of the form `Bearer (Firebase ID token)` identifying the sender.
Uri gameServerNotifyInviteUri() => _gameServerHttpUri('/notify-invite');

Uri _gameServerHttpUri(String path) {
  const wsUrl = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://lastcards.up.railway.app/game',
  );
  final ws = Uri.parse(wsUrl);
  final scheme = ws.scheme == 'wss'
      ? 'https'
      : ws.scheme == 'ws'
          ? 'http'
          : 'https';
  return Uri(
    scheme: scheme,
    host: ws.host,
    port: ws.hasPort ? ws.port : null,
    path: path,
  );
}
