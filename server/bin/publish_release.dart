import 'dart:io';

import 'package:last_cards_server/fcm_sender.dart';
import 'package:last_cards_server/release_version.dart';

/// Run this once after uploading a new build to the App Store / Play Store.
///
/// Updates the `app_config/app_update` Firestore doc (latestBuildAndroid,
/// latestBuildIos, latestVersionName) from the version in the repo root's
/// `pubspec.yaml` — the doc [AppUpdateBroadcaster] polls to fire the
/// "new version available" push, and [fetchAppUpdateSuggestion] /
/// [fetchForcedUpdateGate] read on the client for the update banner/gate.
///
/// Requires GOOGLE_CREDENTIALS_JSON in the environment — the same service
/// account JSON already used by the deployed server (see FcmSender's doc
/// comment). Both Android and iOS get the same build number since this repo
/// ships both platforms from one pubspec.yaml version.
///
/// Usage:
///   GOOGLE_CREDENTIALS_JSON="$(cat service-account.json)" dart run bin/publish_release.dart
///
/// Pass --yes / -y to skip the confirmation prompt (e.g. for CI).
Future<void> main(List<String> args) async {
  final skipConfirm = args.contains('--yes') || args.contains('-y');

  final pubspecPath = '../pubspec.yaml';
  final pubspecFile = File(pubspecPath);
  if (!pubspecFile.existsSync()) {
    stderr.writeln(
        'Could not find $pubspecPath — run this from the server/ directory.');
    exitCode = 1;
    return;
  }

  final parsed = parsePubspecVersion(pubspecFile.readAsStringSync());
  if (parsed == null) {
    stderr.writeln('Could not parse a "version: 1.0.2+35"-shaped line from $pubspecPath.');
    exitCode = 1;
    return;
  }
  final versionName = parsed.versionName;
  final buildNumber = parsed.buildNumber;

  stdout.writeln('Repo pubspec.yaml version: $versionName+$buildNumber');
  stdout.writeln('This will broadcast a push notification to every device');
  stdout.writeln('subscribed to "app_updates" if latestVersionName changes.');
  stdout.writeln('About to set app_config/app_update:');
  stdout.writeln('  latestBuildAndroid = $buildNumber');
  stdout.writeln('  latestBuildIos     = $buildNumber');
  stdout.writeln('  latestVersionName  = "$versionName"');

  if (!skipConfirm) {
    stdout.write('\nProceed? [y/N] ');
    final answer = stdin.readLineSync()?.trim().toLowerCase();
    if (answer != 'y' && answer != 'yes') {
      stdout.writeln('Aborted.');
      return;
    }
  }

  FcmSender.instance.init();
  final ok = await FcmSender.instance.updateDocumentFields(
    collection: 'app_config',
    docId: 'app_update',
    fields: {
      'latestBuildAndroid': buildNumber,
      'latestBuildIos': buildNumber,
      'latestVersionName': versionName,
    },
  );

  if (ok) {
    stdout.writeln('\nDone. app_config/app_update updated.');
    stdout.writeln(
        'The running server polls every 10 minutes and will broadcast on its next check.');
  } else {
    stderr.writeln(
        '\nFailed — check that GOOGLE_CREDENTIALS_JSON is set and valid (see log output above).');
    exitCode = 1;
  }
}
