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
/// Every run also sets minimumBuildAndroid/minimumBuildIos to the same build
/// number as latest — so this release immediately hard-blocks (via
/// [fetchForcedUpdateGate]) any build older than the one being published,
/// with no grace period. There is no "soft banner only" phase: as soon as
/// this doc updates, every player not on the new build is forced to update
/// before they can play again.
///
/// Requires GOOGLE_CREDENTIALS_JSON in the environment — the same service
/// account JSON already used by the deployed server (see FcmSender's doc
/// comment). Both Android and iOS get the same build number since this repo
/// ships both platforms from one pubspec.yaml version — unless --android-only
/// is passed (see below), for the common case where Play review clears
/// before App Review does.
///
/// Usage:
///   GOOGLE_CREDENTIALS_JSON="$(cat service-account.json)" dart run bin/publish_release.dart
///
/// Both platforms have a hardcoded fallback store URL in code
/// ([kDefaultIosStoreUrl] / [kDefaultAndroidStoreUrl]), so these flags are
/// only needed to override them (e.g. a store listing ID changes):
///   --ios-store-url=https://apps.apple.com/app/id<your-app-id>
///   --android-store-url=https://play.google.com/store/apps/details?id=...
///
/// Pass --android-only when the iOS build for this version isn't live yet
/// (e.g. still in App Review). This leaves latestBuildIos untouched — so iOS
/// devices don't get a stale "update available" banner pointing at a store
/// build that doesn't exist — and the broadcast copy calls out Android
/// specifically instead of the generic "a new version is out" text. Once iOS
/// clears review, re-run without --android-only to announce it there too.
///
/// Pass --yes / -y to skip the confirmation prompt (e.g. for CI).
Future<void> main(List<String> args) async {
  final skipConfirm = args.contains('--yes') || args.contains('-y');
  final androidOnly = args.contains('--android-only');
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
  stdout.writeln(
      '\n⚠ This will HARD-BLOCK every build older than $buildNumber —');
  stdout.writeln(
      '  players on any older version will be forced to update before they');
  stdout.writeln('  can play again, with no grace period.');
  stdout.writeln('\nAbout to set app_config/app_update:');
  stdout.writeln('  latestBuildAndroid  = $buildNumber');
  stdout.writeln('  minimumBuildAndroid = $buildNumber');
  if (androidOnly) {
    stdout.writeln('  latestBuildIos      = (untouched — --android-only)');
    stdout.writeln('  minimumBuildIos     = (untouched — --android-only)');
  } else {
    stdout.writeln('  latestBuildIos      = $buildNumber');
    stdout.writeln('  minimumBuildIos     = $buildNumber');
  }
  stdout.writeln('  latestVersionName   = "$versionName"');
  if (iosStoreUrl != null) stdout.writeln('  iosStoreUrl        = "$iosStoreUrl"');
  if (androidStoreUrl != null) {
    stdout.writeln('  androidStoreUrl    = "$androidStoreUrl"');
  }
  if (androidOnly) {
    stdout.writeln(
        '\n--android-only: latestBuildIos will NOT be touched (stays at whatever');
    stdout.writeln(
        '  it currently is), so iOS devices won\'t see a stale "update available"');
    stdout.writeln(
        '  banner pointing at a store build that isn\'t live yet. The broadcast');
    stdout.writeln('  copy will call out Android specifically.');
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
      'minimumBuildAndroid': buildNumber,
      if (!androidOnly) 'latestBuildIos': buildNumber,
      if (!androidOnly) 'minimumBuildIos': buildNumber,
      'latestVersionName': versionName,
      if (iosStoreUrl != null) 'iosStoreUrl': iosStoreUrl,
      if (androidStoreUrl != null) 'androidStoreUrl': androidStoreUrl,
      // Always write these two (even as '' when not android-only) rather than
      // omitting them — updateDocumentFields does a field-masked PATCH, so an
      // omitted key leaves whatever was written by a *previous* --android-only
      // run in place. Without this, the next normal (both-platforms) release
      // would silently re-broadcast stale "Android only, iOS coming soon" copy.
      'announcementTitle': androidOnly ? 'Android update available' : '',
      'announcementBody': androidOnly
          ? 'Update available on Android ($versionName) — update to keep playing. '
              'The iOS version is in review and coming soon.'
          : '',
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
}

String? _argValue(List<String> args, String flag) {
  for (final arg in args) {
    if (arg.startsWith('$flag=')) return arg.substring(flag.length + 1);
  }
  return null;
}
