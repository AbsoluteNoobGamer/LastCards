import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/constants/quick_chat_messages.dart';

void main() {
  test(
    'preset reaction list length and emoji-only shape (must match server index range)',
    () {
      expect(kQuickMessages.length, 13);
      for (final em in kQuickMessages) {
        expect(em.isNotEmpty, isTrue);
        // No English words — index wire format is emoji reactions only
        expect(em.contains(RegExp(r'[A-Za-z]{3,}')), isFalse);
      }
    },
  );
}
