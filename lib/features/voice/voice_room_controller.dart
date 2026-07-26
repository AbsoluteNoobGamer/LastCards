import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/models/game_event.dart';
import '../../core/network/game_event_handler.dart';
import 'livekit_voice_media_session.dart';
import 'ptt_controller.dart';
import 'voice_media_session.dart';

/// Coordinates LiveKit connect/PTT for an online room when voice settings allow.
class VoiceRoomController extends ChangeNotifier {
  VoiceRoomController({
    required GameEventHandler handler,
    VoiceMediaSession? mediaSession,
    PttController? ptt,
    bool Function()? platformSupported,
  })  : _handler = handler,
        _media = mediaSession ??
            (kIsWeb ? NullVoiceMediaSession() : LiveKitVoiceMediaSession()),
        ptt = ptt ?? PttController(),
        _platformSupported = platformSupported ?? _defaultPlatformSupported {
    _tokenSub = _handler.voiceTokens.listen(_onVoiceToken);
    _unavailableSub = _handler.voiceUnavailable.listen((_) {
      _serverAvailable = false;
      _connecting = false;
      notifyListeners();
    });
    _mutedSub = _handler.voicePlayerMuted.listen((e) {
      if (e.muted) {
        _serverMutedIds.add(e.playerId);
      } else {
        _serverMutedIds.remove(e.playerId);
      }
      notifyListeners();
    });
    this.ptt.addListener(_onPttChanged);
  }

  static bool _defaultPlatformSupported() => !kIsWeb;

  final GameEventHandler _handler;
  final VoiceMediaSession _media;
  final bool Function() _platformSupported;
  final PttController ptt;

  StreamSubscription<VoiceTokenEvent>? _tokenSub;
  StreamSubscription<VoiceUnavailableEvent>? _unavailableSub;
  StreamSubscription<VoicePlayerMutedEvent>? _mutedSub;
  StreamSubscription<Set<String>>? _speakersSub;

  bool _voiceSettingEnabled = false;
  String? _roomCode;
  String? _localPlayerId;
  Set<String> _blockedUids = {};
  Map<String, String?> _playerIdToFirebaseUid = {};

  bool _serverAvailable = true;
  bool _connecting = false;
  bool _connected = false;
  bool _canPublish = true;
  final Set<String> _localMutedIds = {};
  final Set<String> _serverMutedIds = {};
  Set<String> _speakingIds = {};

  bool get isPlatformSupported => _platformSupported();
  bool get isConnected => _connected;
  bool get isConnecting => _connecting;
  bool get serverAvailable => _serverAvailable;
  bool get canPublish => _canPublish;
  bool get shouldShowPtt =>
      _voiceSettingEnabled &&
      isPlatformSupported &&
      _roomCode != null &&
      _localPlayerId != null &&
      _serverAvailable;
  Set<String> get speakingIds => _speakingIds;
  Set<String> get localMutedIds => Set.unmodifiable(_localMutedIds);
  bool isLocallyMuted(String playerId) => _localMutedIds.contains(playerId);

  /// Update settings / session binding. Connects or disconnects as needed.
  Future<void> sync({
    required bool voiceSettingEnabled,
    String? roomCode,
    String? localPlayerId,
    Set<String> blockedUids = const {},
    Map<String, String?> playerIdToFirebaseUid = const {},
  }) async {
    _voiceSettingEnabled = voiceSettingEnabled;
    _roomCode = roomCode;
    _localPlayerId = localPlayerId;
    _blockedUids = blockedUids;
    _playerIdToFirebaseUid = playerIdToFirebaseUid;

    final wantConnect = voiceSettingEnabled &&
        isPlatformSupported &&
        roomCode != null &&
        localPlayerId != null;

    if (!wantConnect) {
      await _teardown();
      notifyListeners();
      return;
    }

    await _applyBlockMutes();
    if (!_connected && !_connecting) {
      _requestToken();
    }
    notifyListeners();
  }

  void _requestToken() {
    _connecting = true;
    _serverAvailable = true;
    notifyListeners();
    _handler.sendVoiceTokenRequest();
  }

  Future<void> _onVoiceToken(VoiceTokenEvent e) async {
    if (!_voiceSettingEnabled || _roomCode == null) return;
    if (e.url.isEmpty || e.token.isEmpty) {
      _serverAvailable = false;
      _connecting = false;
      notifyListeners();
      return;
    }
    _canPublish = e.canPublish;
    try {
      await _media.connect(url: e.url, token: e.token);
      await _speakersSub?.cancel();
      _speakersSub = _media.activeSpeakerIds.listen((ids) {
        _speakingIds = ids;
        notifyListeners();
      });
      _connected = true;
      _connecting = false;
      await _applyBlockMutes();
      for (final id in _localMutedIds) {
        await _media.setParticipantMuted(id, true);
      }
    } catch (err) {
      debugPrint('Voice connect failed: $err');
      _connected = false;
      _connecting = false;
      _serverAvailable = false;
    }
    notifyListeners();
  }

  Future<void> _teardown() async {
    if (ptt.isTransmitting) {
      ptt.stopTransmit();
    }
    await _speakersSub?.cancel();
    _speakersSub = null;
    if (_media.isConnected) {
      await _media.setMicrophoneEnabled(false);
      await _media.disconnect();
    }
    _connected = false;
    _connecting = false;
    _speakingIds = {};
  }

  Future<void> onPttPointerDown() async {
    if (!shouldShowPtt || !_connected || !_canPublish) return;
    if (!ptt.startTransmit()) return;
    try {
      await _media.setMicrophoneEnabled(true);
    } catch (e) {
      debugPrint('Mic enable failed: $e');
      ptt.stopTransmit();
    }
  }

  Future<void> onPttPointerUp() async {
    final wasTransmitting = ptt.isTransmitting;
    ptt.notifyPointerUp();
    if (wasTransmitting || _media.isConnected) {
      try {
        await _media.setMicrophoneEnabled(false);
      } catch (e) {
        debugPrint('Mic disable failed: $e');
      }
    }
  }

  void _onPttChanged() {
    if (!ptt.isTransmitting && _media.isConnected) {
      unawaited(_media.setMicrophoneEnabled(false));
    }
    notifyListeners();
  }

  Future<void> setLocalMute(String playerId, bool muted) async {
    if (muted) {
      _localMutedIds.add(playerId);
    } else {
      _localMutedIds.remove(playerId);
    }
    await _media.setParticipantMuted(playerId, muted);
    notifyListeners();
  }

  void requestServerMute(String targetPlayerId, bool muted) {
    _handler.sendVoiceMutePlayer(
      VoiceMutePlayerAction(targetPlayerId: targetPlayerId, muted: muted),
    );
  }

  Future<void> _applyBlockMutes() async {
    for (final entry in _playerIdToFirebaseUid.entries) {
      final uid = entry.value;
      if (uid != null && _blockedUids.contains(uid)) {
        _localMutedIds.add(entry.key);
        await _media.setParticipantMuted(entry.key, true);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_teardown());
    _tokenSub?.cancel();
    _unavailableSub?.cancel();
    _mutedSub?.cancel();
    ptt.removeListener(_onPttChanged);
    ptt.dispose();
    final media = _media;
    if (media is LiveKitVoiceMediaSession) {
      unawaited(media.dispose());
    }
    super.dispose();
  }
}
