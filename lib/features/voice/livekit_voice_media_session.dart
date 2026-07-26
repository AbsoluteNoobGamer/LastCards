import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import 'voice_media_session.dart';

/// LiveKit-backed [VoiceMediaSession] (audio only).
class LiveKitVoiceMediaSession implements VoiceMediaSession {
  Room? _room;
  final _speakersController = StreamController<Set<String>>.broadcast();
  EventsListener<RoomEvent>? _listener;

  @override
  bool get isConnected => _room != null && _room!.connectionState == ConnectionState.connected;

  @override
  Stream<Set<String>> get activeSpeakerIds => _speakersController.stream;

  @override
  Future<void> connect({required String url, required String token}) async {
    await disconnect();
    final room = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(
          name: 'microphone',
        ),
      ),
    );
    _listener = room.createListener();
    _listener!
      ..on<ActiveSpeakersChangedEvent>((e) {
        final ids = e.speakers.map((p) => p.identity).toSet();
        if (!_speakersController.isClosed) {
          _speakersController.add(ids);
        }
      })
      ..on<TrackSubscribedEvent>((e) {
        // Ensure remote audio plays.
        if (e.track is RemoteAudioTrack) {
          unawaited((e.track as RemoteAudioTrack).start());
        }
      });

    await room.connect(url, token);
    // Join as listener; mic stays unpublished until PTT.
    await room.localParticipant?.setMicrophoneEnabled(false);
    _room = room;
  }

  @override
  Future<void> disconnect() async {
    final room = _room;
    _room = null;
    await _listener?.dispose();
    _listener = null;
    if (room != null) {
      try {
        await room.localParticipant?.setMicrophoneEnabled(false);
      } catch (e) {
        debugPrint('Voice mic disable on disconnect: $e');
      }
      await room.disconnect();
      await room.dispose();
    }
    if (!_speakersController.isClosed) {
      _speakersController.add(const {});
    }
  }

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {
    final room = _room;
    if (room == null) return;
    await room.localParticipant?.setMicrophoneEnabled(enabled);
  }

  @override
  Future<void> setParticipantMuted(String identity, bool muted) async {
    final room = _room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      if (participant.identity != identity) continue;
      for (final pub in participant.audioTrackPublications) {
        if (muted) {
          await pub.disable();
        } else {
          await pub.enable();
        }
      }
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _speakersController.close();
  }
}
