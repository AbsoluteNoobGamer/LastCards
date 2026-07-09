import 'package:last_cards_server/fcm_sender.dart';
import 'package:test/test.dart';

void main() {
  group('encodeFirestoreFields', () {
    test('encodes String, int, and bool values as Firestore REST types', () {
      final encoded = encodeFirestoreFields({
        'latestVersionName': '1.0.2',
        'latestBuildAndroid': 35,
        'forced': false,
      });

      expect(encoded['latestVersionName'], {'stringValue': '1.0.2'});
      expect(encoded['latestBuildAndroid'], {'integerValue': '35'});
      expect(encoded['forced'], {'booleanValue': false});
    });
  });

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

  group('buildFcmTopicMessagePayload', () {
    test('wraps title/body/topic in the FCM v1 message envelope', () {
      final payload = buildFcmTopicMessagePayload(
        topic: 'app_updates',
        title: 'Update available',
        body: 'A new version is out.',
      );

      expect(payload['message'], {
        'topic': 'app_updates',
        'notification': {
          'title': 'Update available',
          'body': 'A new version is out.',
        },
      });
    });
  });

  group('parseFirestoreFields', () {
    test('decodes stringValue, integerValue, and arrayValue of strings', () {
      final parsed = parseFirestoreFields({
        'latestVersionName': {'stringValue': '1.2.0'},
        'latestBuildAndroid': {'integerValue': '42'},
        'fcmTokens': {
          'arrayValue': {
            'values': [
              {'stringValue': 'token-a'},
              {'stringValue': 'token-b'},
            ],
          },
        },
      });

      expect(parsed['latestVersionName'], '1.2.0');
      expect(parsed['latestBuildAndroid'], 42);
      expect(parsed['fcmTokens'], ['token-a', 'token-b']);
    });

    test('empty arrayValue decodes to an empty list', () {
      final parsed = parseFirestoreFields({
        'fcmTokens': {'arrayValue': <String, dynamic>{}},
      });
      expect(parsed['fcmTokens'], <String>[]);
    });
  });
}
