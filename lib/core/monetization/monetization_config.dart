import 'package:flutter/foundation.dart';

/// Non-consumable IAP — use the **same** product ID in Google Play Console and
/// App Store Connect (one-time purchase, non-consumable).
const String kRemoveAdsProductId = 'remove_ads_lifetime';

const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

/// LastCards Android (AdMob). For Google test banners during dev:
/// `--dart-define=ADMOB_BANNER_ANDROID=ca-app-pub-3940256099942544/6300978111`
const String _prodBannerAndroid = 'ca-app-pub-4446209247875215/3931896362';

const String kAdmobBannerAndroid = String.fromEnvironment(
  'ADMOB_BANNER_ANDROID',
  defaultValue: _prodBannerAndroid,
);

const String kAdmobBannerIos = String.fromEnvironment(
  'ADMOB_BANNER_IOS',
  defaultValue: _testBannerIos,
);

const String _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';

/// LastCards Android post-game interstitial. For Google test interstitials during dev:
/// `--dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-3940256099942544/1033173712`
const String _prodInterstitialAndroid = 'ca-app-pub-4446209247875215/6454117927';

const String kAdmobInterstitialAndroid = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_ANDROID',
  defaultValue: _prodInterstitialAndroid,
);

const String kAdmobInterstitialIos = String.fromEnvironment(
  'ADMOB_INTERSTITIAL_IOS',
  defaultValue: _testInterstitialIos,
);

const String _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

/// Rewarded — offline tournament skip (Android). For Google test rewarded during dev:
/// `--dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-3940256099942544/5224354917`
const String _prodRewardedAndroid = 'ca-app-pub-4446209247875215/9319954415';

const String kAdmobRewardedAndroid = String.fromEnvironment(
  'ADMOB_REWARDED_ANDROID',
  defaultValue: _prodRewardedAndroid,
);

const String kAdmobRewardedIos = String.fromEnvironment(
  'ADMOB_REWARDED_IOS',
  defaultValue: _testRewardedIos,
);

bool kSupportsStoreMonetization() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String kBannerAdUnitIdForPlatform() {
  if (kIsWeb) return '';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return kAdmobBannerAndroid;
    case TargetPlatform.iOS:
      return kAdmobBannerIos;
    default:
      return '';
  }
}

String kInterstitialAdUnitIdForPlatform() {
  if (kIsWeb) return '';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return kAdmobInterstitialAndroid;
    case TargetPlatform.iOS:
      return kAdmobInterstitialIos;
    default:
      return '';
  }
}

String kRewardedAdUnitIdForPlatform() {
  if (kIsWeb) return '';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return kAdmobRewardedAndroid;
    case TargetPlatform.iOS:
      return kAdmobRewardedIos;
    default:
      return '';
  }
}
