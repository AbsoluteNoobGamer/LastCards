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
}
