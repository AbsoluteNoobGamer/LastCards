import 'dart:io';

import 'package:last_cards_server/fcm_sender.dart';
import 'package:last_cards_server/release_version.dart';

/// Run this once **after the build is actually live/approved** on the App
/// Store / Play Store — not right after uploading it. Announcing a version
/// before the store has finished processing it sends players to a store
/// listing with no update to install.
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
/// Optional, only needed the first time (or to change the store link):
///   --ios-store-url=https://apps.apple.com/app/id<your-app-id>
///   --android-store-url=https://play.google.com/store/apps/details?id=...
///
/// Pass --yes / -y to skip the confirmation prompt (e.g. for CI).
Future<void> main(List<String> args) async {
  final skipConfirm = args.contains('--yes') || args.contains('-y');
  final iosStoreUrl = _argValue(args, '--ios-store-url');
  final androidStoreUrl = _argValue(args, '--android-store-url');

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
  if (iosStoreUrl != null) stdout.writeln('  iosStoreUrl        = "$iosStoreUrl"');
  if (androidStoreUrl != null) {
    stdout.writeln('  androidStoreUrl    = "$androidStoreUrl"');
  }

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
      if (iosStoreUrl != null) 'iosStoreUrl': iosStoreUrl,
      if (androidStoreUrl != null) 'androidStoreUrl': androidStoreUrl,
    },
  );

  if (!ok) {
    stderr.writeln(
        '\nFailed — check that GOOGLE_CREDENTIALS_JSON is set and valid (see log output above).');
    exitCode = 1;
    return;
  }

  stdout.writeln('\nDone. app_config/app_update updated.');
  stdout.writeln(
      'The running server polls every 10 minutes and will broadcast on its next check.');

  // iosStoreUrl has no code fallback (unlike androidStoreUrl) — if it's
  // missing, fetchAppUpdateSuggestion/fetchForcedUpdateGate silently return
  // null on iOS forever, no matter how stale the build is. Read the doc back
  // and warn loudly rather than let that fail silently again.
  final current = await FcmSender.instance.getDocumentFields(
    collection: 'app_config',
    docId: 'app_update',
  );
  final currentIosUrl = current?['iosStoreUrl'] as String?;
  if (currentIosUrl == null || currentIosUrl.trim().isEmpty) {
    stdout.writeln(
        '\n⚠ iosStoreUrl is not set on this document — the update banner and');
    stdout.writeln(
        '  forced-update gate will NEVER show on iOS, regardless of build number.');
    stdout.writeln(
        '  Re-run with --ios-store-url=https://apps.apple.com/app/id<your-app-id> to fix.');
  }
}

String? _argValue(List<String> args, String flag) {
  for (final arg in args) {
    if (arg.startsWith('$flag=')) return arg.substring(flag.length + 1);
  }
  return null;
}
