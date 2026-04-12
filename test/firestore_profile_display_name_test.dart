import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/services/firestore_profile_service.dart';

void main() {
  group('resolvedPublicDisplayNameFromAuth', () {
    test('prefers Auth displayName over email local part', () {
      final u = MockUser(
        uid: 'a',
        email: 'bob@example.com',
        displayName: 'Alice',
      );
      expect(resolvedPublicDisplayNameFromAuth(u), 'Alice');
    });

    test('uses email local part when displayName is null', () {
      final u = MockUser(
        uid: 'a',
        email: 'charlie@example.com',
      );
      expect(resolvedPublicDisplayNameFromAuth(u), 'charlie');
    });

    test('returns null when no name or email', () {
      final u = MockUser(uid: 'anon');
      expect(resolvedPublicDisplayNameFromAuth(u), isNull);
    });
  });
}
