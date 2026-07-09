/// Parsed `version: X.Y.Z+build` line from a `pubspec.yaml`.
typedef PubspecVersion = ({String versionName, int buildNumber});

/// Extracts the version name/build number from raw `pubspec.yaml` content
/// (e.g. `version: 1.0.2+35` → `(versionName: '1.0.2', buildNumber: 35)`).
/// Returns `null` if no `version:` line matches the expected shape.
PubspecVersion? parsePubspecVersion(String pubspecContent) {
  final versionLine = pubspecContent
      .split('\n')
      .firstWhere((l) => l.trim().startsWith('version:'), orElse: () => '');
  final match = RegExp(r'version:\s*(\d+\.\d+\.\d+)\+(\d+)').firstMatch(versionLine);
  if (match == null) return null;
  return (versionName: match.group(1)!, buildNumber: int.parse(match.group(2)!));
}
