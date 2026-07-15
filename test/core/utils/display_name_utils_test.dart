import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/utils/display_name_utils.dart';

void main() {
  group('initialsFromDisplayName', () {
    test('two-word name uses first letter of each word', () {
      expect(initialsFromDisplayName('John Doe'), 'JD');
    });

    test('single word name repeats/truncates to 2 chars', () {
      expect(initialsFromDisplayName('Alice'), 'AL');
    });

    test('empty name falls back to ?', () {
      expect(initialsFromDisplayName(''), '?');
    });
  });

  group('isEmailDerivedFallbackName', () {
    test('true when the display name is exactly the email local part', () {
      expect(
        isEmailDerivedFallbackName(
          displayName: 'abc123xyz',
          email: 'abc123xyz@privaterelay.appleid.com',
        ),
        isTrue,
      );
    });

    test('true for a regular (non-relay) email too', () {
      expect(
        isEmailDerivedFallbackName(
          displayName: 'johndoe42',
          email: 'johndoe42@gmail.com',
        ),
        isTrue,
      );
    });

    test('false when the display name was actually chosen', () {
      expect(
        isEmailDerivedFallbackName(
          displayName: 'CardShark',
          email: 'abc123xyz@privaterelay.appleid.com',
        ),
        isFalse,
      );
    });

    test('false when displayName or email is null/empty', () {
      expect(
        isEmailDerivedFallbackName(displayName: null, email: 'a@b.com'),
        isFalse,
      );
      expect(
        isEmailDerivedFallbackName(displayName: 'abc', email: null),
        isFalse,
      );
      expect(
        isEmailDerivedFallbackName(displayName: '', email: 'abc@b.com'),
        isFalse,
      );
    });
  });
}
