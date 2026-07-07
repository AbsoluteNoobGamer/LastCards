import 'package:flutter_test/flutter_test.dart';

import 'package:last_cards/core/services/app_update_suggestion.dart';

void main() {
  group('shouldSuggestUpgrade', () {
    test('false when remote is null', () {
      expect(
        shouldSuggestUpgrade(currentBuild: 10, latestRemoteBuild: null),
        false,
      );
    });

    test('false when current >= remote', () {
      expect(
        shouldSuggestUpgrade(currentBuild: 15, latestRemoteBuild: 15),
        false,
      );
      expect(
        shouldSuggestUpgrade(currentBuild: 16, latestRemoteBuild: 15),
        false,
      );
    });

    test('true when current < remote', () {
      expect(
        shouldSuggestUpgrade(currentBuild: 15, latestRemoteBuild: 16),
        true,
      );
    });
  });

  group('isBuildBelowMinimum', () {
    test('false when minimum is null (no gate configured)', () {
      expect(
        isBuildBelowMinimum(currentBuild: 10, minimumRequiredBuild: null),
        false,
      );
    });

    test('false when current >= minimum', () {
      expect(
        isBuildBelowMinimum(currentBuild: 15, minimumRequiredBuild: 15),
        false,
      );
      expect(
        isBuildBelowMinimum(currentBuild: 16, minimumRequiredBuild: 15),
        false,
      );
    });

    test('true when current < minimum', () {
      expect(
        isBuildBelowMinimum(currentBuild: 15, minimumRequiredBuild: 16),
        true,
      );
    });
  });
}
