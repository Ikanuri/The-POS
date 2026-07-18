import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Permintaan user: "Opsi add kategori produk tambahkan bulk add dan bulk
/// remove" — test DB-tier utk `addProductGroups`/`deleteProductGroups`
/// (logika inti, dites langsung terhadap DB sungguhan, bukan reimplementasi
/// di test).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('addProductGroups: banyak nama sekaligus (satu per baris) semua '
      'tersimpan, baris kosong dilewati', () async {
    final added = await db.addProductGroups(
        ['Minuman', '', '  Makanan  ', '\n', 'Snack']);
    expect(added, 3, reason: 'baris kosong/whitespace tidak dihitung');

    final groups = await db.getAllProductGroups();
    expect(groups.map((g) => g.name), containsAll(['Minuman', 'Makanan', 'Snack']));
  });

  test('addProductGroups: nama di-trim sebelum disimpan', () async {
    await db.addProductGroups(['  Rokok  ']);
    final groups = await db.getAllProductGroups();
    expect(groups.single.name, 'Rokok');
  });

  test('deleteProductGroups: banyak kategori sekaligus terhapus, produk yg '
      'memakainya jadi tanpa kategori', () async {
    await db.addProductGroups(['A', 'B', 'C']);
    final groups = await db.getAllProductGroups();
    final idA = groups.firstWhere((g) => g.name == 'A').id;
    final idB = groups.firstWhere((g) => g.name == 'B').id;
    final idC = groups.firstWhere((g) => g.name == 'C').id;

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'p1', name: 'Produk A', productGroupId: Value(idA)));

    await db.deleteProductGroups([idA, idB]);

    final remaining = await db.getAllProductGroups();
    expect(remaining.map((g) => g.name), ['C']);
    expect(remaining.single.id, idC);

    final product =
        (await (db.select(db.products)..where((t) => t.name.equals('Produk A')))
            .getSingle());
    expect(product.productGroupId, isNull,
        reason: 'produk yg kategorinya dihapus massal harus jadi tanpa kategori');
  });
}
