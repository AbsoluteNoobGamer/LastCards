import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'monetization_config.dart';

/// Initializes the Mobile Ads SDK once on Android / iOS. No-op on web/desktop.
Future<void> initMobileAdsIfSupported() async {
  if (!kSupportsStoreMonetization()) return;
  await MobileAds.instance.initialize();
}
