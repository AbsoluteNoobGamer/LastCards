// Print release metadata + Firestore hints for the in-app update banner.
// Run from repo root: dart run tool/release_info.dart
import 'dart:io';

void main() {
  final root = Directory.current.path;
  final pubspec = File('$root${Platform.pathSeparator}pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('Run this from the project root (pubspec.yaml not found).');
    exit(1);
  }
  final text = pubspec.readAsStringSync();
  final versionLine = text
      .split('\n')
      .map((l) => l.trim())
      .firstWhere(
        (l) => l.startsWith('version:'),
        orElse: () => '',
      );
  if (versionLine.isEmpty) {
    stderr.writeln('No version: line in pubspec.yaml');
    exit(1);
  }
  final raw = versionLine.substring('version:'.length).trim();
  final plusIdx = raw.indexOf('+');
  final name = plusIdx < 0 ? raw : raw.substring(0, plusIdx);
  final buildStr = plusIdx < 0 ? '0' : raw.substring(plusIdx + 1);
  final build = int.tryParse(buildStr) ?? 0;

  final buf = StringBuffer()
    ..writeln('Last Cards — release info')
    ..writeln('===========================')
    ..writeln()
    ..writeln('pubspec version name : $name')
    ..writeln('pubspec build (+N) : $build')
    ..writeln()
    ..writeln('In-app update banner (see lib/core/services/app_update_suggestion.dart)')
    ..writeln('reads app_config/app_update from Firestore.')
    ..writeln()
    ..writeln('After this build is available in the Play Store / App Store, set or merge:')
    ..writeln()
    ..writeln('  Collection: app_config')
    ..writeln('  Document id: app_update')
    ..writeln()
    ..writeln('  latestBuildAndroid : $build')
    ..writeln('  latestBuildIos     : $build')
    ..writeln('  latestVersionName  : "$name"   // optional label on the banner')
    ..writeln('  androidStoreUrl    : (optional; defaults to Play listing)')
    ..writeln('  iosStoreUrl        : required on iOS or the banner is hidden')
    ..writeln()
    ..writeln('Any installed app with buildNumber < $build will see “update available”.')
    ..writeln();

  // ignore: avoid_print
  print(buf.toString());
}
