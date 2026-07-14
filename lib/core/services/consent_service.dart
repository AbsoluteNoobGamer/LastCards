import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps Google's User Messaging Platform (UMP) SDK — the piece that
/// actually renders the GDPR/EEA and US-states consent messages configured
/// in AdMob's Privacy & Messaging settings. Without this, those messages
/// exist in AdMob but never display, and ad requests go out with no
/// consent signal.
///
/// Singleton, mirrors the shape of [AdsService]/[AnalyticsConsentService].
class ConsentService {
  ConsentService._();

  static final ConsentService instance = ConsentService._();

  /// Requests updated consent info and shows the consent form if this
  /// user/region requires one (a no-op otherwise). Meant to be called once
  /// per app launch — the SDK caches consent status itself.
  ///
  /// Resolves to whether ad requests are currently allowed
  /// ([ConsentInformation.canRequestAds]) — callers must gate any actual
  /// ad SDK init/load calls on this.
  Future<bool> requestAndShowIfRequired() async {
    final completer = Completer<bool>();
    void resolveFromCache() {
      unawaited(
        ConsentInformation.instance.canRequestAds().then((canRequestAds) {
          if (!completer.isCompleted) completer.complete(canRequestAds);
        }),
      );
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(
        // Forces the EEA flow on debug builds so the form is testable
        // without a VPN/EEA device — never applied to release builds.
        consentDebugSettings: kDebugMode
            ? ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea)
            : null,
      ),
      () => ConsentForm.loadAndShowConsentFormIfRequired((_) => resolveFromCache()),
      (_) => resolveFromCache(),
    );
    return completer.future;
  }

  /// The required Settings re-entry point so a player can change their
  /// consent choice later. Only meaningful when [isPrivacyOptionsRequired].
  Future<void> showPrivacyOptionsForm() async {
    final completer = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Whether the Settings screen should show the "Ad Privacy Choices" entry.
  Future<bool> get isPrivacyOptionsRequired async =>
      (await ConsentInformation.instance.getPrivacyOptionsRequirementStatus()) ==
          PrivacyOptionsRequirementStatus.required;
}
