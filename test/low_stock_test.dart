import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 11 — deteksi stok menipis: hanya baris satuan DASAR ber-minStock
/// dengan stok terkini < ambang.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addProduct(String pid, String uid, {int? minStock}) async {
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: pid, name: 'P-$pid'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: uid,
          productId: pid,
          isBaseUnit: const Value(true),
          minStock: Value(minStock),
        ));
  }

  Future<void> setStock(String uid, double after) =>
      db.into(db.stockLedger).insert(StockLedgerCompanion.insert(
            id: 'sl-$uid',
            productUnitId: uid,
            type: 'opening',
            qtyChange: after,
            stockAfter: after,
          ));

  test('getLowStockProductIds: hanya yang stok < minStock', () async {
    await addProduct('p1', 'u1', minStock: 5); // stok 3 → menipis
    await setStock('u1', 3);
    await addProduct('p2', 'u2', minStock: 5); // stok 10 → aman
    await setStock('u2', 10);
    await addProduct('p3', 'u3'); // minStock null → tidak dipantau
    await setStock('u3', 0);
    await addProduct('p4', 'u4', minStock: 5); // tanpa ledger → stok 0 < 5

    final ids = await db.getLowStockProductIds();
    expect(ids, {'p1', 'p4'});
  });

  test('watchLowStockCount memancarkan jumlah yang benar', () async {
    await addProduct('p1', 'u1', minStock: 5);
    await setStock('u1', 2);
    await addProduct('p2', 'u2', minStock: 5);
    await setStock('u2', 99);

    expect(await db.watchLowStockCount().first, 1);
  });

  test('stok tepat DI ambang tidak dianggap menipis (strict <)', () async {
    await addProduct('p1', 'u1', minStock: 5);
    await setStock('u1', 5); // tepat 5, bukan < 5
    expect(await db.getLowStockProductIds(), isEmpty);
  });
}
