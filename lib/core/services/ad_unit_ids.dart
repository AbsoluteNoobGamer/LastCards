import 'dart:io' show Platform;

/// AdMob App IDs and ad unit IDs — all real, live Last Cards AdMob units.
///
/// The **App IDs** are wired into `android/app/src/main/AndroidManifest.xml`
/// and `ios/Runner/Info.plist` as well — those must match these.
abstract final class AdUnitIds {
  static const String androidAppId = 'ca-app-pub-4446209247875215~7842641622';
  static const String iosAppId = 'ca-app-pub-4446209247875215~9617723886';

  static const String _androidBanner = 'ca-app-pub-4446209247875215/8786760462';
  static const String _iosBanner = 'ca-app-pub-4446209247875215/9037243141';

  static const String _androidInterstitial = 'ca-app-pub-4446209247875215/6059726012';
  static const String _iosInterstitial = 'ca-app-pub-4446209247875215/8713809513';

  static const String _androidRewarded = 'ca-app-pub-4446209247875215/4746644346';
  static const String _iosRewarded = 'ca-app-pub-4446209247875215/2120481003';

  static String get banner => Platform.isIOS ? _iosBanner : _androidBanner;
  static String get interstitial =>
      Platform.isIOS ? _iosInterstitial : _androidInterstitial;
  static String get rewarded => Platform.isIOS ? _iosRewarded : _androidRewarded;
}
