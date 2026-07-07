import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:last_cards_server/fcm_sender.dart';
import 'package:last_cards_server/firebase_auth_verifier.dart';
import 'package:last_cards_server/invite_push_handler.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';

shelf.Request _postRequest({
  Map<String, dynamic>? body,
  String? authHeader,
}) {
  return shelf.Request(
    'POST',
    Uri.parse('http://localhost/notify-invite'),
    headers: {
      if (authHeader != null) 'authorization': authHeader,
    },
    body: body == null ? null : jsonEncode(body),
  );
}

void main() {
  tearDown(() {
    FirebaseAuthVerifier.setApiKey(null);
  });

  group('InvitePushRequest.fromJson', () {
    test('parses a complete payload', () {
      final parsed = InvitePushRequest.fromJson({
        'toUid': 'uid-2',
        'fromDisplayName': 'Alice',
        'roomCode': 'ABC123',
      });
      expect(parsed, isNotNull);
      expect(parsed!.toUid, 'uid-2');
      expect(parsed.fromDisplayName, 'Alice');
      expect(parsed.roomCode, 'ABC123');
    });

    test('null when toUid is missing', () {
      expect(
        InvitePushRequest.fromJson({'fromDisplayName': 'Alice', 'roomCode': 'ABC123'}),
        isNull,
      );
    });

    test('null when fromDisplayName is empty', () {
      expect(
        InvitePushRequest.fromJson({
          'toUid': 'uid-2',
          'fromDisplayName': '',
          'roomCode': 'ABC123',
        }),
        isNull,
      );
    });

    test('null when roomCode is missing', () {
      expect(
        InvitePushRequest.fromJson({'toUid': 'uid-2', 'fromDisplayName': 'Alice'}),
        isNull,
      );
    });
  });

  group('handleNotifyInviteRequest', () {
    test('401 when Authorization header is missing', () async {
      final response = await handleNotifyInviteRequest(_postRequest(body: {
        'toUid': 'uid-2',
        'fromDisplayName': 'Alice',
        'roomCode': 'ABC123',
      }));
      expect(response.statusCode, 401);
    });

    test('401 when the token fails verification', () async {
      // No API key configured -> FirebaseAuthVerifier.instance.verifyToken always null.
      final response = await handleNotifyInviteRequest(_postRequest(
        authHeader: 'Bearer not-a-real-token',
        body: {'toUid': 'uid-2', 'fromDisplayName': 'Alice', 'roomCode': 'ABC123'},
      ));
      expect(response.statusCode, 401);
    });

    test('400 when the JSON body is missing required fields', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'users': [
                {'localId': 'uid-1'},
              ],
            }),
            200,
          ));
      final verifier = FirebaseAuthVerifier.withClient(client);
      FirebaseAuthVerifier.setApiKey('test-key');

      final response = await handleNotifyInviteRequest(
        _postRequest(authHeader: 'Bearer valid-token', body: {'toUid': 'uid-2'}),
        authVerifier: verifier,
      );
      expect(response.statusCode, 400);
    });

    test('400 when inviting yourself', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'users': [
                {'localId': 'uid-1'},
              ],
            }),
            200,
          ));
      final verifier = FirebaseAuthVerifier.withClient(client);
      FirebaseAuthVerifier.setApiKey('test-key');

      final response = await handleNotifyInviteRequest(
        _postRequest(authHeader: 'Bearer valid-token', body: {
          'toUid': 'uid-1', // same as the verified sender uid-1
          'fromDisplayName': 'Alice',
          'roomCode': 'ABC123',
        }),
        authVerifier: verifier,
      );
      expect(response.statusCode, 400);
    });

    test('200 for a valid, well-formed request', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'users': [
                {'localId': 'uid-1'},
              ],
            }),
            200,
          ));
      final verifier = FirebaseAuthVerifier.withClient(client);
      FirebaseAuthVerifier.setApiKey('test-key');

      final response = await handleNotifyInviteRequest(
        _postRequest(authHeader: 'Bearer valid-token', body: {
          'toUid': 'uid-2',
          'fromDisplayName': 'Alice',
          'roomCode': 'abc123',
        }),
        authVerifier: verifier,
        // Unconfigured FcmSender.instance (no GOOGLE_CREDENTIALS_JSON in the
        // test process) gracefully no-ops the actual push/token lookup —
        // this test only asserts the HTTP-layer contract (auth + validation
        // pass, so the handler reaches its success response).
        fcmSender: FcmSender.instance,
      );
      expect(response.statusCode, 200);
    });
  });
}
