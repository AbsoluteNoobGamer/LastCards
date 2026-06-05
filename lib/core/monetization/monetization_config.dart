import 'package:flutter/foundation.dart';

/// Non-consumable IAP — Google Play only (Android free tier). iOS is paid with no ads.
const String kRemoveAdsProductId = 'remove_ads_lifetime';

/// LastCards Android (AdMob). For Google test banners during dev:
/// `--dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-3940256099942544/6300978111`
const String _prodBannerAndroid = 'ca-app-pub-4446209247875215/3931896362';

const String kAdmobBannerAndroid = String.fromEnvironment(
  'ADMOB_BANNER_ANDROID',
  defaultValue: _prodBannerAndroid,
);

/// LastCards Android post-game interstitial. For Google test interstitials during dev:
/// `--dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-3940256099942544/1033173712`
const String _prodInterstitialAndroid = 'ca-app-pub-4446209247875215/6454117927';

const String kAdmobInterstitialAndroid = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_ANDROID',
  defaultValue: _prodInterstitialAndroid,
);

/// Rewarded — offline tournament skip (Android). For Google test rewarded during dev:
/// `--dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-3940256099942544/5224354917`
const String _prodRewardedAndroid = 'ca-app-pub-4446209247875215/9319954415';

const String kAdmobRewardedAndroid = String.fromEnvironment(
  'ADMOB_REWARDED_ANDROID',
  defaultValue: _prodRewardedAndroid,
);

/// Ads and remove-ads IAP — Android free tier only. iOS is a paid app with no ads.
bool kShowsAdsOnPlatform() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

String kBannerAdUnitIdForPlatform() {
  if (!kShowsAdsOnPlatform()) return '';
  return kAdmobBannerAndroid;
}

String kInterstitialAdUnitIdForPlatform() {
  if (!kShowsAdsOnPlatform()) return '';
  return kAdmobInterstitialAndroid;
}

String kRewardedAdUnitIdForPlatform() {
  if (!kShowsAdsOnPlatform()) return '';
  return kAdmobRewardedAndroid;
}
