# Voice chat (LiveKit)

Online push-to-talk uses **LiveKit** for media. The game WebSocket mints
short-lived join JWTs with `dart_jsonwebtoken` (same grant shape as LiveKit’s
server SDKs) and hosts mute publish rights.

## Railway / server env

| Variable | Example | Purpose |
| --- | --- | --- |
| `LIVEKIT_URL` | `wss://your-project.livekit.cloud` | Client connect URL |
| `LIVEKIT_API_KEY` | from LiveKit Cloud | JWT issuer |
| `LIVEKIT_API_SECRET` | from LiveKit Cloud | JWT signing secret |

If any variable is missing, `voice_token_request` returns `voice_unavailable`
and gameplay is unchanged.

## Protocol

- Client → `voice_token_request`
- Server → `voice_token` `{ url, token, roomName, maxPttSeconds: 10 }`  
  or `voice_unavailable` / `error`
- Client → `voice_mute_player` `{ targetPlayerId, muted }` (private host, or self)
- Server → `voice_player_muted` `{ playerId, muted, byPlayerId }`

LiveKit room name: `lc-{roomCode}`. Participant identity: game `playerId`.
