import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/utils/price_category_calc.dart';

/// Susulan "assign ke Kategori Harga langsung dari Edit Produk" — varian
/// (produk anak) sudah punya `AltPrices` sendiri (independen dari induk,
/// lihat dok `AltPriceInput`), jadi baris kategori-nya HARUS ikut tersimpan
/// lewat `createVariant`/`updateVariant` persis pola Harga Lain manual
/// (`variant_alt_prices_test.dart`), bukan cuma label+price statis.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<String> seedParent({int basePrice = 10000, int costPrice = 6000}) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Kopi'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'p1_u', productId: 'p1', isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: 'p1_tier',
          productUnitId: 'p1_u',
          minQty: const Value(1),
          price: basePrice,
          costPrice: Value(costPrice),
        ));
    return 'p1';
  }

  test(
      'createVariant: baris Harga Lain category-linked tersimpan lengkap '
      '(priceCategoryId+marginAnchor+marginType+marginValue), harga live-'
      'computed dari getAltPrices', () async {
    final parentId = await seedParent();
    final catId = await db.addPriceCategory('Grosir');

    final variantId = await db.createVariant(
      parentProductId: parentId,
      name: 'Kopi Sachet',
      price: 2000,
      costPrice: 1200,
      unitTypeId: 1,
      altPrices: [
        (
          label: 'Grosir',
          price: 2400, // snapshot awal (20% dari 2000)
          priceCategoryId: catId,
          marginAnchor: kMarginAnchorDasar,
          marginType: kMarginTypePercent,
          marginValue: 20,
        ),
      ],
    );

    final units = await db.getProductUnits(variantId);
    final unit = AppDatabase.variantSaleUnit(units)!;
    final alts = await db.getAltPrices(unit.id);
    expect(alts, hasLength(1));
    expect(alts.single.priceCategoryId, catId);
    expect(alts.single.marginAnchor, kMarginAnchorDasar);
    expect(alts.single.marginType, kMarginTypePercent);
    expect(alts.single.marginValue, 20);
    expect(alts.single.price, 2400);

    // Harga dasar varian dinaikkan -> baris kategori harus ikut LIVE
    // (bukan beku), persis semantik AltPrices/getAltPrices utk produk biasa.
    await (db.update(db.priceTiers)
          ..where((t) => t.productUnitId.equals(unit.id) & t.minQty.equals(1)))
        .write(const PriceTiersCompanion(price: Value(5000)));
    final altsAfter = await db.getAltPrices(unit.id);
    expect(altsAfter.single.price, 6000, // 5000 * 1.2
        reason: 'baris category-linked varian harus live-computed juga');
  });

  test(
      'updateVariant: mengganti Harga Lain manual jadi category-linked '
      '(dan sebaliknya) tersimpan sesuai altPrices baru', () async {
    final parentId = await seedParent();
    final catId = await db.addPriceCategory('Rokok');

    final variantId = await db.createVariant(
      parentProductId: parentId,
      name: 'Kopi Sachet',
      price: 2000,
      costPrice: 1200,
      unitTypeId: 1,
      altPrices: const [
        (
          label: 'Manual',
          price: 1800,
          priceCategoryId: null,
          marginAnchor: null,
          marginType: null,
          marginValue: null,
        ),
      ],
    );
    final unit =
        AppDatabase.variantSaleUnit(await db.getProductUnits(variantId))!;

    await db.updateVariant(
      variantProductId: variantId,
      name: 'Kopi Sachet',
      price: 2000,
      altPrices: [
        (
          label: 'Rokok',
          price: 2200,
          priceCategoryId: catId,
          marginAnchor: kMarginAnchorModal,
          marginType: kMarginTypeFixed,
          marginValue: 1000,
        ),
      ],
    );

    final alts = await db.getAltPrices(unit.id);
    expect(alts, hasLength(1));
    expect(alts.single.priceCategoryId, catId);
    expect(alts.single.marginAnchor, kMarginAnchorModal);
    expect(alts.single.marginType, kMarginTypeFixed);
    expect(alts.single.marginValue, 1000);
    expect(alts.single.price, 2200, reason: '1200 (costPrice) + 1000');
  });
}
