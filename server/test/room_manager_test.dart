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
  group('sanitizeAvatarCosmeticId', () {
    test('accepts catalog-style slugs', () {
      expect(sanitizeAvatarCosmeticId('default_chip'), 'default_chip');
      expect(sanitizeAvatarCosmeticId('title_combo_king'), 'title_combo_king');
    });

    test('rejects use_photo sentinel and unsafe values', () {
      expect(sanitizeAvatarCosmeticId('use_photo'), isNull);
      expect(sanitizeAvatarCosmeticId(''), isNull);
      expect(sanitizeAvatarCosmeticId('../x'), isNull);
      expect(sanitizeAvatarCosmeticId('Bad-Id'), isNull);
      expect(sanitizeAvatarCosmeticId(null), isNull);
      expect(sanitizeAvatarCosmeticId(12), isNull);
    });
  });

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
      expect(created['isHardcore'], isFalse);
      expect(created['gameVariant'], 'standard');
    });

    test('create_room with isHardcore echoes in room_created', () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'create_room',
        'displayName': 'Host',
        'isHardcore': true,
      }));
      await _flushAsync();

      final created = ws.lastOfType('room_created');
      expect(created!['isHardcore'], isTrue);
    });

    test('create_room with gameVariant bust', () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'create_room',
        'displayName': 'Host',
        'gameVariant': 'bust',
      }));
      await _flushAsync();

      final created = ws.lastOfType('room_created');
      expect(created!['gameVariant'], 'bust');
    });

    test('create_room with gameVariant knockout', () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'create_room',
        'displayName': 'Host',
        'gameVariant': 'knockout',
      }));
      await _flushAsync();

      final created = ws.lastOfType('room_created');
      expect(created!['gameVariant'], 'knockout');
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
      expect(joined['isHardcore'], isFalse);
      expect(joined['gameVariant'], 'standard');

      // Roster replay so the guest learns about players who joined earlier.
      final rosterIds = guest.messages
          .where((m) => m['type'] == 'player_joined')
          .map((m) => (m['player'] as Map<String, dynamic>)['id'] as String)
          .toSet();
      expect(rosterIds, containsAll(['player-1', 'player-2']));
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

    test('quickplay casual matches two players and opens tournament vote',
        () async {
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
        a.messages.any((m) => m['type'] == 'tournament_vote_open'),
        isTrue,
        reason: 'public casual should vote before deal',
      );
      expect(
        a.messages.any((m) => m['type'] == 'state_snapshot'),
        isFalse,
        reason: 'deal waits for tournament vote',
      );

      a.addIncoming(jsonEncode({
        'type': 'vote_tournament',
        'wantTournament': true,
      }));
      b.addIncoming(jsonEncode({
        'type': 'vote_tournament',
        'wantTournament': true,
      }));
      await _flushAsync();

      final result = a.lastOfType('tournament_vote_result');
      expect(result, isNotNull);
      expect(result!['isKnockoutTournament'], isTrue);
      expect(
        a.messages.any((m) => m['type'] == 'state_snapshot'),
        isTrue,
        reason: 'game starts after vote resolves',
      );
      expect(
        a.lastOfType('session_config')?['isKnockoutTournament'],
        isTrue,
      );
    });

    test('quickplay casual tournament vote majority no stays standard',
        () async {
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

      a.addIncoming(jsonEncode({
        'type': 'vote_tournament',
        'wantTournament': false,
      }));
      b.addIncoming(jsonEncode({
        'type': 'vote_tournament',
        'wantTournament': true,
      }));
      await _flushAsync();

      // Tie → standard (not knockout).
      expect(
        a.lastOfType('tournament_vote_result')?['isKnockoutTournament'],
        isFalse,
      );
      expect(
        a.lastOfType('session_config')?['isKnockoutTournament'],
        isFalse,
      );
    });

    test('quickplay ranked skips tournament vote and starts immediately',
        () async {
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
      b.addIncoming(jsonEncode({...qp, 'displayName': 'R2'}));
      await _flushAsync();

      expect(
        a.messages.any((m) => m['type'] == 'tournament_vote_open'),
        isFalse,
      );
      expect(
        a.messages.any((m) => m['type'] == 'state_snapshot'),
        isTrue,
      );
    });

    test('full quickplay table sends final quickplay_queue_update to every player',
        () async {
      final rm = RoomManager();
      final sockets = List.generate(3, (_) => FakeWs());
      for (final w in sockets) {
        rm.handleConnection(w);
      }
      for (var i = 0; i < 3; i++) {
        sockets[i].addIncoming(jsonEncode({
          'type': 'quickplay',
          'playerCount': 3,
          'displayName': 'P${i + 1}',
        }));
        await _flushAsync();
      }
      for (final w in sockets) {
        final qs = w.messages
            .where((m) => m['type'] == 'quickplay_queue_update')
            .toList();
        expect(qs, isNotEmpty);
        final last = qs.last;
        expect(last['playerCount'], 3);
        expect((last['displayNames'] as List).length, 3);
      }
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

    test('quickplay ranked_hardcore with uid can queue', () async {
      final rm = RoomManager(
        verifyIdToken: (_) async => 'firebase-u1',
      );
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);

      final qp = {
        'type': 'quickplay',
        'gameMode': 'ranked_hardcore',
        'playerCount': 2,
        'displayName': 'H',
        'idToken': 't',
      };
      a.addIncoming(jsonEncode(qp));
      b.addIncoming(jsonEncode(qp));
      await _flushAsync();

      expect(a.messages.any((m) => m['type'] == 'error'), isFalse);
      final cfgs = a.messages.where((m) => m['type'] == 'session_config').toList();
      expect(cfgs, isNotEmpty);
      final cfg = cfgs.last;
      expect(cfg['isHardcore'], isTrue);
      expect(cfg['isRanked'], isTrue);
    });

    test('quickplay joinWaitingQueue joins existing casual queue', () async {
      final rm = RoomManager();
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);

      a.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 3,
        'displayName': 'P1',
      }));
      await _flushAsync();

      b.addIncoming(jsonEncode({
        'type': 'quickplay',
        'joinWaitingQueue': true,
        'displayName': 'P2',
      }));
      await _flushAsync();

      final qu = b.lastOfType('quickplay_queue_update');
      expect(qu, isNotNull);
      expect(qu!['playerCount'], 3);
      expect((qu['displayNames'] as List).length, 2);
    });

    test('quickplay joinWaitingQueue accepts numeric 1 as true', () async {
      final rm = RoomManager();
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);
      a.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 3,
        'displayName': 'P1',
      }));
      await _flushAsync();
      b.addIncoming(jsonEncode({
        'type': 'quickplay',
        'joinWaitingQueue': 1,
        'displayName': 'P2',
      }));
      await _flushAsync();
      final qu = b.lastOfType('quickplay_queue_update');
      expect(qu!['playerCount'], 3);
    });

    test('quickplay joinWaitingQueue with no waiters returns no_waiting_tables',
        () async {
      final rm = RoomManager();
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'quickplay',
        'joinWaitingQueue': true,
        'displayName': 'P',
      }));
      await _flushAsync();

      final err = ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], 'no_waiting_tables');
    });

    test('quickplay ranked joinWaitingQueue without uid returns auth_required',
        () async {
      final rm = RoomManager(
        verifyIdToken: (_) async => null,
      );
      final ws = FakeWs();
      rm.handleConnection(ws);
      ws.addIncoming(jsonEncode({
        'type': 'quickplay',
        'gameMode': 'ranked',
        'joinWaitingQueue': true,
        'displayName': 'R',
        'idToken': 'fake-token',
      }));
      await _flushAsync();

      final err = ws.lastOfType('error');
      expect(err, isNotNull);
      expect(err!['code'], 'auth_required');
    });

    test('quickplay ranked joinWaitingQueue joins existing ranked queue', () async {
      final rm = RoomManager(
        verifyIdToken: (_) async => 'firebase-u1',
      );
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);

      a.addIncoming(jsonEncode({
        'type': 'quickplay',
        'gameMode': 'ranked',
        'playerCount': 3,
        'displayName': 'R1',
        'idToken': 't',
      }));
      await _flushAsync();

      b.addIncoming(jsonEncode({
        'type': 'quickplay',
        'gameMode': 'ranked',
        'joinWaitingQueue': true,
        'displayName': 'R2',
        'idToken': 't',
      }));
      await _flushAsync();

      final qu = b.lastOfType('quickplay_queue_update');
      expect(qu, isNotNull);
      expect(qu!['playerCount'], 3);
      expect((qu['displayNames'] as List).length, 2);
    });

    test('quickplay ranked_hardcore joinWaitingQueue joins existing queue',
        () async {
      final rm = RoomManager(
        verifyIdToken: (_) async => 'firebase-u1',
      );
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      rm.handleConnection(b);

      a.addIncoming(jsonEncode({
        'type': 'quickplay',
        'gameMode': 'ranked_hardcore',
        'playerCount': 3,
        'displayName': 'H1',
        'idToken': 't',
      }));
      await _flushAsync();

      b.addIncoming(jsonEncode({
        'type': 'quickplay',
        'gameMode': 'ranked_hardcore',
        'joinWaitingQueue': true,
        'displayName': 'H2',
        'idToken': 't',
      }));
      await _flushAsync();

      final qu = b.lastOfType('quickplay_queue_update');
      expect(qu, isNotNull);
      expect(qu!['playerCount'], 3);
      expect((qu['displayNames'] as List).length, 2);
    });

    test('joinWaitingQueue prefers more-filled table when tie on waiter count',
        () async {
      final rm = RoomManager();
      final q3 = FakeWs();
      final q4 = FakeWs();
      final joiner = FakeWs();
      rm.handleConnection(q3);
      rm.handleConnection(q4);
      rm.handleConnection(joiner);
      q3.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 3,
        'displayName': 'T3',
      }));
      q4.addIncoming(jsonEncode({
        'type': 'quickplay',
        'playerCount': 4,
        'displayName': 'T4',
      }));
      await _flushAsync();
      joiner.addIncoming(jsonEncode({
        'type': 'quickplay',
        'joinWaitingQueue': true,
        'displayName': 'Join',
      }));
      await _flushAsync();
      final qu = joiner.lastOfType('quickplay_queue_update');
      expect(qu, isNotNull);
      expect(qu!['playerCount'], 3);
      expect((qu['displayNames'] as List).length, 2);
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

    test('openWebSocketCount tracks connect and disconnect', () async {
      final rm = RoomManager();
      expect(rm.openWebSocketCount, 0);
      final a = FakeWs();
      final b = FakeWs();
      rm.handleConnection(a);
      expect(rm.openWebSocketCount, 1);
      rm.handleConnection(b);
      expect(rm.openWebSocketCount, 2);
      await a.close();
      await _flushAsync();
      expect(rm.openWebSocketCount, 1);
      await b.close();
      await _flushAsync();
      expect(rm.openWebSocketCount, 0);
    });

    test('set_private_lobby_rules from host updates everyone', () async {
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

      host.addIncoming(jsonEncode({
        'type': 'set_private_lobby_rules',
        'isHardcore': true,
      }));
      await _flushAsync();

      Map<String, dynamic>? lastSettings(List<Map<String, dynamic>> msgs) {
        final list =
            msgs.where((m) => m['type'] == 'private_lobby_settings').toList();
        if (list.isEmpty) return null;
        return list.last;
      }

      expect(lastSettings(host.messages)?['isHardcore'], isTrue);
      expect(lastSettings(guest.messages)?['isHardcore'], isTrue);
    });

    test('start_game from host starts with 2+ players; guest gets not_host',
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

      guest.addIncoming(jsonEncode({'type': 'start_game'}));
      await _flushAsync();
      expect(guest.lastOfType('error')?['code'], 'not_host');

      host.addIncoming(jsonEncode({'type': 'start_game'}));
      await _flushAsync();
      expect(
        host.messages.any((m) => m['type'] == 'state_snapshot'),
        isTrue,
      );
    });
  });
}
