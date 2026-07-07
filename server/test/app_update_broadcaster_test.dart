import 'package:last_cards_server/app_update_broadcaster.dart';
import 'package:test/test.dart';

void main() {
  group('shouldAnnounceNewVersion', () {
    test('false on the first check since server start (no baseline yet)', () {
      expect(
        shouldAnnounceNewVersion(
          latestVersionName: '1.2.0',
          lastAnnouncedVersion: null,
        ),
        isFalse,
        reason: 'a fresh restart must not re-announce whatever is already live',
      );
    });

    test('false when the version is unchanged', () {
      expect(
        shouldAnnounceNewVersion(
          latestVersionName: '1.2.0',
          lastAnnouncedVersion: '1.2.0',
        ),
        isFalse,
      );
    });

    test('true when the version changed from an established baseline', () {
      expect(
        shouldAnnounceNewVersion(
          latestVersionName: '1.3.0',
          lastAnnouncedVersion: '1.2.0',
        ),
        isTrue,
      );
    });
  });
}
