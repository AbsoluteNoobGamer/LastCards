import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'firebase_auth_verifier.dart';
import 'game_session.dart';
import 'logger.dart';

/// Sanitizes a display name: trims whitespace, limits to 20 characters,
/// and strips HTML/special characters.
String sanitizeDisplayName(String raw) {
  var name = raw.trim();
  // Strip HTML tags and angle brackets.
  name = name.replaceAll(RegExp(r'<[^>]*>'), '');
  // Remove remaining special/control characters (keep letters, digits,
  // spaces, hyphens, underscores, and common punctuation).
  name = name.replaceAll(RegExp(r'[^\w\s\-\.!]'), '');
  if (name.length > 20) name = name.substring(0, 20);
  if (name.isEmpty) name = 'Player';
  return name;
}

class RoomManager {
  final _log = Logger('RoomManager');
  final _rooms = <String, GameSession>{};
  final _playerRooms = <dynamic, String>{};
  final _playerIds = <dynamic, String>{};
  final _playerUserIds = <dynamic, String>{};
  final _uuid = const Uuid();

  /// Quickplay matchmaking queues. Key: playerCount (int) for standard,
  /// 'bust' (String) for Bust mode (10 players).
  final _quickplayQueues = <Object, List<_QueuedPlayer>>{};

  /// Per-socket futures used to serialize async message handling.
  final _messageChains = <dynamic, Future<void>>{};

  void handleConnection(dynamic webSocket) {
    _messageChains[webSocket] = Future.value();
    webSocket.stream.listen(
      (raw) {
        _messageChains[webSocket] = _messageChains[webSocket]!
            .then((_) => _onMessage(webSocket, raw as String))
            .catchError((e) {
          Logger('RoomManager').error('Error handling message: $e');
        });
      },
      onDone: () {
        final pending = _messageChains.remove(webSocket);
        (pending ?? Future.value()).whenComplete(() => _onDisconnect(webSocket));
      },
    );
  }

  Future<void> _onMessage(dynamic ws, String raw) async {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final type = json['type'] as String;

    if ((type == 'create_room' || type == 'join_room' || type == 'quickplay') &&
        json.containsKey('idToken')) {
      final token = json['idToken'] as String;
      final uid = await FirebaseAuthVerifier.instance.verifyToken(token);
      if (uid != null) {
        _playerUserIds[ws] = uid;
      }
      // If uid is null (API key not set or token invalid), proceed without
      // a firebase UID — trophies will fall back to session-scoped player IDs.
    }

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
    var roomCode = _uuid.v4().substring(0, 6).toUpperCase();
    while (_rooms.containsKey(roomCode)) {
      roomCode = _uuid.v4().substring(0, 6).toUpperCase();
    }
    final displayName =
        sanitizeDisplayName(json['displayName'] as String? ?? 'Player');
    final firebaseUid = _playerUserIds[ws];
    final session = GameSession(roomCode, isPrivate: true);
    _rooms[roomCode] = session;

    final playerId = session.addPlayer(ws, displayName, firebaseUid: firebaseUid);
    _playerRooms[ws] = roomCode;
    _playerIds[ws] = playerId;

    ws.sink.add(jsonEncode({
      'type': 'room_created',
      'roomCode': roomCode,
      'playerId': playerId,
      'isPrivate': true,
    }));
  }

  void _joinRoom(dynamic ws, Map<String, dynamic> json) {
    final code = (json['roomCode'] as String).toUpperCase();
    final displayName =
        sanitizeDisplayName(json['displayName'] as String? ?? 'Player');
    final session = _rooms[code];

    if (session == null) {
      ws.sink.add(jsonEncode({
        'type': 'error',
        'code': 'room_not_found',
        'message': 'Room $code does not exist.',
      }));
      return;
    }

    final firebaseUid = _playerUserIds[ws];
    final playerId = session.addPlayer(ws, displayName, firebaseUid: firebaseUid);
    if (playerId.isEmpty) return; // rejected (room full or game started)
    _playerRooms[ws] = code;
    _playerIds[ws] = playerId;

    ws.sink.add(jsonEncode({
      'type': 'room_joined',
      'roomCode': code,
      'playerId': playerId,
      'isPrivate': session.isPrivate,
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
    final gameMode = json['gameMode'] as String?;
    final isBust = gameMode == 'bust';
    final isRanked = gameMode == 'ranked';
    final playerCount = isBust ? 10 : (json['playerCount'] as int? ?? 4);
    final displayName =
        sanitizeDisplayName(json['displayName'] as String? ?? 'Player');
    final firebaseUid = _playerUserIds[ws];

    // Ranked games require a verified Firebase identity.
    if (isRanked && firebaseUid == null) {
      ws.sink.add(jsonEncode({
        'type': 'error',
        'code': 'auth_required',
        'message': 'Sign in is required for ranked games.',
      }));
      return;
    }

    // Each mode uses an isolated queue so ranked players only match each other.
    final Object queueKey;
    if (isBust) {
      queueKey = 'bust';
    } else if (isRanked) {
      queueKey = 'ranked-$playerCount';
    } else {
      queueKey = playerCount;
    }
    _log.info(
        'Player "$displayName" queued for $playerCount-player '
        '${isBust ? "Bust" : isRanked ? "Ranked" : ""} match');

    final queue = _quickplayQueues.putIfAbsent(queueKey, () => []);

    // Prevent duplicate entries for the same websocket.
    queue.removeWhere((q) => q.ws == ws);
    queue.add(_QueuedPlayer(ws: ws, displayName: displayName, firebaseUid: firebaseUid));

    _log.info('Queue($queueKey) size: ${queue.length}/$playerCount');

    if (queue.length >= playerCount) {
      final matched = queue.sublist(0, playerCount);
      queue.removeRange(0, playerCount);

      var roomCode = _uuid.v4().substring(0, 6).toUpperCase();
      while (_rooms.containsKey(roomCode)) {
        roomCode = _uuid.v4().substring(0, 6).toUpperCase();
      }
      final session = GameSession(roomCode,
          isPrivate: false,
          maxPlayerCount: playerCount,
          isBustMode: isBust,
          isRanked: isRanked);
      _rooms[roomCode] = session;
      _log.info(
          'Match found! Creating room $roomCode with $playerCount players');

      // First pass: add all players to the session.
      final playerIds = <String>[];
      for (final qp in matched) {
        final playerId = session.addPlayer(qp.ws, qp.displayName, firebaseUid: qp.firebaseUid);
        playerIds.add(playerId);
        _playerRooms[qp.ws] = roomCode;
        _playerIds[qp.ws] = playerId;
        _log.info(
            'Added "${qp.displayName}" ($playerId) to room $roomCode');
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

      _log.info(
          'All players readied — game should start in room $roomCode');
    }
  }

  void _onDisconnect(dynamic ws) {
    _playerUserIds.remove(ws);
    // Remove from any quickplay queue.
    final emptyKeys = <Object>[];
    for (final entry in _quickplayQueues.entries) {
      entry.value.removeWhere((q) => q.ws == ws);
      if (entry.value.isEmpty) emptyKeys.add(entry.key);
    }
    for (final key in emptyKeys) {
      _quickplayQueues.remove(key);
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
  _QueuedPlayer({required this.ws, required this.displayName, this.firebaseUid});
  final dynamic ws;
  final String displayName;
  final String? firebaseUid;
}
