import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:last_cards/features/gameplay/presentation/layout/table_chrome_layout.dart';

void main() {
  group('TableChromeLayout.overlayScaleFor', () {
    test('phones stay at 1.0', () {
      expect(
        TableChromeLayout.overlayScaleFor(const Size(390, 844)),
        1.0,
      );
      expect(
        TableChromeLayout.overlayScaleFor(const Size(844, 390)),
        1.0,
      );
    });

    test('caps below full chrome scale on large tablets', () {
      // ~13" tablet portrait — shortest side ~1024 logical px.
      const tablet = Size(1024, 1366);
      final chrome = TableChromeLayout.scaleFor(tablet);
      final overlay = TableChromeLayout.overlayScaleFor(tablet);

      expect(chrome, greaterThan(TableChromeLayout.overlayScaleMax));
      expect(overlay, TableChromeLayout.overlayScaleMax);
      expect(overlay, lessThan(chrome));
    });

    test('never exceeds overlayScaleMax', () {
      expect(
        TableChromeLayout.overlayScaleFor(const Size(2000, 3000)),
        TableChromeLayout.overlayScaleMax,
      );
    });
  });
}
