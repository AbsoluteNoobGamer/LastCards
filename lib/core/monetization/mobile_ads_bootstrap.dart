import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization_config.dart';

/// Initializes the Mobile Ads SDK once on Android. No-op on iOS / web / desktop.
Future<void> initMobileAdsIfSupported() async {
  if (!kShowsAdsOnPlatform()) return;
  await MobileAds.instance.initialize();
}
