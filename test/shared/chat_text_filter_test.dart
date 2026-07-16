import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/shared/moderation/chat_text_filter.dart';

void main() {
  group('sanitizeChatMessage', () {
    test('allows mild language including shit', () {
      final r = sanitizeChatMessage('oh shit nice play');
      expect(r.isAllowed, isTrue);
      expect(r.text, 'oh shit nice play');
    });

    test('masks fuck as Fu*k', () {
      final r = sanitizeChatMessage('what the fuck');
      expect(r.isAllowed, isTrue);
      expect(r.text, 'what the Fu*k');
    });

    test('masks fucking / fucked stems', () {
      expect(sanitizeChatMessage('fucking hell').text, 'Fu*king hell');
      expect(sanitizeChatMessage('I fucked up').text, 'I Fu*ked up');
    });

    test('masks evasive f*ck spelling', () {
      final r = sanitizeChatMessage('f*ck this');
      expect(r.isAllowed, isTrue);
      expect(r.text, 'Fu*k this');
    });

    test('preserves surrounding punctuation', () {
      final r = sanitizeChatMessage('Fuck!');
      expect(r.isAllowed, isTrue);
      expect(r.text, 'Fu*k!');
    });

    test('rejects racial slur', () {
      final r = sanitizeChatMessage('you nigger');
      expect(r.rejected, isTrue);
      expect(r.text, isNull);
    });

    test('rejects obfuscated racial slur', () {
      final r = sanitizeChatMessage('n1gg3r');
      expect(r.rejected, isTrue);
    });

    test('rejects homophobic slur', () {
      expect(sanitizeChatMessage('shut up faggot').rejected, isTrue);
      expect(sanitizeChatMessage('what a fag').rejected, isTrue);
    });

    test('rejects empty / whitespace', () {
      expect(sanitizeChatMessage('   ').rejected, isTrue);
      expect(sanitizeChatMessage('').rejected, isTrue);
    });

    test('rejects over-long messages', () {
      final long = 'a' * (kChatMessageMaxLength + 1);
      expect(sanitizeChatMessage(long).rejected, isTrue);
    });

    test('trims whitespace on allowed messages', () {
      final r = sanitizeChatMessage('  gl hf  ');
      expect(r.isAllowed, isTrue);
      expect(r.text, 'gl hf');
    });
  });

  group('chatMessageContainsHateSpeech', () {
    test('true for slur, false for shit/fuck', () {
      expect(chatMessageContainsHateSpeech('nigger'), isTrue);
      expect(chatMessageContainsHateSpeech('shit'), isFalse);
      expect(chatMessageContainsHateSpeech('fuck'), isFalse);
    });
  });
}
