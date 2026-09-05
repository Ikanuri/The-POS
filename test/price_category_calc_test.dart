import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/utils/price_category_calc.dart';

/// Test murni utk `computeCategoryPrice`/`computeMarginValue` (Fase B
/// "Kategori Harga") — sengaja tanpa DB, lihat dok library.
void main() {
  group('computeCategoryPrice', () {
    test('persen dari harga dasar', () {
      // 10000 * (1 + 20/100) = 12000
      expect(
        computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypePercent,
          marginValue: 20,
        ),
        12000,
      );
    });

    test('persen dari harga modal', () {
      // 7000 * (1 + 15/100) = 8050
      expect(
        computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypePercent,
          marginValue: 15,
        ),
        8050,
      );
    });

    test('fixed (Rp tetap) dari harga dasar', () {
      expect(
        computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypeFixed,
          marginValue: 2500,
        ),
        12500,
      );
    });

    test('fixed dari harga modal', () {
      expect(
        computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypeFixed,
          marginValue: 500,
        ),
        7500,
      );
    });

    test('margin negatif (rugi sengaja/diskon) tetap dihitung apa adanya', () {
      expect(
        computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypeFixed,
          marginValue: -1000,
        ),
        9000,
      );
    });

    test('pembulatan ke rupiah terdekat (.5 ke atas)', () {
      // 10000 * (1 + 12.345/100) = 11234.5 -> round() Dart membulatkan
      // .5 ke atas utk bilangan positif.
      expect(
        computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypePercent,
          marginValue: 12.345,
        ),
        11235,
      );
    });

    test('pembulatan ke bawah', () {
      // 10000 * 1.1234 = 11234.0 (bukan kasus .5, tapi verifikasi truncation
      // arah yang benar): 10033 + 0.4 -> round ke 10033
      expect(
        computeCategoryPrice(
          basePrice: 10033,
          costPrice: 7000,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypeFixed,
          marginValue: 0.4,
        ),
        10033,
      );
    });

    test('guard: anchor modal dgn costPrice<=0 melempar ArgumentError', () {
      expect(
        () => computeCategoryPrice(
          basePrice: 10000,
          costPrice: 0,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypePercent,
          marginValue: 10,
        ),
        throwsArgumentError,
      );
    });

    test('guard: anchor modal dgn costPrice negatif juga melempar', () {
      expect(
        () => computeCategoryPrice(
          basePrice: 10000,
          costPrice: -500,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypeFixed,
          marginValue: 10,
        ),
        throwsArgumentError,
      );
    });

    test('anchor dasar dgn costPrice<=0 TETAP aman (tidak pakai costPrice)',
        () {
      expect(
        computeCategoryPrice(
          basePrice: 10000,
          costPrice: 0,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypePercent,
          marginValue: 10,
        ),
        11000,
      );
    });

    test('marginAnchor tidak dikenal melempar ArgumentError', () {
      expect(
        () => computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: 'ngasal',
          marginType: kMarginTypeFixed,
          marginValue: 10,
        ),
        throwsArgumentError,
      );
    });

    test('marginType tidak dikenal melempar ArgumentError', () {
      expect(
        () => computeCategoryPrice(
          basePrice: 10000,
          costPrice: 7000,
          marginAnchor: kMarginAnchorDasar,
          marginType: 'ngasal',
          marginValue: 10,
        ),
        throwsArgumentError,
      );
    });
  });

  group('computeMarginValue (arah kebalikan: dari harga jual target)', () {
    test('persen dari harga dasar', () {
      // (12000 - 10000) / 10000 * 100 = 20
      expect(
        computeMarginValue(
          basePrice: 10000,
          costPrice: 7000,
          sellPrice: 12000,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypePercent,
        ),
        20,
      );
    });

    test('persen dari harga modal', () {
      // (8050 - 7000) / 7000 * 100 = 15
      expect(
        computeMarginValue(
          basePrice: 10000,
          costPrice: 7000,
          sellPrice: 8050,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypePercent,
        ),
        closeTo(15, 0.0001),
      );
    });

    test('fixed dari harga dasar', () {
      expect(
        computeMarginValue(
          basePrice: 10000,
          costPrice: 7000,
          sellPrice: 12500,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypeFixed,
        ),
        2500,
      );
    });

    test('fixed dari harga modal', () {
      expect(
        computeMarginValue(
          basePrice: 10000,
          costPrice: 7000,
          sellPrice: 7500,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypeFixed,
        ),
        500,
      );
    });

    test('roundtrip: computeMarginValue lalu computeCategoryPrice kembali'
        ' ke harga jual yang sama (dibulatkan)', () {
      const basePrice = 15750;
      const costPrice = 9200;
      const sellTarget = 21000;
      final margin = computeMarginValue(
        basePrice: basePrice,
        costPrice: costPrice,
        sellPrice: sellTarget,
        marginAnchor: kMarginAnchorModal,
        marginType: kMarginTypePercent,
      );
      final back = computeCategoryPrice(
        basePrice: basePrice,
        costPrice: costPrice,
        marginAnchor: kMarginAnchorModal,
        marginType: kMarginTypePercent,
        marginValue: margin,
      );
      expect(back, sellTarget);
    });

    test('guard: anchor modal dgn costPrice<=0 melempar ArgumentError', () {
      expect(
        () => computeMarginValue(
          basePrice: 10000,
          costPrice: 0,
          sellPrice: 12000,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypePercent,
        ),
        throwsArgumentError,
      );
    });

    test('marginType tidak dikenal melempar ArgumentError', () {
      expect(
        () => computeMarginValue(
          basePrice: 10000,
          costPrice: 7000,
          sellPrice: 12000,
          marginAnchor: kMarginAnchorDasar,
          marginType: 'ngasal',
        ),
        throwsArgumentError,
      );
    });
  });
}
