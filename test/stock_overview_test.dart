import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 30 — layar "Cek Stok": watchStockOverview() mengembalikan stok riil
/// terurut tertipis dulu, mengecualikan produk non-stok/tidak aktif, DAN
/// (beda dari getBaseUnitRealStock/Item 29) TETAP menampilkan produk yang
/// belum pernah disentuh stoknya sbg 0 — layar ini dibuka owner utk
/// meREVIEW, bukan menyembunyikan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> addProduct(
    String name, {
    int? groupId,
    bool isNonStock = false,
    bool isActive = true,
  }) async {
    final id = 'p-$name';
    final unitId = '$id-u';
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
          productGroupId: Value(groupId),
          isActive: Value(isActive),
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
          isNonStock: Value(isNonStock),
        ));
    return unitId;
  }

  test('produk stok riil belum pernah disentuh TETAP tampil sbg stok 0 '
      '(beda dari getBaseUnitRealStock Item 29 yg menyembunyikannya)',
      () async {
    await addProduct('Belum Dicek');

    final rows = await db.watchStockOverview().first;
    expect(rows.map((r) => r.name), contains('Belum Dicek'));
    expect(rows.firstWhere((r) => r.name == 'Belum Dicek').stock, 0);
  });

  test('urut stok TERTIPIS dulu (ascending)', () async {
    final u1 = await addProduct('Stok Banyak');
    final u2 = await addProduct('Stok Sedikit');
    await db.adjustStock(productUnitId: u1, newQty: 50);
    await db.adjustStock(productUnitId: u2, newQty: 2);

    final rows = await db.watchStockOverview().first;
    final names = rows.map((r) => r.name).toList();
    expect(names.indexOf('Stok Sedikit'), lessThan(names.indexOf('Stok Banyak')));
  });

  test('filter groupId hanya kembalikan produk kategori itu', () async {
    await addProduct('Kategori A', groupId: 1);
    await addProduct('Kategori B', groupId: 2);

    final rowsA = await db.watchStockOverview(groupId: 1).first;
    expect(rowsA.map((r) => r.name), ['Kategori A']);
  });

  test('produk non-stok (isNonStock true) TIDAK muncul di overview',
      () async {
    await addProduct('Jasa', isNonStock: true);
    await addProduct('Barang Fisik');

    final rows = await db.watchStockOverview().first;
    expect(rows.map((r) => r.name), isNot(contains('Jasa')));
    expect(rows.map((r) => r.name), contains('Barang Fisik'));
  });

  test('produk tidak aktif TIDAK muncul di overview', () async {
    await addProduct('Nonaktif', isActive: false);
    final rows = await db.watchStockOverview().first;
    expect(rows.map((r) => r.name), isNot(contains('Nonaktif')));
  });

  test('markedOutOfStock ikut ter-refleksi & reaktif thd toggle', () async {
    await addProduct('Gula');
    var rows = await db.watchStockOverview().first;
    expect(rows.firstWhere((r) => r.name == 'Gula').markedOutOfStock, isFalse);

    await db.setMarkedOutOfStock('p-Gula', true);
    rows = await db.watchStockOverview().first;
    expect(rows.firstWhere((r) => r.name == 'Gula').markedOutOfStock, isTrue);
  });
}
