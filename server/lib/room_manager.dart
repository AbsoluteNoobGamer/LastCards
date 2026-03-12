import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'game_session.dart';

class RoomManager {
  final _rooms = <String, GameSession>{};
  final _playerRooms = <dynamic, String>{};
  final _playerIds = <dynamic, String>{};
  final _uuid = const Uuid();

  /// Quickplay matchmaking queues keyed by desired player count.
  final _quickplayQueues = <int, List<_QueuedPlayer>>{};

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
      case 'quickplay':
        _handleQuickplay(ws, json);
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
      'playerId': playerId,
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
    if (playerId.isEmpty) return; // rejected (room full or game started)
    _playerRooms[ws] = code;
    _playerIds[ws] = playerId;

    ws.sink.add(jsonEncode({
      'type': 'room_joined',
      'roomCode': code,
      'playerId': playerId,
    }));
  }

  void _markReady(dynamic ws) {
    final roomCode = _playerRooms[ws];
    final playerId = _playerIds[ws];
    if (roomCode != null && playerId != null) {
      _rooms[roomCode]?.markReady(playerId);
    }
  }

  void _handleQuickplay(dynamic ws, Map<String, dynamic> json) {
    final playerCount = json['playerCount'] as int? ?? 4;
    final displayName = json['displayName'] as String? ?? 'Player';
    print(
        '[Quickplay] Player "$displayName" queued for $playerCount-player match');

    final queue = _quickplayQueues.putIfAbsent(playerCount, () => []);

    // Prevent duplicate entries for the same websocket.
    queue.removeWhere((q) => q.ws == ws);
    queue.add(_QueuedPlayer(ws: ws, displayName: displayName));

    print('[Quickplay] Queue($playerCount) size: ${queue.length}/$playerCount');

    if (queue.length >= playerCount) {
      final matched = queue.sublist(0, playerCount);
      queue.removeRange(0, playerCount);

      final roomCode = _uuid.v4().substring(0, 6).toUpperCase();
      final session = GameSession(roomCode);
      _rooms[roomCode] = session;
      print(
          '[Quickplay] Match found! Creating room $roomCode with $playerCount players');

      // First pass: add all players to the session.
      final playerIds = <String>[];
      for (final qp in matched) {
        final playerId = session.addPlayer(qp.ws, qp.displayName);
        playerIds.add(playerId);
        _playerRooms[qp.ws] = roomCode;
        _playerIds[qp.ws] = playerId;
        print(
            '[Quickplay] Added "${qp.displayName}" ($playerId) to room $roomCode');
      }

      // Send catch-up roster so every client knows about all players.
      for (final qp in matched) {
        session.sendPlayerRosterTo(qp.ws);
      }

      // Second pass: mark all players ready so _startGame fires only after
      // every player is in the session.
      for (final playerId in playerIds) {
        session.markReady(playerId);
      }

      print(
          '[Quickplay] All players readied — game should start in room $roomCode');
    }
  }

  void _onDisconnect(dynamic ws) {
    // Remove from any quickplay queue.
    for (final queue in _quickplayQueues.values) {
      queue.removeWhere((q) => q.ws == ws);
    }

    final roomCode = _playerRooms.remove(ws);
    final playerId = _playerIds.remove(ws);
    if (roomCode != null && playerId != null) {
      final session = _rooms[roomCode];
      session?.removePlayer(playerId);

      // Clean up empty rooms to prevent memory leaks on long-running servers.
      if (session != null && !_playerRooms.containsValue(roomCode)) {
        _rooms.remove(roomCode);
      }
    }
  }
}

/// A player waiting in the quickplay matchmaking queue.
class _QueuedPlayer {
  _QueuedPlayer({required this.ws, required this.displayName});
  final dynamic ws;
  final String displayName;
}
