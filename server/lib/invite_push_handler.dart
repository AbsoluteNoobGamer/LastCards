import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;

import 'fcm_sender.dart';
import 'firebase_auth_verifier.dart';
import 'logger.dart';

/// Parsed, validated `/notify-invite` request body.
class InvitePushRequest {
  const InvitePushRequest({
    required this.toUid,
    required this.fromDisplayName,
    required this.roomCode,
  });

  final String toUid;
  final String fromDisplayName;
  final String roomCode;

  /// Returns null if any required field is missing/empty.
  static InvitePushRequest? fromJson(Map<String, dynamic> json) {
    final toUid = json['toUid'] as String?;
    final fromDisplayName = json['fromDisplayName'] as String?;
    final roomCode = json['roomCode'] as String?;
    if (toUid == null || toUid.isEmpty) return null;
    if (fromDisplayName == null || fromDisplayName.isEmpty) return null;
    if (roomCode == null || roomCode.isEmpty) return null;
    return InvitePushRequest(
      toUid: toUid,
      fromDisplayName: fromDisplayName,
      roomCode: roomCode,
    );
  }
}

/// Handles `POST /notify-invite`: verifies the caller's Firebase ID token
/// (`Authorization: Bearer <idToken>`), looks up the recipient's registered
/// push tokens, and sends a push — no duplicate inbox write, since
/// `users/{toUid}/gameInvites` (written directly by the client via the
/// Firestore SDK, unchanged by this endpoint) is already that event's
/// dedicated Firestore-backed inbox; see [FcmSender.notify]'s
/// `writeInboxDoc` doc comment.
///
/// This endpoint is purely the push side-effect. If it's unreachable or
/// fails, the invite itself still works in-app (the client already wrote
/// the Firestore doc before calling this) — it just won't wake up a
/// backgrounded/closed app via an OS notification.
Future<shelf.Response> handleNotifyInviteRequest(
  shelf.Request request, {
  FcmSender? fcmSender,
  FirebaseAuthVerifier? authVerifier,
}) async {
  final fcm = fcmSender ?? FcmSender.instance;
  final verifier = authVerifier ?? FirebaseAuthVerifier.instance;
  final log = Logger('NotifyInvite');

  final authHeader = request.headers['authorization'];
  final idToken =
      authHeader != null && authHeader.startsWith('Bearer ') ? authHeader.substring(7) : null;
  if (idToken == null) {
    return shelf.Response(401, body: jsonEncode({'error': 'Missing Authorization header'}));
  }

  final fromUid = await verifier.verifyToken(idToken);
  if (fromUid == null) {
    return shelf.Response(401, body: jsonEncode({'error': 'Invalid token'}));
  }

  Map<String, dynamic> body;
  try {
    body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return shelf.Response(400, body: jsonEncode({'error': 'Invalid JSON body'}));
  }

  final parsed = InvitePushRequest.fromJson(body);
  if (parsed == null) {
    return shelf.Response(
      400,
      body: jsonEncode({'error': 'Missing toUid/fromDisplayName/roomCode'}),
    );
  }
  if (parsed.toUid == fromUid) {
    return shelf.Response(400, body: jsonEncode({'error': 'Cannot invite yourself'}));
  }

  final tokens = await fcm.getUserFcmTokens(parsed.toUid);
  if (tokens.isNotEmpty) {
    await fcm.notify(
      uid: parsed.toUid,
      fcmTokens: tokens,
      type: 'invite',
      title: '${parsed.fromDisplayName} invited you to play',
      body: 'Room code: ${parsed.roomCode}',
      writeInboxDoc: false,
    );
  }
  log.info('Invite push sent from $fromUid to ${parsed.toUid} (room ${parsed.roomCode})');
  return shelf.Response.ok(jsonEncode({'ok': true}));
}
