import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 17 — harga di daftar produk harus reaktif terhadap perubahan tier
/// harga, bukan snapshot sekali (bug lama: `_basePricesProvider` FutureProvider
/// tidak refresh selama widget produk_list_screen masih hidup di Navigator
/// stack, mis. setelah kembali dari edit produk via `push`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('watchBaseUnitPrices() memancarkan map baru setelah tier harga '
      'minQty=1 diubah', () async {
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 2500),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final stream = db.watchBaseUnitPrices();
    final emissions = <Map<String, int>>[];
    final sub = stream.listen(emissions.add);

    // Tunggu emisi pertama (harga awal).
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 10));
      return emissions.isEmpty;
    }).timeout(const Duration(seconds: 5));
    expect(emissions.last['p1'], 2500);

    // Ubah harga tier minQty=1 (simulasi edit di form Produk).
    await (db.update(db.priceTiers)..where((t) => t.id.equals('t1')))
        .write(const PriceTiersCompanion(price: Value(8000)));

    // Tunggu emisi baru merefleksikan harga terbaru.
    await Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 10));
      return emissions.last['p1'] != 8000;
    }).timeout(const Duration(seconds: 5));
    expect(emissions.last['p1'], 8000,
        reason: 'stream harus emit ulang begitu tier harga berubah');

    await sub.cancel();
  });
}
