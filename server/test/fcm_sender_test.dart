import 'package:last_cards_server/fcm_sender.dart';
import 'package:test/test.dart';

void main() {
  group('buildNotificationDocFields', () {
    test('encodes string/bool/timestamp fields for the Firestore REST API', () {
      final fields = buildNotificationDocFields(
        type: 'turn',
        title: "It's your turn",
        body: 'Alice played a card.',
        now: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );

      expect(fields['type'], {'stringValue': 'turn'});
      expect(fields['title'], {'stringValue': "It's your turn"});
      expect(fields['body'], {'stringValue': 'Alice played a card.'});
      expect(fields['read'], {'booleanValue': false});
      expect(fields['createdAt'], {'timestampValue': '2026-01-02T03:04:05.000Z'});
    });
  });

  group('buildFcmMessagePayload', () {
    test('wraps title/body/token in the FCM v1 message envelope', () {
      final payload = buildFcmMessagePayload(
        deviceToken: 'device-token-123',
        title: "It's your turn",
        body: 'Alice played a card.',
      );

      expect(payload['message'], {
        'token': 'device-token-123',
        'notification': {
          'title': "It's your turn",
          'body': 'Alice played a card.',
        },
      });
    });
  });
}
