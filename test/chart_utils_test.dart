import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/utils/chart_utils.dart';

void main() {
  group('clampedBarHeight', () {
    test('nilai positif normal diskalakan proporsional ke maxHeight', () {
      expect(clampedBarHeight(50, 100), 35); // 50/100*70
      expect(clampedBarHeight(100, 100), 70, reason: 'nilai == max → tinggi penuh');
    });

    test('nilai NEGATIF (omzet/qty hari didominasi retur) di-clamp ke 0, TIDAK crash',
        () {
      expect(clampedBarHeight(-5000, 10000), 0);
      expect(() => clampedBarHeight(-999999, 100), returnsNormally);
    });

    test('nilai melebihi max (defensif) di-clamp ke max, bukan meluber', () {
      expect(clampedBarHeight(150, 100), 70);
    });

    test('max <= 0 (tidak ada data positif sama sekali) → emptyHeight, bukan pembagian nol', () {
      expect(clampedBarHeight(0, 0), 2, reason: 'default emptyHeight = 2');
      expect(clampedBarHeight(-10, -5), 2);
      expect(() => clampedBarHeight(5, 0), returnsNormally);
    });

    test('parameter maxHeight & emptyHeight custom dihormati', () {
      expect(clampedBarHeight(50, 100, maxHeight: 40), 20);
      expect(clampedBarHeight(0, 0, emptyHeight: 0), 0,
          reason: 'dipakai _HourlyChart yang emptyHeight-nya 0, bukan 2');
    });
  });
}
