import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 30(c) — laporan analitik/audit stok: getInventoryRows() jadi dasar
/// nilai inventori (stok × harga pokok), deteksi harga pokok kosong, & daftar
/// stok negatif. Query mentah, agregasi dihitung di layer UI.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> addProduct(
    String name, {
    int? groupId,
    int costPrice = 0,
  }) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
          productGroupId: Value(groupId),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '$unitId-t1',
          productUnitId: unitId,
          minQty: const Value(1),
          price: 10000,
          costPrice: Value(costPrice),
        ));
    return unitId;
  }

  test('stok × harga pokok bisa dihitung dari baris mentah', () async {
    final unitId = await addProduct('Gula', costPrice: 12000);
    await db.adjustStock(productUnitId: unitId, newQty: 5);

    final rows = await db.getInventoryRows();
    final row = rows.firstWhere((r) => r.name == 'Gula');
    expect(row.stock, 5);
    expect(row.costPrice, 12000);
    expect(row.stock * row.costPrice, 60000);
  });

  test('produk tanpa tier harga (LEFT JOIN kosong) costPrice default 0, '
      'bukan crash', () async {
    const id = 'p-TanpaHarga';
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: id, name: 'Tanpa Harga'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: '$id-u',
          productId: id,
          isBaseUnit: const Value(true),
        ));

    final rows = await db.getInventoryRows();
    final row = rows.firstWhere((r) => r.name == 'Tanpa Harga');
    expect(row.costPrice, 0);
  });

  test('stok negatif tetap muncul di baris mentah (utk daftar audit stok '
      'negatif)', () async {
    final unitId = await addProduct('Minus', costPrice: 5000);
    await db.adjustStock(productUnitId: unitId, newQty: -3);

    final rows = await db.getInventoryRows();
    final row = rows.firstWhere((r) => r.name == 'Minus');
    expect(row.stock, -3);
  });

  test('groupId ikut terbawa utk agregasi per-kategori', () async {
    await addProduct('A', groupId: 7, costPrice: 1000);
    final rows = await db.getInventoryRows();
    expect(rows.firstWhere((r) => r.name == 'A').groupId, 7);
  });
}
