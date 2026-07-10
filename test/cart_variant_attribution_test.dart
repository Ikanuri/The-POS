import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';

/// Item 16 — varian menempel ke baris SATUAN spesifik (parentProductUnitId),
/// bukan ke sembarang baris satuan produk yang sama.
CartItem _unit(String unitId, double qty) => CartItem(
      productId: 'P',
      productUnitId: unitId,
      productName: 'Prod',
      unitName: unitId,
      qty: qty,
      price: 1000,
      originalPrice: 1000,
      costPrice: 500,
    );

CartItem _variant(String unitId, double qty, {required String parentUnitId}) =>
    CartItem(
      productId: 'V-$unitId',
      productUnitId: unitId,
      productName: 'Varian',
      unitName: 'pcs',
      qty: qty,
      price: 500,
      originalPrice: 500,
      costPrice: 300,
      isVariant: true,
      parentProductId: 'P',
      parentProductUnitId: parentUnitId,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('varian menempel ke satuan yang BENAR (Pcs), TIDAK menyeret Dus', () {
    final n = CartNotifier('t');
    n.addItem(_unit('dus', 2));
    n.addItem(_unit('pcs', 5));
    n.addItem(_variant('vpcs', 3, parentUnitId: 'pcs'));

    final dus = n.state.firstWhere((c) => c.productUnitId == 'dus');
    final pcs = n.state.firstWhere((c) => c.productUnitId == 'pcs');
    // Dus TIDAK terpengaruh varian yang menempel ke Pcs (bug lama: kena juga).
    expect(dus.qty, 2);
    expect(n.effectiveQtyFor(dus), 2);
    // Pcs storedQty = base 5 + varian 3 = 8; effective = 5 (bukan 2 spt bug).
    expect(pcs.qty, 8);
    expect(n.effectiveQtyFor(pcs), 5);
  });

  test('hapus baris satuan induk cascade-hapus variannya (tak yatim)', () {
    final n = CartNotifier('t');
    n.addItem(_unit('dus', 2));
    n.addItem(_unit('pcs', 5));
    n.addItem(_variant('vpcs', 3, parentUnitId: 'pcs'));

    n.removeItem('pcs');
    // Pcs + variannya hilang; Dus tetap ada, tak tersentuh.
    expect(n.state.map((c) => c.productUnitId).toList(), ['dus']);
    expect(n.state.first.qty, 2);
  });

  test('hapus varian mengembalikan storedQty induk yang BENAR (Pcs), bukan Dus',
      () {
    final n = CartNotifier('t');
    n.addItem(_unit('dus', 2));
    n.addItem(_unit('pcs', 5));
    n.addItem(_variant('vpcs', 3, parentUnitId: 'pcs'));

    n.removeItem('vpcs');
    final dus = n.state.firstWhere((c) => c.productUnitId == 'dus');
    final pcs = n.state.firstWhere((c) => c.productUnitId == 'pcs');
    expect(pcs.qty, 5); // kembali ke base
    expect(dus.qty, 2); // tak tersentuh
  });

  test('cartTotalOf memakai atribusi per-satuan (varian tak dihitung dobel)',
      () {
    final items = [
      _unit('dus', 2), // 2 x 1000 = 2000
      _unit('pcs', 5), // storedQty jadi 8 setelah varian; effective 5 x 1000
      _variant('vpcs', 3, parentUnitId: 'pcs'), // 3 x 500 = 1500
    ];
    // Simulasikan storedQty pcs = 8 (base 5 + varian 3) seperti hasil addItem.
    final withStored = [
      items[0],
      items[1].copyWith(qty: 8),
      items[2],
    ];
    // dus 2000 + pcs effective (8-3=5)*1000=5000 + varian 1500 = 8500.
    expect(cartTotalOf(withStored), 8500);
  });
}
