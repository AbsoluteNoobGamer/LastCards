import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'firebase_auth_verifier.dart';
import 'game_session.dart';
import 'logger.dart';
import 'trophy_recorder.dart';

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
  RoomManager({
    Future<String?> Function(String idToken)? verifyIdToken,
  }) : _verifyIdToken =
            verifyIdToken ?? FirebaseAuthVerifier.instance.verifyToken;

  final Future<String?> Function(String idToken) _verifyIdToken;

  final _log = Logger('RoomManager');
  final _rooms = <String, GameSession>{};
  final _playerRooms = <dynamic, String>{};
  final _playerIds = <dynamic, String>{};
  final _playerUserIds = <dynamic, String>{};
  final _uuid = const Uuid();

  /// Quickplay matchmaking queues. Key: playerCount (int) for standard,
  /// 'bust' (String) for Bust mode (10 players), or 'ranked-N' for ranked.
  final _quickplayQueues = <Object, List<_QueuedPlayer>>{};

  /// Per-socket futures used to serialize async message handling.
  final _messageChains = <dynamic, Future<void>>{};

  void handleConnection(dynamic webSocket) {
    syncOnlineServerPresenceDelta(1);
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

    if ((type == 'create_room' ||
            type == 'join_room' ||
            type == 'quickplay' ||
            type == 'rejoin_session') &&
        json.containsKey('idToken')) {
      final token = json['idToken'] as String;
      final uid = await _verifyIdToken(token);
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
      case 'rejoin_session':
        await _rejoinSession(ws, json);
        break;
      case 'play_cards':
      case 'draw_card':
      case 'declare_joker':
      case 'end_turn':
      case 'suit_choice':
      case 'declare_last_cards':
        final roomCode = _playerRooms[ws];
        final playerId = _playerIds[ws];
        if (roomCode != null && playerId != null) {
          _rooms[roomCode]?.handleAction(playerId, json);
        }
        break;
      case 'quick_chat':
        final roomCode = _playerRooms[ws];
        final playerId = _playerIds[ws];
        if (roomCode != null && playerId != null) {
          _rooms[roomCode]?.handleQuickChat(playerId, json);
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
    final session = GameSession(
      roomCode,
      isPrivate: true,
      onBecameEmpty: (_) => _rooms.remove(roomCode),
    );
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

  Future<void> _rejoinSession(dynamic ws, Map<String, dynamic> json) async {
    final roomCode = (json['roomCode'] as String).toUpperCase();
    final playerId = json['playerId'] as String;
    final session = _rooms[roomCode];
    if (session == null) {
      ws.sink.add(jsonEncode({
        'type': 'error',
        'code': 'room_not_found',
        'message': 'Room $roomCode does not exist.',
      }));
      return;
    }
    final uid = _playerUserIds[ws];
    if (!session.tryReattachSocket(
      playerId,
      ws,
      firebaseUidFromToken: uid,
    )) {
      ws.sink.add(jsonEncode({
        'type': 'error',
        'code': 'rejoin_failed',
        'message':
            'Could not rejoin this game. It may have ended or the reconnect window expired.',
      }));
      return;
    }
    _playerRooms[ws] = roomCode;
    _playerIds[ws] = playerId;
    ws.sink.add(jsonEncode({
      'type': 'rejoin_ok',
      'roomCode': roomCode,
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

  int _targetPlayerCountForQueueKey(Object queueKey) {
    if (queueKey is int) return queueKey;
    if (queueKey == 'bust') return 10;
    if (queueKey is String && queueKey.startsWith('ranked-')) {
      return int.tryParse(queueKey.substring('ranked-'.length)) ?? 4;
    }
    return 4;
  }

  /// Notifies every socket in [queueKey]'s quickplay queue who is waiting.
  void _broadcastQuickplayQueueUpdate(Object queueKey) {
    final queue = _quickplayQueues[queueKey];
    if (queue == null || queue.isEmpty) return;

    final target = _targetPlayerCountForQueueKey(queueKey);
    final names = queue.map((q) => q.displayName).toList();
    for (var i = 0; i < queue.length; i++) {
      queue[i].ws.sink.add(jsonEncode({
        'type': 'quickplay_queue_update',
        'playerCount': target,
        'displayNames': names,
        'yourIndex': i,
      }));
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
      if (queue.isEmpty) {
        _quickplayQueues.remove(queueKey);
      } else {
        _broadcastQuickplayQueueUpdate(queueKey);
      }

      var roomCode = _uuid.v4().substring(0, 6).toUpperCase();
      while (_rooms.containsKey(roomCode)) {
        roomCode = _uuid.v4().substring(0, 6).toUpperCase();
      }
      final session = GameSession(
        roomCode,
        isPrivate: false,
        maxPlayerCount: playerCount,
        isBustMode: isBust,
        isRanked: isRanked,
        onBecameEmpty: (_) => _rooms.remove(roomCode),
      );
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
    } else {
      _broadcastQuickplayQueueUpdate(queueKey);
    }
  }

  void _onDisconnect(dynamic ws) {
    syncOnlineServerPresenceDelta(-1);
    _playerUserIds.remove(ws);
    // Remove from any quickplay queue.
    final emptyKeys = <Object>[];
    for (final entry in _quickplayQueues.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((q) => q.ws == ws);
      if (entry.value.length != before && entry.value.isNotEmpty) {
        _broadcastQuickplayQueueUpdate(entry.key);
      }
      if (entry.value.isEmpty) emptyKeys.add(entry.key);
    }
    for (final key in emptyKeys) {
      _quickplayQueues.remove(key);
    }

    final roomCode = _playerRooms.remove(ws);
    final playerId = _playerIds.remove(ws);
    if (roomCode != null && playerId != null) {
      final session = _rooms[roomCode];
      session?.handleSocketDisconnected(playerId, ws);

      // Clean up empty rooms only when the session has no players left.
      if (session != null && session.isEmpty) {
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
