import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/services/auth_service.dart';

void main() {
  group('displayNameFromAppleNameParts', () {
    test('joins given and family name', () {
      expect(
        displayNameFromAppleNameParts(
          givenName: 'Jane',
          familyName: 'Doe',
        ),
        'Jane Doe',
      );
    });

    test('returns null when Apple sends no name', () {
      expect(displayNameFromAppleNameParts(), isNull);
    });
  });
}
