import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/network/game_event_handler.dart';
import 'package:last_cards/features/voice/ptt_controller.dart';
import 'package:last_cards/features/voice/voice_media_session.dart';
import 'package:last_cards/features/voice/voice_room_controller.dart';

import '../../helpers/fake_websocket_client.dart';

void main() {
  group('PttController', () {
    test('startTransmit begins countdown and stop clears', () {
      fakeAsync((async) {
        final ptt = PttController(maxSeconds: 10);
        expect(ptt.startTransmit(), isTrue);
        expect(ptt.isTransmitting, isTrue);
        expect(ptt.secondsRemaining, 10);
        async.elapse(const Duration(seconds: 3));
        expect(ptt.secondsRemaining, 7);
        ptt.stopTransmit();
        expect(ptt.isTransmitting, isFalse);
        expect(ptt.secondsRemaining, 0);
        ptt.dispose();
      });
    });

    test('auto-stops at maxSeconds and requires release before next', () {
      fakeAsync((async) {
        final ptt = PttController(maxSeconds: 10);
        expect(ptt.startTransmit(), isTrue);
        async.elapse(const Duration(seconds: 10));
        expect(ptt.isTransmitting, isFalse);
        expect(ptt.awaitingRelease, isTrue);
        expect(ptt.startTransmit(), isFalse);
        ptt.notifyPointerUp();
        expect(ptt.awaitingRelease, isFalse);
        expect(ptt.startTransmit(), isTrue);
        ptt.dispose();
      });
    });
  });

  group('VoiceRoomController settings gate', () {
    test('settings off disconnects media session', () async {
      final media = _RecordingMediaSession();
      final fakeWs = FakeWebSocketClient();
      final handler = GameEventHandler(fakeWs);
      final controller = VoiceRoomController(
        handler: handler,
        mediaSession: media,
        platformSupported: () => true,
      );

      await controller.sync(
        voiceSettingEnabled: true,
        roomCode: 'ABCD',
        localPlayerId: 'player-1',
      );
      expect(
        fakeWs.sentMessages.any((m) {
          final map = jsonDecode(m) as Map<String, dynamic>;
          return map['type'] == 'voice_token_request';
        }),
        isTrue,
      );

      fakeWs.injectServerMessage(jsonEncode({
        'type': 'voice_token',
        'url': 'wss://example.livekit.cloud',
        'token': 'tok',
        'roomName': 'lc-ABCD',
        'maxPttSeconds': 10,
        'canPublish': true,
      }));
      await Future<void>.delayed(Duration.zero);
      expect(media.connectCount, 1);
      expect(controller.isConnected, isTrue);
      expect(controller.shouldShowPtt, isTrue);

      await controller.sync(
        voiceSettingEnabled: false,
        roomCode: 'ABCD',
        localPlayerId: 'player-1',
      );
      expect(media.disconnectCount, greaterThanOrEqualTo(1));
      expect(controller.isConnected, isFalse);
      expect(controller.shouldShowPtt, isFalse);

      controller.dispose();
      handler.dispose();
    });
  });
}

class _RecordingMediaSession implements VoiceMediaSession {
  int connectCount = 0;
  int disconnectCount = 0;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Set<String>> get activeSpeakerIds => const Stream.empty();

  @override
  Future<void> connect({required String url, required String token}) async {
    connectCount++;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount++;
    _connected = false;
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> setParticipantMuted(String identity, bool muted) async {}
}
