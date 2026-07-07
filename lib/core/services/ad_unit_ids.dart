import 'dart:io' show Platform;

/// AdMob App IDs and ad unit IDs.
///
/// The **App IDs** below are the real Last Cards AdMob account IDs (wired
/// into `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`
/// as well — those must match these).
///
/// The **ad unit IDs** are still Google's official public test units
/// (https://developers.google.com/admob/flutter/test-ads#test_ad_unit_ids).
/// Test units always fill with a "Test Ad" placeholder and are safe to ship
/// during development — they never generate real revenue or trip AdMob
/// policy reviews. Replace each constant below with a real ad unit ID from
/// the AdMob console before release.
abstract final class AdUnitIds {
  static const String androidAppId = 'ca-app-pub-4446209247875215~7842641622';
  static const String iosAppId = 'ca-app-pub-4446209247875215~9617723886';

  // TODO(ads): replace with real ad unit IDs from the AdMob console before release.
  static const String _androidBannerTest = 'ca-app-pub-3940256099942544/6300978111';
  static const String _iosBannerTest = 'ca-app-pub-3940256099942544/2934735716';

  static const String _androidInterstitialTest = 'ca-app-pub-3940256099942544/1033173712';
  static const String _iosInterstitialTest = 'ca-app-pub-3940256099942544/4411468910';

  static const String _androidRewardedTest = 'ca-app-pub-3940256099942544/5224354917';
  static const String _iosRewardedTest = 'ca-app-pub-3940256099942544/1712485313';

  static String get banner => Platform.isIOS ? _iosBannerTest : _androidBannerTest;
  static String get interstitial =>
      Platform.isIOS ? _iosInterstitialTest : _androidInterstitialTest;
  static String get rewarded => Platform.isIOS ? _iosRewardedTest : _androidRewardedTest;
}
