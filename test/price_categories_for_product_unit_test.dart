import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// `getPriceCategoriesForProductUnit` — dipakai deretan chip kategori
/// per-item di baris keranjang (`cart_sheet.dart`). Harus mengembalikan
/// SEMUA kategori yg produk itu tergabung (bisa >1), kosong utk produk yg
/// tidak tergabung kategori apa pun, & mengecualikan kategori ter-tombstone
/// (`name = null`).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> seedUnit(String id) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: id, name: 'Produk $id'));
    final unitId = '${id}_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: id, isBaseUnit: const Value(true)));
    return unitId;
  }

  test('produk TIDAK tergabung kategori apa pun -> list kosong', () async {
    final unitId = await seedUnit('p1');
    final cats = await db.getPriceCategoriesForProductUnit(unitId);
    expect(cats, isEmpty);
  });

  test('produk tergabung >1 kategori -> semuanya dikembalikan, terurut',
      () async {
    final unitId = await seedUnit('p1');
    final catA = await db.addPriceCategory('A Kategori');
    final catB = await db.addPriceCategory('B Kategori');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt_b', productUnitId: unitId, label: 'B', price: 9000,
        priceCategoryId: Value(catB)));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt_a', productUnitId: unitId, label: 'A', price: 8000,
        priceCategoryId: Value(catA)));

    final cats = await db.getPriceCategoriesForProductUnit(unitId);
    expect(cats.map((c) => c.id), [catA, catB],
        reason: 'terurut sortOrder lalu nama, sama pola getAllPriceCategories');
  });

  test('kategori lain (produk beda unit) TIDAK ikut muncul', () async {
    final unitId = await seedUnit('p1');
    final otherUnit = await seedUnit('p2');
    final catId = await db.addPriceCategory('Grosir');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt_other', productUnitId: otherUnit, label: 'Grosir',
        price: 5000, priceCategoryId: Value(catId)));

    final cats = await db.getPriceCategoriesForProductUnit(unitId);
    expect(cats, isEmpty);
  });

  test('AltPrices TANPA priceCategoryId (Harga Lain ad-hoc biasa) TIDAK '
      'dihitung sbg kategori', () async {
    final unitId = await seedUnit('p1');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt_adhoc',
        productUnitId: unitId,
        label: 'Harga Toko A',
        price: 5000));

    final cats = await db.getPriceCategoriesForProductUnit(unitId);
    expect(cats, isEmpty);
  });

  test('kategori ter-tombstone (name=null) dikecualikan', () async {
    final unitId = await seedUnit('p1');
    final catId = await db.addPriceCategory('Akan Dihapus');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'alt_x', productUnitId: unitId, label: 'X', price: 5000,
        priceCategoryId: Value(catId)));
    await db.deletePriceCategory(catId);

    final cats = await db.getPriceCategoriesForProductUnit(unitId);
    expect(cats, isEmpty);
  });
}
