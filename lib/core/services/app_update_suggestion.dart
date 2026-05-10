import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Play Store listing for [com.lastcards.app] (used when Firestore omits a URL).
const String kDefaultAndroidStoreUrl =
    'https://play.google.com/store/apps/details?id=com.lastcards.app';

/// Soft “update available” hint for the start screen.
///
/// **Firestore** (create in Console): collection `app_config`, document id
/// `app_update`. Suggested fields:
/// - `latestBuildAndroid` (int): when [PackageInfo.buildNumber] is lower on
///   Android, the app shows the banner.
/// - `latestBuildIos` (int): same for iOS.
/// - `latestVersionName` (string, optional): shown as subtitle, e.g. `1.0.1`.
/// - `androidStoreUrl` (string, optional): defaults to [kDefaultAndroidStoreUrl].
/// - `iosStoreUrl` (string, optional): **required** to open the store on iOS;
///   if missing, the banner is not shown on iOS even when the build is stale.
class AppUpdateSuggestion {
  const AppUpdateSuggestion({
    required this.storeUrl,
    this.remoteVersionLabel,
  });

  final String storeUrl;
  final String? remoteVersionLabel;
}

@visibleForTesting
bool shouldSuggestUpgrade({
  required int currentBuild,
  required int? latestRemoteBuild,
}) {
  if (latestRemoteBuild == null) return false;
  return currentBuild < latestRemoteBuild;
}

/// Returns a suggestion when this build is older than the Firestore config for
/// the current platform. Never throws — failures yield `null` (no banner).
Future<AppUpdateSuggestion?> fetchAppUpdateSuggestion() async {
  if (kIsWeb) return null;
  if (Firebase.apps.isEmpty) return null;

  try {
    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;

    final snap = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('app_update')
        .get(const GetOptions(source: Source.serverAndCache));

    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;

    final latestAndroid = (data['latestBuildAndroid'] as num?)?.toInt();
    final latestIos = (data['latestBuildIos'] as num?)?.toInt();
    final versionName = data['latestVersionName'] as String?;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        if (!shouldSuggestUpgrade(
          currentBuild: currentBuild,
          latestRemoteBuild: latestAndroid,
        )) {
          return null;
        }
        final url = (data['androidStoreUrl'] as String?)?.trim();
        return AppUpdateSuggestion(
          storeUrl:
              (url != null && url.isNotEmpty) ? url : kDefaultAndroidStoreUrl,
          remoteVersionLabel: versionName,
        );
      case TargetPlatform.iOS:
        if (!shouldSuggestUpgrade(
          currentBuild: currentBuild,
          latestRemoteBuild: latestIos,
        )) {
          return null;
        }
        final iosUrl = (data['iosStoreUrl'] as String?)?.trim();
        if (iosUrl == null || iosUrl.isEmpty) {
          // Cannot deep-link; avoid a useless banner.
          return null;
        }
        return AppUpdateSuggestion(
          storeUrl: iosUrl,
          remoteVersionLabel: versionName,
        );
      default:
        return null;
    }
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('fetchAppUpdateSuggestion: $e\n$st');
    }
    return null;
  }
}
