import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:last_cards_server/firebase_auth_verifier.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    FirebaseAuthVerifier.setApiKey(null);
  });

  group('FirebaseAuthVerifier', () {
    test('returns null when API key is unset', () async {
      final client = MockClient((_) async => throw StateError('no HTTP'));
      final v = FirebaseAuthVerifier.withClient(client);
      expect(await v.verifyToken('any'), isNull);
    });

    test('returns null when API key is empty', () async {
      FirebaseAuthVerifier.setApiKey('');
      final client = MockClient((_) async => throw StateError('no HTTP'));
      final v = FirebaseAuthVerifier.withClient(client);
      expect(await v.verifyToken('any'), isNull);
    });

    test('200 with localId returns uid', () async {
      FirebaseAuthVerifier.setApiKey('test-api-key');
      final client = MockClient((request) async {
        expect(request.url.toString(),
            contains('identitytoolkit.googleapis.com/v1/accounts:lookup'));
        expect(request.url.queryParameters['key'], 'test-api-key');
        expect(
          jsonDecode(request.body as String) as Map<String, dynamic>,
          containsPair('idToken', 'my-token'),
        );
        return http.Response(
          jsonEncode({
            'users': [
              {'localId': 'uid123'},
            ],
          }),
          200,
        );
      });
      final v = FirebaseAuthVerifier.withClient(client);
      expect(await v.verifyToken('my-token'), 'uid123');
    });

    test('non-200 returns null', () async {
      FirebaseAuthVerifier.setApiKey('k');
      final client =
          MockClient((_) async => http.Response('bad', 401));
      final v = FirebaseAuthVerifier.withClient(client);
      expect(await v.verifyToken('t'), isNull);
    });

    test('empty users returns null', () async {
      FirebaseAuthVerifier.setApiKey('k');
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'users': []}), 200));
      final v = FirebaseAuthVerifier.withClient(client);
      expect(await v.verifyToken('t'), isNull);
    });

    test('malformed JSON returns null', () async {
      FirebaseAuthVerifier.setApiKey('k');
      final client =
          MockClient((_) async => http.Response('not json', 200));
      final v = FirebaseAuthVerifier.withClient(client);
      expect(await v.verifyToken('t'), isNull);
    });
  });
}
