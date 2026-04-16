import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/core/monetization/monetization_config.dart';

void main() {
  test('remove-ads product id matches store listing slug', () {
    expect(kRemoveAdsProductId, 'remove_ads_lifetime');
  });
}
