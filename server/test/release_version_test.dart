import 'package:last_cards_server/release_version.dart';
import 'package:test/test.dart';

void main() {
  group('parsePubspecVersion', () {
    test('parses version name and build number from a real pubspec.yaml shape', () {
      const content = '''
name: last_cards
description: "Last Cards — Play It All. Leave Nothing."
publish_to: "none"
version: 1.0.2+35

environment:
  sdk: ">=3.3.0 <4.0.0"
''';
      final parsed = parsePubspecVersion(content);
      expect(parsed, isNotNull);
      expect(parsed!.versionName, '1.0.2');
      expect(parsed.buildNumber, 35);
    });

    test('returns null when there is no version line', () {
      const content = 'name: last_cards\ndescription: "no version here"\n';
      expect(parsePubspecVersion(content), isNull);
    });

    test('returns null when the version does not have a +build suffix', () {
      const content = 'version: 1.0.2\n';
      expect(parsePubspecVersion(content), isNull);
    });
  });
}
