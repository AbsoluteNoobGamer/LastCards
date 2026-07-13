import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls whether Firebase Analytics collection is active, and whether
/// the one-time first-launch notice has been shown.
///
/// Analytics is on by default — this is a notice + opt-out model (the
/// player is told analytics is used and can turn it off in Settings),
/// not a blocking opt-in gate. See docs/analytics-plan.md §6 Phase 4.
///
/// Singleton + [ValueNotifier], mirroring [PurchaseService.adsRemoved] —
/// this needs to be readable/settable before [ProviderScope] exists (in
/// `main()`, ahead of `runApp`), where Riverpod isn't reachable yet.
class AnalyticsConsentService {
  AnalyticsConsentService._();

  static final AnalyticsConsentService instance = AnalyticsConsentService._();

  static const String _enabledPrefsKey = 'analytics_enabled';
  static const String _noticeShownPrefsKey = 'analytics_notice_shown';

  bool _initialized = false;

  /// Whether analytics collection is currently on. Defaults to true.
  final ValueNotifier<bool> analyticsEnabled = ValueNotifier<bool>(true);

  /// Loads the persisted preference (default on) and applies it to the SDK.
  /// Call once, early in `main()`, before any analytics events can fire.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    analyticsEnabled.value = prefs.getBool(_enabledPrefsKey) ?? true;
    await FirebaseAnalytics.instance
        .setAnalyticsCollectionEnabled(analyticsEnabled.value);
  }

  /// Settings-screen opt-out toggle. Takes effect immediately — no restart
  /// needed — since it calls the SDK live in addition to persisting.
  Future<void> setEnabled(bool value) async {
    analyticsEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledPrefsKey, value);
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(value);
  }

  /// True exactly once — the first time this is called on a fresh install —
  /// so the first-launch notice dialog only ever shows a single time.
  Future<bool> shouldShowFirstLaunchNotice() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_noticeShownPrefsKey) ?? false) return false;
    await prefs.setBool(_noticeShownPrefsKey, true);
    return true;
  }
}
