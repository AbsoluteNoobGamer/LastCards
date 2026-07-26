import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Mints LiveKit participant JWTs for in-room push-to-talk voice.
///
/// Configure with `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, and `LIVEKIT_URL`.
/// When unset, [isConfigured] is false and the game server skips voice.
class VoiceTokenService {
  VoiceTokenService({
    String? apiKey,
    String? apiSecret,
    String? url,
  })  : apiKey = apiKey ?? Platform.environment['LIVEKIT_API_KEY'],
        apiSecret = apiSecret ?? Platform.environment['LIVEKIT_API_SECRET'],
        url = url ?? Platform.environment['LIVEKIT_URL'];

  factory VoiceTokenService.fromEnvironment() => VoiceTokenService();

  final String? apiKey;
  final String? apiSecret;
  final String? url;

  /// Hard client/server PTT transmit cap (seconds).
  static const int maxPttSeconds = 10;

  /// LiveKit room name for a game [roomCode].
  static String liveKitRoomName(String roomCode) => 'lc-$roomCode';

  bool get isConfigured =>
      (apiKey?.isNotEmpty ?? false) &&
      (apiSecret?.isNotEmpty ?? false) &&
      (url?.isNotEmpty ?? false);

  /// Returns a signed access token, or null if voice is not configured.
  String? mintToken({
    required String roomCode,
    required String playerId,
    required String displayName,
    required bool canPublish,
    Duration ttl = const Duration(hours: 1),
  }) {
    if (!isConfigured) return null;

    final videoGrant = <String, dynamic>{
      'roomJoin': true,
      'room': liveKitRoomName(roomCode),
      'canPublish': canPublish,
      'canSubscribe': true,
      'canPublishData': false,
    };

    final jwt = JWT(
      {
        'name': displayName,
        'video': videoGrant,
      },
      issuer: apiKey,
      subject: playerId,
    );

    return jwt.sign(
      SecretKey(apiSecret!),
      expiresIn: ttl,
    );
  }

  /// Decodes a token minted by [mintToken] (for tests).
  Map<String, dynamic>? verifyForTesting(String token) {
    if (!isConfigured) return null;
    try {
      final jwt = JWT.verify(token, SecretKey(apiSecret!), issuer: apiKey);
      return Map<String, dynamic>.from(jwt.payload as Map);
    } on JWTException {
      return null;
    }
  }
}
