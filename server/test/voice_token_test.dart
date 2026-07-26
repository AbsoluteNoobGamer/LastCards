import 'dart:convert';

import 'package:test/test.dart';

import 'package:last_cards_server/game_session.dart';
import 'package:last_cards_server/voice_token_service.dart';

class _FakeWs {
  final _sink = _FakeSink();
  _FakeSink get sink => _sink;
  List<Map<String, dynamic>> get messages => _sink.messages;
  Map<String, dynamic>? lastOfType(String type) {
    final matches = messages.where((m) => m['type'] == type).toList();
    return matches.isEmpty ? null : matches.last;
  }
}

class _FakeSink {
  final messages = <Map<String, dynamic>>[];
  void add(String json) {
    messages.add(jsonDecode(json) as Map<String, dynamic>);
  }
}

void main() {
  group('VoiceTokenService', () {
    test('isConfigured false when env missing', () {
      final svc = VoiceTokenService(apiKey: null, apiSecret: null, url: null);
      expect(svc.isConfigured, isFalse);
      expect(
        svc.mintToken(
          roomCode: 'ABCD',
          playerId: 'player-1',
          displayName: 'A',
          canPublish: true,
        ),
        isNull,
      );
    });

    test('mintToken includes room and canPublish false when muted', () {
      final svc = VoiceTokenService(
        apiKey: 'APItest',
        apiSecret: 'secretsecretsecretsecretsecret12',
        url: 'wss://example.livekit.cloud',
      );
      expect(svc.isConfigured, isTrue);
      final token = svc.mintToken(
        roomCode: 'ROOM1',
        playerId: 'player-1',
        displayName: 'Alex',
        canPublish: false,
      );
      expect(token, isNotNull);
      final payload = svc.verifyForTesting(token!);
      expect(payload, isNotNull);
      expect(payload!['name'], 'Alex');
      final video = payload['video'] as Map<String, dynamic>;
      expect(video['room'], 'lc-ROOM1');
      expect(video['roomJoin'], isTrue);
      expect(video['canPublish'], isFalse);
      expect(video['canSubscribe'], isTrue);
    });

    test('liveKitRoomName prefixes room code', () {
      expect(VoiceTokenService.liveKitRoomName('XYZ'), 'lc-XYZ');
      expect(VoiceTokenService.maxPttSeconds, 10);
    });
  });

  group('GameSession voice', () {
    test('voice_token_request returns voice_unavailable when not configured',
        () {
      final voice = VoiceTokenService(
        apiKey: '',
        apiSecret: '',
        url: '',
      );
      final session = GameSession('VTEST', voiceTokenService: voice);
      final ws = _FakeWs();
      final id = session.addPlayer(ws, 'P1');
      ws.messages.clear();
      session.handleVoiceTokenRequest(id);
      expect(ws.lastOfType('voice_unavailable'), isNotNull);
    });

    test('voice_token_request returns token with maxPttSeconds 10', () {
      final voice = VoiceTokenService(
        apiKey: 'APItest',
        apiSecret: 'secretsecretsecretsecretsecret12',
        url: 'wss://example.livekit.cloud',
      );
      final session = GameSession('VTEST', voiceTokenService: voice);
      final ws = _FakeWs();
      final id = session.addPlayer(ws, 'P1');
      ws.messages.clear();
      session.handleVoiceTokenRequest(id);
      final msg = ws.lastOfType('voice_token');
      expect(msg, isNotNull);
      expect(msg!['maxPttSeconds'], 10);
      expect(msg['url'], 'wss://example.livekit.cloud');
      expect(msg['roomName'], 'lc-VTEST');
      expect(msg['canPublish'], isTrue);
      expect((msg['token'] as String).isNotEmpty, isTrue);
    });

    test('host mute sets canPublish false on next token', () {
      final voice = VoiceTokenService(
        apiKey: 'APItest',
        apiSecret: 'secretsecretsecretsecretsecret12',
        url: 'wss://example.livekit.cloud',
      );
      final session = GameSession(
        'VTEST',
        isPrivate: true,
        voiceTokenService: voice,
      );
      final hostWs = _FakeWs();
      final targetWs = _FakeWs();
      final hostId = session.addPlayer(hostWs, 'Host');
      final targetId = session.addPlayer(targetWs, 'Target');
      expect(session.hostPlayerIdForPrivateLobby, hostId);

      session.handleVoiceMutePlayer(hostId, {
        'targetPlayerId': targetId,
        'muted': true,
      });
      expect(session.isVoiceMutedForTesting(targetId), isTrue);

      final mutedEvt = targetWs.lastOfType('voice_player_muted');
      expect(mutedEvt?['muted'], isTrue);

      final tokenMsg = targetWs.lastOfType('voice_token');
      expect(tokenMsg?['canPublish'], isFalse);
      final payload = voice.verifyForTesting(tokenMsg!['token'] as String)!;
      expect((payload['video'] as Map)['canPublish'], isFalse);
    });

    test('non-host cannot mute others', () {
      final voice = VoiceTokenService(
        apiKey: 'APItest',
        apiSecret: 'secretsecretsecretsecretsecret12',
        url: 'wss://example.livekit.cloud',
      );
      final session = GameSession(
        'VTEST',
        isPrivate: true,
        voiceTokenService: voice,
      );
      final hostWs = _FakeWs();
      final otherWs = _FakeWs();
      session.addPlayer(hostWs, 'Host');
      final otherId = session.addPlayer(otherWs, 'Other');
      otherWs.messages.clear();
      session.handleVoiceMutePlayer(otherId, {
        'targetPlayerId': session.hostPlayerIdForPrivateLobby,
        'muted': true,
      });
      expect(otherWs.lastOfType('error')?['code'], 'not_host');
      expect(
        session.isVoiceMutedForTesting(session.hostPlayerIdForPrivateLobby!),
        isFalse,
      );
    });
  });
}
