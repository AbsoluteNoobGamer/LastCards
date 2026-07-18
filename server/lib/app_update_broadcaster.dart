import 'dart:async';

import 'fcm_sender.dart';
import 'logger.dart';

/// Polls `app_config/app_update` (the same Firestore doc the client's
/// optional-update banner and forced-update gate already read) and
/// broadcasts to the `app_updates` FCM topic when [latestVersionName]
/// changes.
///
/// Tracks the last-seen version **in memory only** — deliberately does not
/// re-broadcast on the very first check after a (re)start (see
/// [shouldAnnounceNewVersion]), so a server restart/redeploy can't spam
/// every subscriber with a "new version" push for a version that was
/// already live before the restart.
class AppUpdateBroadcaster {
  AppUpdateBroadcaster({FcmSender? fcmSender}) : _fcm = fcmSender ?? FcmSender.instance;

  final FcmSender _fcm;
  final _log = Logger('AppUpdateBroadcaster');

  String? _lastSeenVersion;
  Timer? _timer;

  void start({Duration interval = const Duration(minutes: 10)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => checkAndBroadcast());
    unawaited(checkAndBroadcast());
  }

  void stop() => _timer?.cancel();

  Future<void> checkAndBroadcast() async {
    final fields =
        await _fcm.getDocumentFields(collection: 'app_config', docId: 'app_update');
    if (fields == null) return;
    final versionName = fields['latestVersionName'] as String?;
    if (versionName == null || versionName.isEmpty) return;

    final previous = _lastSeenVersion;
    final shouldBroadcast = shouldAnnounceNewVersion(
      latestVersionName: versionName,
      lastAnnouncedVersion: previous,
    );
    _lastSeenVersion = versionName;
    if (!shouldBroadcast) return;

    _log.info('New app version detected ($versionName) — broadcasting to app_updates topic.');
    final title = (fields['announcementTitle'] as String?)?.trim();
    final body = (fields['announcementBody'] as String?)?.trim();
    await _fcm.notifyTopic(
      topic: 'app_updates',
      title: (title != null && title.isNotEmpty) ? title : 'Update available',
      body: (body != null && body.isNotEmpty)
          ? body
          : 'A new version of Last Cards ($versionName) is out — update to keep playing.',
    );
  }
}

/// Pure decision for [AppUpdateBroadcaster.checkAndBroadcast]: only
/// broadcast when there's an established baseline ([lastAnnouncedVersion]
/// non-null, i.e. this isn't the first check since server start) AND the
/// version actually changed.
bool shouldAnnounceNewVersion({
  required String latestVersionName,
  required String? lastAnnouncedVersion,
}) {
  return lastAnnouncedVersion != null && latestVersionName != lastAnnouncedVersion;
}
