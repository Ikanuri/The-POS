import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/features/kasir/discount_allocation.dart';

CartItem _item(String id, int price, double qty, {bool priceOverridden = false}) =>
    CartItem(
      productId: id,
      productUnitId: '$id-unit',
      productName: 'Produk $id',
      unitName: 'Pcs',
      qty: qty,
      price: price,
      originalPrice: price,
      costPrice: (price * 0.6).round(),
      priceOverridden: priceOverridden,
    );

double _effQty(CartItem item) => item.qty;

void main() {
  group('allocateCartTotal — tanpa diskon (total == cartTotal)', () {
    test('subtotal & harga per unit sama seperti harga asli tiap baris', () {
      final items = [_item('A', 10000, 2), _item('B', 5000, 3)];
      final lines = allocateCartTotal(
        items: items,
        effectiveQtyOf: _effQty,
        total: 35000, // 10000*2 + 5000*3
        cartTotal: 35000,
      );

      expect(lines.length, 2);
      expect(lines[0].subtotal, 20000);
      expect(lines[0].unitPrice, 10000);
      expect(lines[0].priceOverridden, isFalse);
      expect(lines[1].subtotal, 15000);
      expect(lines[1].unitPrice, 5000);
    });

    test('flag priceOverridden yang sudah true sebelumnya tetap dipertahankan', () {
      final items = [_item('A', 8000, 1, priceOverridden: true)];
      final lines = allocateCartTotal(
          items: items, effectiveQtyOf: _effQty, total: 8000, cartTotal: 8000);
      expect(lines.single.priceOverridden, isTrue);
    });
  });

  group('allocateCartTotal — dengan diskon manual', () {
    test('proporsional ke tiap baris, Σsubtotal persis == total (baris terakhir menyerap sisa)',
        () {
      // Cart asli 35000 (10000*2 + 5000*3), didiskon manual jadi 30000.
      final items = [_item('A', 10000, 2), _item('B', 5000, 3)];
      final lines = allocateCartTotal(
        items: items,
        effectiveQtyOf: _effQty,
        total: 30000,
        cartTotal: 35000,
      );

      final sum = lines.fold<int>(0, (s, l) => s + l.subtotal);
      expect(sum, 30000, reason: 'total harus persis sama, tak boleh selisih akibat pembulatan');
      // Baris terakhir menyerap sisa pembulatan.
      final expectedFirst = (20000 * (30000 / 35000)).round();
      expect(lines[0].subtotal, expectedFirst);
      expect(lines[1].subtotal, 30000 - expectedFirst);
    });

    test('rounding ganjil tetap presisi (Σ tidak meleset walau tiap baris dibulatkan)', () {
      // 3 baris dengan rasio yang menghasilkan pembulatan ganjil.
      final items = [
        _item('A', 3333, 1),
        _item('B', 3333, 1),
        _item('C', 3334, 1),
      ]; // cartTotal = 10000, didiskon jadi 9999 (rasio 0.9999)
      final lines = allocateCartTotal(
        items: items,
        effectiveQtyOf: _effQty,
        total: 9999,
        cartTotal: 10000,
      );
      final sum = lines.fold<int>(0, (s, l) => s + l.subtotal);
      expect(sum, 9999, reason: 'sisa pembulatan wajib diserap baris terakhir, bukan hilang/lebih');
    });

    test('priceOverridden jadi true untuk semua baris saat diskon diterapkan, walau aslinya false',
        () {
      final items = [_item('A', 10000, 1, priceOverridden: false)];
      final lines = allocateCartTotal(
          items: items, effectiveQtyOf: _effQty, total: 8000, cartTotal: 10000);
      expect(lines.single.priceOverridden, isTrue,
          reason: 'struk perlu menandai baris ini sebagai harga ter-override akibat diskon manual');
    });

    test('unitPrice per baris ikut turun proporsional (bukan cuma subtotal)', () {
      final items = [_item('A', 10000, 2)]; // subtotal asli 20000
      final lines = allocateCartTotal(
          items: items, effectiveQtyOf: _effQty, total: 18000, cartTotal: 20000);
      expect(lines.single.subtotal, 18000);
      expect(lines.single.unitPrice, 9000, reason: '18000/2 qty = 9000 per unit');
    });
  });

  group('allocateCartTotal — kasus tepi', () {
    test('item dengan effective qty 0 (induk placeholder varian) dilewati', () {
      final parent = _item('P', 10000, 0); // placeholder, qty efektif 0
      final variant = _item('V', 12000, 1);
      final lines = allocateCartTotal(
        items: [parent, variant],
        effectiveQtyOf: _effQty,
        total: 12000,
        cartTotal: 12000,
      );
      expect(lines.length, 1, reason: 'placeholder induk tidak boleh masuk transaction_items');
      expect(lines.single.item.productId, 'V');
    });

    test('cartTotal 0 tidak menyebabkan pembagian oleh nol (fallback tanpa diskon)', () {
      final items = [_item('A', 0, 0)];
      expect(
        () => allocateCartTotal(
            items: items, effectiveQtyOf: _effQty, total: 0, cartTotal: 0),
        returnsNormally,
      );
    });

    test('keranjang kosong / semua qty 0 → hasil kosong', () {
      final lines = allocateCartTotal(
          items: [_item('A', 5000, 0)], effectiveQtyOf: _effQty, total: 0, cartTotal: 0);
      expect(lines, isEmpty);
    });
  });

  group('applyPercentDiscount — Fase A "Kategori Harga" (mode Diskon %)', () {
    test('contoh dari kasir: 5% dari Rp 317.000, kelipatan 500 turun', () {
      final result = applyPercentDiscount(
        cartTotal: 317000,
        percent: 5,
        multiple: 500,
        direction: RoundDirection.down,
      );
      expect(result.rawDiscount, 15850); // 317000 * 5% = 15850
      expect(317000 - result.rawDiscount, 301150); // mentah
      expect(result.roundedTotal, 301000, reason: 'dibulatkan turun ke kelipatan 500');
    });

    test('kelipatan 500, arah terdekat → 301150 dibulatkan ke 301000 (lebih dekat dari 301500)', () {
      final result = applyPercentDiscount(
        cartTotal: 317000,
        percent: 5,
        multiple: 500,
        direction: RoundDirection.nearest,
      );
      expect(result.roundedTotal, 301000);
    });

    test('kelipatan 500, arah naik → 301150 dibulatkan naik ke 301500', () {
      final result = applyPercentDiscount(
        cartTotal: 317000,
        percent: 5,
        multiple: 500,
        direction: RoundDirection.up,
      );
      expect(result.roundedTotal, 301500);
    });

    test('kelipatan 1000, arah turun', () {
      final result = applyPercentDiscount(
        cartTotal: 317000,
        percent: 5,
        multiple: 1000,
        direction: RoundDirection.down,
      );
      expect(result.roundedTotal, 301000);
    });

    test('kelipatan 100, arah naik — pembulatan halus', () {
      final result = applyPercentDiscount(
        cartTotal: 12345,
        percent: 10,
        multiple: 100,
        direction: RoundDirection.up,
      );
      // 12345 - 1235 (10% dibulatkan) = 11110 -> naik ke kelipatan 100 = 11200
      expect(result.rawDiscount, 1235);
      expect(result.roundedTotal, 11200);
    });

    test('multiple <= 1 berarti tanpa pembulatan (total mentah apa adanya)', () {
      final result = applyPercentDiscount(
        cartTotal: 100000,
        percent: 7,
        multiple: 1,
        direction: RoundDirection.nearest,
      );
      expect(result.roundedTotal, 93000); // 100000 - 7000, tanpa pembulatan
    });

    test('percent 0 atau negatif tidak mengubah total (diskon nihil)', () {
      final result = applyPercentDiscount(
        cartTotal: 100000,
        percent: 0,
        multiple: 500,
        direction: RoundDirection.nearest,
      );
      expect(result.roundedTotal, 100000);
    });

    test('percent di atas 100 di-clamp ke 100 (diskon tidak boleh negatif)', () {
      final result = applyPercentDiscount(
        cartTotal: 100000,
        percent: 150,
        multiple: 500,
        direction: RoundDirection.nearest,
      );
      expect(result.roundedTotal, 0);
    });

    test('hasil tidak pernah melebihi cartTotal walau arah Naik + kelipatan kasar', () {
      // cartTotal kecil, diskon kecil, kelipatan kasar -> rawTotal dekat
      // cartTotal, dibulatkan naik bisa lewati cartTotal tanpa clamp.
      final result = applyPercentDiscount(
        cartTotal: 100,
        percent: 1,
        multiple: 5000,
        direction: RoundDirection.up,
      );
      expect(result.roundedTotal, lessThanOrEqualTo(100));
    });

    test('hasil tidak pernah negatif', () {
      final result = applyPercentDiscount(
        cartTotal: 1000,
        percent: 99,
        multiple: 5000,
        direction: RoundDirection.down,
      );
      expect(result.roundedTotal, greaterThanOrEqualTo(0));
    });
  });
}
