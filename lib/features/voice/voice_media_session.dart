/// Abstraction over LiveKit (or fakes in tests) for room audio.
abstract class VoiceMediaSession {
  Future<void> connect({required String url, required String token});

  Future<void> disconnect();

  Future<void> setMicrophoneEnabled(bool enabled);

  /// Participant identities currently speaking (LiveKit active speakers).
  Stream<Set<String>> get activeSpeakerIds;

  Future<void> setParticipantMuted(String identity, bool muted);

  bool get isConnected;
}

/// No-op session used when voice is off or platform unsupported.
class NullVoiceMediaSession implements VoiceMediaSession {
  @override
  bool get isConnected => false;

  @override
  Stream<Set<String>> get activeSpeakerIds => const Stream.empty();

  @override
  Future<void> connect({required String url, required String token}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> setMicrophoneEnabled(bool enabled) async {}

  @override
  Future<void> setParticipantMuted(String identity, bool muted) async {}
}
