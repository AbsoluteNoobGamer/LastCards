import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'game_session.dart';

class RoomManager {
  final _rooms = <String, GameSession>{};
  final _playerRooms = <dynamic, String>{};
  final _playerIds = <dynamic, String>{};
  final _uuid = const Uuid();

  void handleConnection(dynamic webSocket) {
    webSocket.stream.listen(
      (raw) => _onMessage(webSocket, raw as String),
      onDone: () => _onDisconnect(webSocket),
    );
  }

  void _onMessage(dynamic ws, String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final type = json['type'] as String;

    switch (type) {
      case 'create_room':
        _createRoom(ws, json);
        break;
      case 'join_room':
        _joinRoom(ws, json);
        break;
      case 'ready':
        _markReady(ws);
        break;
      case 'play_cards':
      case 'draw_card':
      case 'declare_joker':
      case 'end_turn':
      case 'suit_choice':
        final roomCode = _playerRooms[ws];
        final playerId = _playerIds[ws];
        if (roomCode != null && playerId != null) {
          _rooms[roomCode]?.handleAction(playerId, json);
        }
        break;
    }
  }

  void _createRoom(dynamic ws, Map<String, dynamic> json) {
    final roomCode = _uuid.v4().substring(0, 6).toUpperCase();
    final displayName = json['displayName'] as String? ?? 'Player';
    final session = GameSession(roomCode);
    _rooms[roomCode] = session;

    final playerId = session.addPlayer(ws, displayName);
    _playerRooms[ws] = roomCode;
    _playerIds[ws] = playerId;

    ws.sink.add(jsonEncode({
      'type': 'room_created',
      'roomCode': roomCode,
    }));
  }

  void _joinRoom(dynamic ws, Map<String, dynamic> json) {
    final code = (json['roomCode'] as String).toUpperCase();
    final displayName = json['displayName'] as String? ?? 'Player';
    final session = _rooms[code];

    if (session == null) {
      ws.sink.add(jsonEncode({
        'type': 'error',
        'code': 'room_not_found',
        'message': 'Room $code does not exist.',
      }));
      return;
    }

    final playerId = session.addPlayer(ws, displayName);
    _playerRooms[ws] = code;
    _playerIds[ws] = playerId;
  }

  void _markReady(dynamic ws) {
    final roomCode = _playerRooms[ws];
    final playerId = _playerIds[ws];
    if (roomCode != null && playerId != null) {
      _rooms[roomCode]?.markReady(playerId);
    }
  }

  void _onDisconnect(dynamic ws) {
    final roomCode = _playerRooms.remove(ws);
    final playerId = _playerIds.remove(ws);
    if (roomCode != null && playerId != null) {
      final session = _rooms[roomCode];
      session?.removePlayer(playerId);

      // Clean up empty rooms to prevent memory leaks on long-running servers.
      if (session != null &&
          !_playerRooms.containsValue(roomCode)) {
        _rooms.remove(roomCode);
      }
    }
  }
}
