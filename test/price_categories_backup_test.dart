import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/price_category_calc.dart';

/// Bug ditemukan (audit manual): `price_categories` (master "Kategori
/// Harga", Fase B) ADA di skema tapi TIDAK ADA di `_allTables`
/// (`dumpAllTables`/`restoreFromDump`, dipakai backup penuh/"Alihkan
/// Owner"). Restore/Alihkan Owner diam-diam MENGHAPUS SEMUA kategori
/// (nama "Grosir" dkk hilang total) — hanya `alt_prices.priceCategoryId`
/// yang tersisa, jadi orphan.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test(
      'dumpAllTables + restoreFromDump membawa serta price_categories, urutan '
      'FK terjaga (alt_prices.priceCategoryId tidak jadi orphan)', () async {
    // Seed produk + unit dulu supaya alt_prices punya productUnitId valid.
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p1',
          name: 'Beras',
        ));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: 'u1',
          productId: 'p1',
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 't1',
          productUnitId: 'u1',
          price: 10000,
        ));

    final catId = await db.addPriceCategory('Grosir');
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: 'u1',
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypeFixed,
      marginValue: 500,
      computedPrice: 10500,
    );

    final dump = await db.dumpAllTables();
    expect(dump['price_categories']?.any((r) => r['id'] == catId), isTrue,
        reason: 'price_categories harus ikut dumpAllTables — sebelumnya '
            'tabel ini terlewat sama sekali');

    final freshDb = AppDatabase(NativeDatabase.memory());
    addTearDown(() => freshDb.close());
    // restoreFromDump tidak boleh meledak krn urutan FK logis
    // (alt_prices.priceCategoryId -> price_categories.id) salah.
    await freshDb.restoreFromDump(dump);

    final restoredCats = await freshDb.getAllPriceCategories();
    expect(restoredCats.map((c) => c.name), contains('Grosir'),
        reason: 'kategori harus ikut ter-restore, bukan hilang total');

    final restoredAlt = (await freshDb.getAltPrices('u1')).single;
    expect(restoredAlt.priceCategoryId, catId,
        reason: 'alt_prices.priceCategoryId tidak boleh jadi orphan setelah '
            'restore — kategori rujukannya harus sudah ada duluan');
  });
}
