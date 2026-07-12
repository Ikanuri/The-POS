import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Harga dasar produk (satuan dasar, tier minQty=1) ditampilkan di daftar
/// Produk — diambil lewat 1 query JOIN (getBaseUnitPrices), bukan N+1.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('getBaseUnitPrices: kembalikan harga tier minQty=1 satuan dasar '
      'tiap produk', () async {
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
        ProductUnitsCompanion.insert(id: 'u2', productId: 'p1'),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2850),
        ],
        // Satuan non-dasar sengaja punya harga BEDA — harus DIABAIKAN.
        'u2': [
          PriceTiersCompanion.insert(id: 't2', productUnitId: 'u2', price: 30000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p2', name: 'Tanpa Harga'),
      units: const [],
      tiersByUnitTempId: const {},
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final prices = await db.getBaseUnitPrices();

    expect(prices['p1'], 2850);
    expect(prices.containsKey('p2'), isFalse,
        reason: 'produk tanpa satuan/harga tidak masuk map');
  });
}
