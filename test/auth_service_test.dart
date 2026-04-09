import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/services/auth_service.dart';

void main() {
  // Required so SignInWithApple.isAvailable() can use the platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService', () {
    test('signInWithApple returns failure when Firebase is unavailable', () async {
      final service = AuthService();
      final result = await service.signInWithApple();
      expect(result, isA<AppleSignInFailure>());
      expect(
        (result as AppleSignInFailure).message,
        contains('not initialized'),
      );
    });

    test(
      'signInWithApple returns failure when Apple flow cannot complete in test VM',
      () async {
        final mockAuth = MockFirebaseAuth();
        final service = AuthService(firebaseAuth: mockAuth);
        final result = await service.signInWithApple();
        expect(result, isA<AppleSignInFailure>());
        final msg = (result as AppleSignInFailure).message;
        // VM tests: no native plugin → MissingPluginException. Device: often
        // "not available on this device" when isAvailable is false.
        expect(
          msg,
          anyOf(
            contains('not available'),
            contains('MissingPluginException'),
          ),
        );
      },
    );
  });
}
