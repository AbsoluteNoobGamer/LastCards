import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_unit_ids.dart';
import 'analytics_service.dart';
import 'consent_service.dart';
import 'purchase_service.dart';

/// Wraps the Google Mobile Ads SDK: interstitial/rewarded preloading +
/// reload-after-show, and a banner-ad factory. Singleton, initialized once
/// from `main()` (mirrors [AudioService]/[CardBackService] — no reactive
/// state to expose via Riverpod).
class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const String _prefsMatchesSinceInterstitialKey = 'ads_matches_since_interstitial';

  /// Show an interstitial every Nth match end. Set to 1 = every match.
  static const int _interstitialFrequency = 1;

  bool _initialized = false;
  bool _canRequestAds = false;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  bool _interstitialLoading = false;
  bool _rewardedLoading = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _canRequestAds = await ConsentService.instance.requestAndShowIfRequired();
    await MobileAds.instance.initialize();
    // Skip preloading entirely for "Remove Ads" purchasers — every show-call
    // site already blocks on this, so a preloaded ad here could never be
    // shown anyway; it was just a guaranteed-wasted request every session.
    if (_canRequestAds && !PurchaseService.instance.adsRemoved.value) {
      _loadInterstitial();
      _loadRewarded();
    }
  }

  /// Creates and loads a banner ad. Caller owns the returned [BannerAd] and
  /// must call `.dispose()` when done with it (see [BannerAdSlot]). Returns
  /// `null` (and calls [onFailedToLoad]) without a valid consent signal.
  BannerAd? createBannerAd({
    required String placement,
    AdSize size = AdSize.banner,
    VoidCallback? onLoaded,
    VoidCallback? onFailedToLoad,
  }) {
    if (!_canRequestAds) {
      onFailedToLoad?.call();
      return null;
    }
    final ad = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded?.call(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          AnalyticsService.instance
              .logAdFailed(placement: placement, reason: 'load_failed');
          onFailedToLoad?.call();
        },
        onAdImpression: (_) =>
            AnalyticsService.instance.logAdImpression(placement: placement),
        onAdClicked: (_) =>
            AnalyticsService.instance.logAdClick(placement: placement),
      ),
    );
    ad.load();
    return ad;
  }

  /// No-ops if a load is already in flight or a loaded ad is already sitting
  /// there unused — otherwise every "not ready yet" retry would stack up
  /// duplicate concurrent load requests.
  void _loadInterstitial() {
    if (_interstitialLoading || _interstitialAd != null) return;
    _interstitialLoading = true;
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          _interstitialAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialAd = null;
              _loadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _interstitialLoading = false;
          _interstitialAd = null;
          if (kDebugMode) debugPrint('AdsService: interstitial failed to load: $error');
        },
      ),
    );
  }

  /// Call once per completed match. Only actually shows an ad every
  /// [_interstitialFrequency]th call (and only if one finished preloading in
  /// time), so this is safe to call unconditionally after every match. No-op
  /// once the player has purchased "Remove Ads".
  ///
  /// Awaiting this call only returns once the ad has actually been dismissed
  /// (or failed to show) — [InterstitialAd.show]'s own Future resolves as
  /// soon as the show request is issued, not when the ad closes, so callers
  /// that don't wait on this would start the next screen/game underneath the
  /// still-visible ad. Callers must `await` this rather than fire-and-forget.
  Future<void> maybeShowInterstitialAfterMatch() async {
    if (PurchaseService.instance.adsRemoved.value) return;
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_prefsMatchesSinceInterstitialKey) ?? 0) + 1;
    if (count < _interstitialFrequency) {
      await prefs.setInt(_prefsMatchesSinceInterstitialKey, count);
      return;
    }
    await prefs.setInt(_prefsMatchesSinceInterstitialKey, 0);

    const placement = 'post_match_interstitial';
    final ad = _interstitialAd;
    if (ad == null) {
      AnalyticsService.instance
          .logAdFailed(placement: placement, reason: 'not_loaded');
      // The previous load didn't win the race against this match ending —
      // kick off another one now so the *next* match has a fresh shot,
      // instead of leaving it to chance whether one gets triggered again.
      _loadInterstitial();
      return;
    }
    _interstitialAd = null;

    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        AnalyticsService.instance.logAdImpression(placement: placement);
      },
      onAdClicked: (ad) {
        AnalyticsService.instance.logAdClick(placement: placement);
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        AnalyticsService.instance
            .logAdFailed(placement: placement, reason: 'show_failed');
        _loadInterstitial();
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    await ad.show();
    await dismissed.future;
  }

  /// No-ops if a load is already in flight or a loaded ad is already sitting
  /// there unused — otherwise every "not ready yet" retry would stack up
  /// duplicate concurrent load requests.
  void _loadRewarded() {
    if (_rewardedLoading || _rewardedAd != null) return;
    _rewardedLoading = true;
    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedLoading = false;
          _rewardedAd = ad;
        },
        onAdFailedToLoad: (error) {
          _rewardedLoading = false;
          _rewardedAd = null;
          if (kDebugMode) debugPrint('AdsService: rewarded ad failed to load: $error');
        },
      ),
    );
  }

  bool get isRewardedAdReady => _rewardedAd != null;

  /// Shows the preloaded rewarded ad. [onEarnedReward] only fires if the
  /// player watches to completion. Returns `false` (without showing anything)
  /// if no ad has finished preloading yet — callers should disable/hide the
  /// "watch ad" button while [isRewardedAdReady] is `false`. [placement]
  /// identifies which surface offered the reward (e.g. "locker_xp_reward"),
  /// since one shared preloaded ad instance backs every rewarded placement.
  Future<bool> showRewardedAd({
    required String placement,
    required void Function(num amount) onEarnedReward,
  }) async {
    final ad = _rewardedAd;
    if (ad == null) {
      AnalyticsService.instance
          .logAdFailed(placement: placement, reason: 'not_loaded');
      // Kick off another load so a subsequent attempt (or the next screen
      // that offers a rewarded placement) has a fresh shot at one being ready.
      _loadRewarded();
      return false;
    }
    _rewardedAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        AnalyticsService.instance.logAdImpression(placement: placement);
      },
      onAdClicked: (ad) {
        AnalyticsService.instance.logAdClick(placement: placement);
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        AnalyticsService.instance
            .logAdFailed(placement: placement, reason: 'show_failed');
        _loadRewarded();
      },
    );
    await ad.show(
      onUserEarnedReward: (_, reward) => onEarnedReward(reward.amount),
    );
    return true;
  }
}
