import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/monetization/monetization_config.dart';
import 'package:last_cards/core/monetization/post_game_interstitial.dart';

void main() {
  test('remove-ads product id matches store listing slug', () {
    expect(kRemoveAdsProductId, 'remove_ads_lifetime');
  });

  test('interstitial min interval is policy-friendly (>= 3 min)', () {
    expect(
      kInterstitialMinInterval.inMinutes,
      greaterThanOrEqualTo(3),
    );
  });

  test('Android banner and interstitial default to LastCards AdMob units', () {
    expect(kAdmobBannerAndroid, 'ca-app-pub-4446209247875215/3931896362');
    expect(
      kAdmobInterstitialAndroid,
      'ca-app-pub-4446209247875215/6454117927',
    );
  });

  test('Android rewarded defaults to LastCards skip unit; iOS uses sample test ID', () {
    expect(kAdmobRewardedAndroid, 'ca-app-pub-4446209247875215/9319954415');
    expect(kAdmobRewardedIos, contains('ca-app-pub-3940256099942544'));
  });
}
