import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/constants/quick_chat_messages.dart';

void main() {
  test(
    'reaction presets length equals shared catalogue (offline + server index range)',
    () {
      expect(kQuickMessages.length, kReactionCatalogLength);
      for (final em in kQuickMessages) {
        expect(em.isNotEmpty, isTrue);
        expect(em.contains(RegExp(r'[A-Za-z]{3,}')), isFalse);
      }
    },
  );
}
