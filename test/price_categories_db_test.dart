import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/price_category_calc.dart';

/// Fase B "Kategori Harga" — level DB murni (`AppDatabase(NativeDatabase.
/// memory())` sungguhan, bukan mock): CRUD `PriceCategories`, harga LIVE
/// (bukan beku) di `getAltPrices`/`getPriceCategoryMembers`, dan semantik
/// hapus kategori vs hapus satu produk dari kategori.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedProduct({
    required String id,
    required String name,
    required int basePrice,
    required int costPrice,
  }) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: id, name: name));
    final unitId = '${id}_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: id, isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '${id}_tier',
          productUnitId: unitId,
          minQty: const Value(1),
          price: basePrice,
          costPrice: Value(costPrice),
        ));
    return unitId;
  }

  test('CRUD kategori: tambah, ubah nama, reorder', () async {
    final id1 = await db.addPriceCategory('Grosir');
    final id2 = await db.addPriceCategory('Ecer Spesial');

    var cats = await db.getAllPriceCategories();
    expect(cats.map((c) => c.name).toList(), ['Grosir', 'Ecer Spesial']);

    await db.renamePriceCategory(id1, 'Grosir Besar');
    cats = await db.getAllPriceCategories();
    expect(cats.firstWhere((c) => c.id == id1).name, 'Grosir Besar');

    // Reorder: id2 duluan.
    await db.reorderPriceCategories([id2, id1]);
    cats = await db.getAllPriceCategories();
    expect(cats.map((c) => c.id).toList(), [id2, id1]);
  });

  test('setPriceCategoryMargin: baris baru dgn anchor dasar + persen',
      () async {
    final catId = await db.addPriceCategory('Grosir');
    final unitId =
        await seedProduct(id: 'p1', name: 'Beras', basePrice: 10000, costPrice: 7000);

    final computed = computeCategoryPrice(
      basePrice: 10000,
      costPrice: 7000,
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypePercent,
      marginValue: 20,
    );
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypePercent,
      marginValue: 20,
      computedPrice: computed,
    );

    final alts = await db.getAltPrices(unitId);
    expect(alts, hasLength(1));
    expect(alts.single.price, 12000);
    expect(alts.single.priceCategoryId, catId);
  });

  test(
      'getAltPrices() mengembalikan harga LIVE: ubah PriceTiers produk, '
      'panggil lagi -> harga kategori ikut berubah TANPA update manual baris '
      'AltPrice', () async {
    final catId = await db.addPriceCategory('Grosir');
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras', basePrice: 10000, costPrice: 7000);

    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypePercent,
      marginValue: 20,
      computedPrice: 12000, // 10000 * 1.2
    );

    var alts = await db.getAltPrices(unitId);
    expect(alts.single.price, 12000);

    // Owner menaikkan harga dasar produk jadi 15000 — TANPA sentuh baris
    // AltPrice sama sekali.
    await (db.update(db.priceTiers)
          ..where((t) => t.productUnitId.equals(unitId) & t.minQty.equals(1)))
        .write(const PriceTiersCompanion(price: Value(15000)));

    alts = await db.getAltPrices(unitId);
    expect(alts.single.price, 18000, // 15000 * 1.2
        reason: 'harga kategori harus ikut bergerak otomatis (live-computed)');
  });

  test(
      'getAltPrices() TIDAK mengubah baris AltPrice lama tanpa kategori '
      '(backward compatible)', () async {
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras', basePrice: 10000, costPrice: 7000);
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'ap-manual',
          productUnitId: unitId,
          label: 'Harga Toko A',
          price: 9500,
        ));

    final alts = await db.getAltPrices(unitId);
    expect(alts.single.price, 9500);
    expect(alts.single.priceCategoryId, isNull);
  });

  test('getPriceCategoryMembers: anggota kategori beserta harga live',
      () async {
    final catId = await db.addPriceCategory('Grosir');
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras', basePrice: 10000, costPrice: 7000);
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorModal,
      marginType: kMarginTypeFixed,
      marginValue: 1000,
      computedPrice: 8000,
    );

    final members = await db.getPriceCategoryMembers(catId);
    expect(members, hasLength(1));
    expect(members.single.productName, 'Beras');
    expect(members.single.currentPrice, 8000); // 7000 + 1000
    expect(members.single.basePrice, 10000);
    expect(members.single.costPrice, 7000);
  });

  test(
      'hapus kategori (deletePriceCategory): baris AltPrice anggota TIDAK '
      'dihapus, hanya priceCategoryId+margin dilepas (jadi harga manual '
      'beku)', () async {
    final catId = await db.addPriceCategory('Grosir');
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras', basePrice: 10000, costPrice: 7000);
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypePercent,
      marginValue: 20,
      computedPrice: 12000,
    );

    await db.deletePriceCategory(catId);

    final cats = await db.getAllPriceCategories();
    expect(cats, isEmpty);

    // Kategori itu sendiri TOMBSTONE (name=null), BUKAN hard delete — baris
    // fisiknya tetap ada di DB (persis pola product_groups) supaya full-dump
    // sync (masterData) bisa merefleksikan penghapusan ini ke klien lain.
    final rawCat = await (db.select(db.priceCategories)
          ..where((t) => t.id.equals(catId)))
        .getSingleOrNull();
    expect(rawCat != null, true,
        reason: 'baris price_categories TIDAK boleh hilang total dari DB');
    expect(rawCat!.name, isNull);

    // Baris AltPrice masih ada, tapi sudah lepas dari kategori & beku.
    final alts = await db.getAltPrices(unitId);
    expect(alts, hasLength(1));
    expect(alts.single.priceCategoryId, isNull);
    expect(alts.single.marginType, isNull);
    expect(alts.single.marginValue, isNull);
    expect(alts.single.price, 12000,
        reason: 'harga snapshot terakhir dipertahankan, bukan direset ke 0');

    // Naikkan harga dasar produk — baris yg sudah lepas TIDAK ikut bergerak
    // lagi (bukan live lagi, murni manual beku).
    await (db.update(db.priceTiers)
          ..where((t) => t.productUnitId.equals(unitId) & t.minQty.equals(1)))
        .write(const PriceTiersCompanion(price: Value(99999)));
    final altsAfter = await db.getAltPrices(unitId);
    expect(altsAfter.single.price, 12000);
  });

  test(
      'lepas satu produk dari kategori (removeProductFromPriceCategory): '
      'baris AltPrice-nya dihapus TOTAL (beda dari hapus kategori massal)',
      () async {
    final catId = await db.addPriceCategory('Grosir');
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras', basePrice: 10000, costPrice: 7000);
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypePercent,
      marginValue: 20,
      computedPrice: 12000,
    );
    final altId = (await db.getAltPrices(unitId)).single.id;

    await db.removeProductFromPriceCategory(altId);

    final alts = await db.getAltPrices(unitId);
    expect(alts, isEmpty);
    // Kategori sendiri masih ada (cuma produk ini yang dicabut).
    final cats = await db.getAllPriceCategories();
    expect(cats.map((c) => c.id), contains(catId));
  });

  test(
      'setPriceCategoryMargin dipanggil 2x utk produk yg sama -> UPDATE '
      'baris yg sama, bukan baris baru (upsert)', () async {
    final catId = await db.addPriceCategory('Grosir');
    final unitId = await seedProduct(
        id: 'p1', name: 'Beras', basePrice: 10000, costPrice: 7000);

    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypePercent,
      marginValue: 20,
      computedPrice: 12000,
    );
    await db.setPriceCategoryMargin(
      priceCategoryId: catId,
      productUnitId: unitId,
      categoryName: 'Grosir',
      marginAnchor: kMarginAnchorDasar,
      marginType: kMarginTypeFixed,
      marginValue: 3000,
      computedPrice: 13000,
    );

    final alts = await db.getAltPrices(unitId);
    expect(alts, hasLength(1),
        reason: 'harus UPDATE baris yang sama, bukan menumpuk baris baru');
    expect(alts.single.price, 13000);
    expect(alts.single.marginType, kMarginTypeFixed);
  });

  test(
      'anchor modal dgn costPrice<=0: getAltPrices tidak crash, fallback ke '
      'snapshot terakhir (data lama/tidak konsisten)', () async {
    final catId = await db.addPriceCategory('Grosir');
    // Produk TANPA HPP (costPrice 0) — kondisi UTAMA menurut briefing,
    // bukan kasus langka.
    final unitId = await seedProduct(
        id: 'p1', name: 'Rokok', basePrice: 10000, costPrice: 0);

    // Simulasikan baris yang (secara tidak konsisten/data lama) tersimpan
    // dgn anchor modal walau costPrice sudah 0 — mis. HPP dihapus belakangan
    // setelah kategori dipasang.
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: 'ap-modal-invalid',
          productUnitId: unitId,
          label: 'Grosir',
          price: 9999, // snapshot lama
          priceCategoryId: const Value('cat-x'),
          marginAnchor: const Value(kMarginAnchorModal),
          marginType: const Value(kMarginTypePercent),
          marginValue: const Value(10),
        ));

    final alts = await db.getAltPrices(unitId);
    expect(alts.single.price, 9999,
        reason: 'fallback ke snapshot lama, tidak crash & tidak menghitung '
            'persen dari costPrice 0');
    // ignore: unused_local_variable
    final _ = catId;
  });
}
