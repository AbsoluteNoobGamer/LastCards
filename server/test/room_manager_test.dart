import 'dart:async';
import 'dart:convert';

import 'package:last_cards_server/room_manager.dart';
import 'package:test/test.dart';

// ── Fake WebSocket (stream + sink, like shelf WebSocket) ─────────────────────

class _FakeSink {
  final messages = <Map<String, dynamic>>[];

  void add(String json) =>
      messages.add(jsonDecode(json) as Map<String, dynamic>);
}

class FakeWs {
  final _sink = _FakeSink();
  final _controller = StreamController<String>();

  _FakeSink get sink => _sink;
  Stream<String> get stream => _controller.stream;

  List<Map<String, dynamic>> get messages => _sink.messages;

  void addIncoming(String jsonStr) {
    _controller.add(jsonStr);
  }

  Future<void> close() => _controller.close();

  Map<String, dynamic>? lastOfType(String type) {
    final list = messages.where((m) => m['type'] == type).toList();
    if (list.isEmpty) return null;
    return list.last;
  }
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  group('sanitizeDisplayName', () {
    test('trims and caps length at 20', () {
      expect(sanitizeDisplayName('  hello  '), 'hello');
      expect(sanitizeDisplayName('a' * 25), 'a' * 20);
    });

    test('strips HTML-like tags', () {
      expect(sanitizeDisplayName('<b>x</b>'), 'x');
    });

    test('removes disallowed characters', () {
      expect(sanitizeDisplayName(r'foo@#$bar'), 'foobar');
    });

    test('allows letters digits spaces hyphen underscore dot bang', () {
      expect(sanitizeDisplayName('A-z 0-9 _-.!'), 'A-z 0-9 _-.!');
    });

    test('empty becomes Player', () {
      expect(sanitizeDisplayName('   '), 'Player');
      expect(sanitizeDisplayName('@@@'), 'Player');
    });
  });

  group('RoomManager', () {
    test('create_room returns room_created with 6-char uppercase code', () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'create_room',
        'displayName': 'Host',
      }));
      await _flushAsync();

      final created = ws.lastOfType('room_created');
      expect(created, isNotNull);
      final code = created!['roomCode'] as String;
      expect(code.length, 6);
      expect(code, code.toUpperCase());
      expect(code, matches(RegExp(r'^[0-9A-F]{6}$')));
      expect(created['isPrivate'], isTrue);
      expect(created['playerId'], isNotEmpty);
    });

    test('join_room unknown code returns room_not_found', () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'join_room',
        'roomCode': 'ZZZZZZ',
        'displayName': 'Guest',
      }));
      await _flushAsync();

      final err = ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], 'room_not_found');
    });

    test('join_room after create_room succeeds', () async {
      final rm = RoomManager();
      final host = FakeWs();
      final guest = FakeWs();
      rm.handleConnection(host);
      host.addIncoming(jsonEncode({
        'type': 'create_room',
        'displayName': 'Host',
      }));
      await _flushAsync();

      final code = host.lastOfType('room_created')!['roomCode'] as String;

      rm.handleConnection(guest);
      guest.addIncoming(jsonEncode({
        'type': 'join_room',
        'roomCode': code,
        'displayName': 'Guest',
      }));
      await _flushAsync();

      final joined = guest.lastOfType('room_joined');
      expect(joined, isNotNull);
      expect(joined!['roomCode'], code);
      expect(joined['isPrivate'], isTrue);
    });

    test('quickplay sends queue update after each player joins queue', () async {
      final rm = RoomManager();
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);
      a.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 2,
        'displayName': 'P1',
      }));
      await _flushAsync();
      final qu = a.lastOfType('quickplay_queue_update');
      expect(qu, isNotNull);
      expect(qu!['displayNames'], ['P1']);
      expect(qu['yourIndex'], 0);
      expect(qu['playerCount'], 2);
      expect(b.messages.any((m) => m['type'] == 'quickplay_queue_update'), isFalse);

      b.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 2,
        'displayName': 'P2',
      }));
      await _flushAsync();
      expect(a.messages.any((m) => m['type'] == 'player_joined'), isTrue);
      expect(b.messages.any((m) => m['type'] == 'player_joined'), isTrue);
    });

    test('quickplay casual matches two players and sends roster', () async {
      final rm = RoomManager();
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);

      a.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 2,
        'displayName': 'P1',
      }));
      b.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 2,
        'displayName': 'P2',
      }));
      await _flushAsync();

      // Each addPlayer broadcasts player_joined; sendPlayerRosterTo replays full roster.
      final p1Joined = a.messages.where((m) => m['type'] == 'player_joined').length;
      final p2Joined = b.messages.where((m) => m['type'] == 'player_joined').length;
      expect(p1Joined, greaterThanOrEqualTo(2));
      expect(p2Joined, greaterThanOrEqualTo(2));

      expect(
        a.messages.any((m) => m['type'] == 'state_snapshot'),
        isTrue,
        reason: 'game should start after match',
      );
      expect(
        b.messages.any((m) => m['type'] == 'state_snapshot'),
        isTrue,
      );
    });

    test('quickplay ranked without verified uid returns auth_required', () async {
      final rm = RoomManager(
        verifyIdToken: (_) async => null,
      );
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'quickplay',
        'gameMode': 'ranked',
        'playerCount': 2,
        'displayName': 'R',
        'idToken': 'fake-token',
      }));
      await _flushAsync();

      final err = ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], 'auth_required');
    });

    test('quickplay ranked with uid can queue', () async {
      final rm = RoomManager(
        verifyIdToken: (_) async => 'firebase-u1',
      );
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);

      final qp = {
        'type': 'quickplay',
        'gameMode': 'ranked',
        'playerCount': 2,
        'displayName': 'R',
        'idToken': 't',
      };
      a.addIncoming(jsonEncode(qp));
      b.addIncoming(jsonEncode(qp));
      await _flushAsync();

      expect(a.messages.any((m) => m['type'] == 'error'), isFalse);
      expect(
        a.messages.where((m) => m['type'] == 'player_joined').length,
        greaterThanOrEqualTo(2),
      );
    });

    test('rejoin_session unknown room returns room_not_found', () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'rejoin_session',
        'roomCode': 'ABCDEF',
        'playerId': 'player-1',
      }));
      await _flushAsync();

      expect(ws.lastOfType('error')?['code'], 'room_not_found');
    });

    test('disconnect removes empty room so rejoin fails', () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'create_room',
        'displayName': 'Solo',
      }));
      await _flushAsync();

      final code = ws.lastOfType('room_created')!['roomCode'] as String;
      await ws.close();
      await _flushAsync();

      final ws2 = FakeWs();
      rm.handleConnection(ws2);
      ws2.addIncoming(jsonEncode({
        'type': 'join_room',
        'roomCode': code,
        'displayName': 'Late',
      }));
      await _flushAsync();

      expect(ws2.lastOfType('error')?['code'], 'room_not_found');
    });

    test('duplicate join_room from same socket does not add another roster entry',
        () async {
      final rm = RoomManager();
      final host = FakeWs();
      final guest = FakeWs();
      rm.handleConnection(host);
      host.addIncoming(jsonEncode({
        'type': 'create_room',
        'displayName': 'Host',
      }));
      await _flushAsync();
      final code = host.lastOfType('room_created')!['roomCode'] as String;

      rm.handleConnection(guest);
      guest.addIncoming(jsonEncode({
        'type': 'join_room',
        'roomCode': code,
        'displayName': 'Guest',
      }));
      await _flushAsync();

      final hostJoinBefore =
          host.messages.where((m) => m['type'] == 'player_joined').length;

      guest.addIncoming(jsonEncode({
        'type': 'join_room',
        'roomCode': code,
        'displayName': 'Guest',
      }));
      await _flushAsync();

      final hostJoinAfter =
          host.messages.where((m) => m['type'] == 'player_joined').length;
      expect(hostJoinAfter, hostJoinBefore);
    });

    test('disconnect removes player from quickplay queue', () async {
      final rm = RoomManager();
      final a = FakeWs();
      rm.handleConnection(a);
      a.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 4,
        'displayName': 'Lonely',
      }));
      await _flushAsync();

      await a.close();
      await _flushAsync();

      final b = FakeWs();
      final c = FakeWs();
      final d = FakeWs();
      rm.handleConnection(b);
      rm.handleConnection(c);
      rm.handleConnection(d);

      for (final w in [b, c, d]) {
        w.addIncoming(jsonEncode({
          'type': 'quickplay',
          'playerCount': 4,
          'displayName': 'P',
        }));
      }
      await _flushAsync();

      expect(b.messages.any((m) => m['type'] == 'player_joined'), isFalse);
    });
  });
}
