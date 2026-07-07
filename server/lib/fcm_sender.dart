import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'logger.dart';

/// Firestore field encoding for a new `users/{uid}/notifications/{id}` doc.
/// Split out from [FcmSender._writeInboxDoc] so the payload shape is
/// unit-testable without a network call — see `firestore.rules` for the
/// client-visible read/update contract this must satisfy.
Map<String, dynamic> buildNotificationDocFields({
  required String type,
  required String title,
  required String body,
  DateTime? now,
}) {
  return {
    'type': {'stringValue': type},
    'title': {'stringValue': title},
    'body': {'stringValue': body},
    'read': {'booleanValue': false},
    'createdAt': {'timestampValue': (now ?? DateTime.now()).toUtc().toIso8601String()},
  };
}

/// FCM HTTP v1 `messages:send` request body for a single device token.
Map<String, dynamic> buildFcmMessagePayload({
  required String deviceToken,
  required String title,
  required String body,
}) {
  return {
    'message': {
      'token': deviceToken,
      'notification': {'title': title, 'body': body},
    },
  };
}

/// Sends push notifications (FCM) and writes the matching in-app inbox entry
/// to Firestore. The two together are how a server-triggered event (e.g.
/// "it's your turn", "you were challenged") reaches a player whether the app
/// is foregrounded, backgrounded, or fully closed — the Firestore doc is the
/// source of truth for [NotificationInboxScreen] on the client; the FCM push
/// is just what wakes up the OS tray when the app isn't in the foreground.
///
/// Uses the SAME service account as [TrophyRecorder]/ranked-stat writes (env
/// var `GOOGLE_CREDENTIALS_JSON` — see that class's doc comment for the
/// expected JSON shape). That key's project must additionally have the
/// **Firebase Cloud Messaging API (V1)** enabled (GCP Console → APIs &
/// Services → Library) — it is a separate opt-in from Firestore access.
///
/// If credentials are absent or the API isn't enabled, calls are silently
/// skipped/logged rather than throwing (mirrors the rest of this server's
/// "degrade gracefully, never crash a game session over an analytics/side
/// write" convention).
///
/// **Not yet wired into [GameSession]** — deciding exactly which turn/game
/// events should trigger a push (every turn regardless of connection state?
/// only after the player has been disconnected for N seconds? only ranked
/// games?) is a product decision left to the caller. [notify] is the call to
/// make once that's decided, e.g. from the disconnect-handling path around
/// `GameSession._trophyRecorder.recordLeavePenalty` call sites.
class FcmSender {
  FcmSender._();

  static final FcmSender instance = FcmSender._();

  final _log = Logger('FcmSender');
  final _uuid = const Uuid();

  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
    'https://www.googleapis.com/auth/datastore',
  ];

  String? _projectId;
  String? _clientEmail;
  String? _privateKeyPem;

  String? _cachedToken;
  DateTime? _tokenExpiry;

  bool _initCalled = false;

  /// Initialises credentials from the `GOOGLE_CREDENTIALS_JSON` env var.
  void init() {
    if (_initCalled) return;
    _initCalled = true;
    final raw = Platform.environment['GOOGLE_CREDENTIALS_JSON'];
    if (raw == null || raw.isEmpty) {
      _log.info('GOOGLE_CREDENTIALS_JSON not set — push notifications are disabled.');
      return;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _projectId = json['project_id'] as String?;
      _clientEmail = json['client_email'] as String?;
      _privateKeyPem = json['private_key'] as String?;
      _log.info('FcmSender credentials loaded for project "$_projectId".');
    } catch (e) {
      _log.error('Failed to parse GOOGLE_CREDENTIALS_JSON: $e');
    }
  }

  bool get _configured =>
      _projectId != null && _clientEmail != null && _privateKeyPem != null;

  Future<String?> _getAccessToken() async {
    if (!_configured) return null;

    final expiry = _tokenExpiry;
    if (_cachedToken != null &&
        expiry != null &&
        DateTime.now().isBefore(expiry.subtract(const Duration(seconds: 60)))) {
      return _cachedToken;
    }

    try {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = JWT(
        {
          'iss': _clientEmail,
          'scope': _scopes.join(' '),
          'aud': _tokenUrl,
          'iat': now,
          'exp': now + 3600,
        },
        issuer: _clientEmail,
      );
      final signed = payload.sign(
        RSAPrivateKey(_privateKeyPem!),
        algorithm: JWTAlgorithm.RS256,
      );

      final response = await http.post(
        Uri.parse(_tokenUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': signed,
        },
      );

      if (response.statusCode != 200) {
        _log.error(
            'Failed to obtain access token: ${response.statusCode} ${response.body}');
        return null;
      }
      final tokenJson = jsonDecode(response.body) as Map<String, dynamic>;
      _cachedToken = tokenJson['access_token'] as String?;
      final expiresIn = (tokenJson['expires_in'] as num?)?.toInt() ?? 3600;
      _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
      return _cachedToken;
    } catch (e) {
      _log.error('Error obtaining access token: $e');
      return null;
    }
  }

  /// Writes the in-app inbox doc for [uid] and pushes to every token in
  /// [fcmTokens] (from `users/{uid}.fcmTokens` — see
  /// `FirestoreProfileService.addFcmToken` on the client). Safe to call with
  /// an empty token list (writes only the inbox doc, no push). No-op if
  /// credentials aren't configured.
  Future<void> notify({
    required String uid,
    required List<String> fcmTokens,
    required String type,
    required String title,
    required String body,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return;

    await Future.wait([
      _writeInboxDoc(accessToken: token, uid: uid, type: type, title: title, body: body),
      ...fcmTokens.map(
        (deviceToken) => _sendPush(
          accessToken: token,
          deviceToken: deviceToken,
          title: title,
          body: body,
        ),
      ),
    ]);
  }

  Future<void> _writeInboxDoc({
    required String accessToken,
    required String uid,
    required String type,
    required String title,
    required String body,
  }) async {
    final id = _uuid.v4();
    final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents/users/$uid/notifications?documentId=$id');
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'fields': buildNotificationDocFields(type: type, title: title, body: body)}),
      );
      if (response.statusCode != 200) {
        _log.error(
            'Failed to write notification doc (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Error writing notification doc: $e');
    }
  }

  Future<void> _sendPush({
    required String accessToken,
    required String deviceToken,
    required String title,
    required String body,
  }) async {
    final url =
        Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(buildFcmMessagePayload(deviceToken: deviceToken, title: title, body: body)),
      );
      if (response.statusCode != 200) {
        _log.error('FCM send failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Error sending FCM push: $e');
    }
  }
}
