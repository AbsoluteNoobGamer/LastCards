// HTTP helpers for the same host as the game WS_URL (WebSocket path `/game`).

/// JSON stats endpoint on the game server ([GET /stats]).
///
/// Uses the same `--dart-define=WS_URL=...` as [WebSocketClient] (default
/// production Railway URL).
Uri gameServerStatsUri() {
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
    path: '/stats',
  );
}
