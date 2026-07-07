import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_unit_ids.dart';

/// Wraps the Google Mobile Ads SDK: interstitial/rewarded preloading +
/// reload-after-show, and a banner-ad factory. Singleton, initialized once
/// from `main()` (mirrors [AudioService]/[CardBackService] — no reactive
/// state to expose via Riverpod).
class AdsService {
  AdsService._();

  static final AdsService instance = AdsService._();

  static const String _prefsMatchesSinceInterstitialKey = 'ads_matches_since_interstitial';

  /// Show an interstitial only every Nth match end, so players aren't shown a
  /// full-screen ad after every single game.
  static const int _interstitialFrequency = 3;

  bool _initialized = false;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  /// Creates and loads a banner ad. Caller owns the returned [BannerAd] and
  /// must call `.dispose()` when done with it (see [BannerAdSlot]).
  BannerAd createBannerAd({
    AdSize size = AdSize.banner,
    VoidCallback? onLoaded,
    VoidCallback? onFailedToLoad,
  }) {
    final ad = BannerAd(
      adUnitId: AdUnitIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onLoaded?.call(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onFailedToLoad?.call();
        },
      ),
    );
    ad.load();
    return ad;
  }

  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: AdUnitIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
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
          _interstitialAd = null;
          if (kDebugMode) debugPrint('AdsService: interstitial failed to load: $error');
        },
      ),
    );
  }

  /// Call once per completed match. Only actually shows an ad every
  /// [_interstitialFrequency]th call (and only if one finished preloading in
  /// time), so this is safe to call unconditionally after every match.
  Future<void> maybeShowInterstitialAfterMatch() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_prefsMatchesSinceInterstitialKey) ?? 0) + 1;
    if (count < _interstitialFrequency) {
      await prefs.setInt(_prefsMatchesSinceInterstitialKey, count);
      return;
    }
    await prefs.setInt(_prefsMatchesSinceInterstitialKey, 0);

    final ad = _interstitialAd;
    if (ad == null) return;
    _interstitialAd = null;
    await ad.show();
  }

  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: AdUnitIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewarded();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              _loadRewarded();
            },
          );
        },
        onAdFailedToLoad: (error) {
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
  /// "watch ad" button while [isRewardedAdReady] is `false`.
  Future<bool> showRewardedAd({
    required void Function(num amount) onEarnedReward,
  }) async {
    final ad = _rewardedAd;
    if (ad == null) return false;
    _rewardedAd = null;
    await ad.show(
      onUserEarnedReward: (_, reward) => onEarnedReward(reward.amount),
    );
    return true;
  }
}
