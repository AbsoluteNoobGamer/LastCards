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

/// FCM HTTP v1 `messages:send` request body for a topic broadcast — every
/// device subscribed to [topic] (client calls `subscribeToTopic` on launch)
/// receives it, with no per-user Firestore write (there's no single `uid` a
/// broadcast belongs to).
Map<String, dynamic> buildFcmTopicMessagePayload({
  required String topic,
  required String title,
  required String body,
}) {
  return {
    'message': {
      'topic': topic,
      'notification': {'title': title, 'body': body},
    },
  };
}

/// Reads a Firestore REST `fields` map (as returned by `GET .../documents/...`)
/// back into a plain Dart map. Only handles the value types this server
/// actually reads (`stringValue`, `arrayValue` of `stringValue`s) — extend if
/// a future caller needs more.
Map<String, dynamic> parseFirestoreFields(Map<String, dynamic> fields) {
  final result = <String, dynamic>{};
  for (final entry in fields.entries) {
    final value = entry.value as Map<String, dynamic>;
    if (value.containsKey('stringValue')) {
      result[entry.key] = value['stringValue'] as String?;
    } else if (value.containsKey('integerValue')) {
      result[entry.key] = int.tryParse(value['integerValue'] as String? ?? '');
    } else if (value.containsKey('arrayValue')) {
      final values = (value['arrayValue'] as Map<String, dynamic>?)?['values']
              as List<dynamic>? ??
          const [];
      result[entry.key] = values
          .map((v) => (v as Map<String, dynamic>)['stringValue'] as String?)
          .whereType<String>()
          .toList();
    }
  }
  return result;
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
/// Wired sends: [notifyTopic] broadcasts a new-app-version announcement
/// (topic `app_updates`, polled periodically in `bin/main.dart`) and a
/// "someone is searching for players" announcement (topic
/// `matchmaking_open`, fired from `RoomManager._handleQuickplay` on queue
/// join). [notify] (per-user, targeted) powers the `/notify-invite` HTTP
/// route for friend room invites — [GameSession] turn/disconnect events are
/// not wired up yet; that's still a product decision left to a future caller.
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

  /// Pushes to every token in [fcmTokens] (from `users/{uid}.fcmTokens` —
  /// see `FirestoreProfileService.addFcmToken` on the client), and — unless
  /// [writeInboxDoc] is `false` — also writes the in-app inbox doc for
  /// [uid]. Pass `writeInboxDoc: false` when the event already has its own
  /// dedicated Firestore-backed inbox (e.g. friend room invites use
  /// `users/{uid}/gameInvites`; writing a second, generic inbox entry for
  /// the same event would just be a duplicate notification in the UI).
  /// Safe to call with an empty token list (writes only the inbox doc, if
  /// any). No-op if credentials aren't configured.
  Future<void> notify({
    required String uid,
    required List<String> fcmTokens,
    required String type,
    required String title,
    required String body,
    bool writeInboxDoc = true,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return;

    await Future.wait([
      if (writeInboxDoc)
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

  /// Broadcasts to every device subscribed to [topic] — no per-user
  /// targeting, no inbox write (there's no single recipient to write one
  /// for). No-op if credentials aren't configured.
  Future<void> notifyTopic({
    required String topic,
    required String title,
    required String body,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return;
    await _sendTopicPush(accessToken: token, topic: topic, title: title, body: body);
  }

  /// Reads `users/{uid}.fcmTokens` (registered device push tokens). Returns
  /// an empty list if the doc/field is missing, credentials aren't
  /// configured, or the request fails — callers should treat that the same
  /// as "no devices to push to" rather than an error.
  Future<List<String>> getUserFcmTokens(String uid) async {
    final token = await _getAccessToken();
    if (token == null) return const [];

    final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents/users/$uid');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return const [];
      final doc = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = doc['fields'] as Map<String, dynamic>?;
      if (fields == null) return const [];
      final parsed = parseFirestoreFields(fields);
      final tokens = parsed['fcmTokens'];
      return tokens is List<String> ? tokens : const [];
    } catch (e) {
      _log.error('Error reading fcmTokens for $uid: $e');
      return const [];
    }
  }

  /// Reads a top-level Firestore document's fields (e.g. `app_config/app_update`).
  /// Returns null if missing, unconfigured, or the request fails.
  Future<Map<String, dynamic>?> getDocumentFields({
    required String collection,
    required String docId,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    final url = Uri.parse('https://firestore.googleapis.com/v1/projects/$_projectId'
        '/databases/(default)/documents/$collection/$docId');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode != 200) return null;
      final doc = jsonDecode(response.body) as Map<String, dynamic>;
      final fields = doc['fields'] as Map<String, dynamic>?;
      if (fields == null) return null;
      return parseFirestoreFields(fields);
    } catch (e) {
      _log.error('Error reading $collection/$docId: $e');
      return null;
    }
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

  Future<void> _sendTopicPush({
    required String accessToken,
    required String topic,
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
        body: jsonEncode(buildFcmTopicMessagePayload(topic: topic, title: title, body: body)),
      );
      if (response.statusCode != 200) {
        _log.error('FCM topic send failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      _log.error('Error sending FCM topic push: $e');
    }
  }
}
