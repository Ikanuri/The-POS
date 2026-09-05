import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/price_service.dart';

/// Fase C "Kategori Harga" — level DB murni:
/// `PriceService.resolvePrice(activeCategoryId:)` & `AppDatabase.
/// getCategoryPriceFor`. Prioritas resolusi (di LUAR fungsi ini, level
/// pemanggil `cart_sheet.dart`, manual override selalu menang duluan):
/// kategori aktif > customerGroup > qty-tier > base.
void main() {
  late AppDatabase db;
  late PriceService priceService;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    priceService = PriceService(db);
  });
  tearDown(() async => db.close());

  Future<String> seedProduct({
    required String id,
    required int basePrice,
    required int costPrice,
    List<(int minQty, int price, int cost)> extraTiers = const [],
  }) async {
    await db
        .into(db.products)
        .insert(ProductsCompanion.insert(id: id, name: 'Produk $id'));
    final unitId = '${id}_u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: unitId, productId: id, isBaseUnit: const Value(true)));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '${id}_tier1',
          productUnitId: unitId,
          minQty: const Value(1),
          price: basePrice,
          costPrice: Value(costPrice),
        ));
    for (final (minQty, price, cost) in extraTiers) {
      await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
            id: '${id}_tier_$minQty',
            productUnitId: unitId,
            minQty: Value(minQty),
            price: price,
            costPrice: Value(cost),
          ));
    }
    return unitId;
  }

  Future<String> addCategoryMember({
    required String unitId,
    required int categoryPrice,
  }) async {
    final catId = await db.addPriceCategory('Grosir');
    // marginType null/marginValue null -> baris manual (bukan margin-based)
    // TAPI priceCategoryId terisi -> tetap dianggap ANGGOTA kategori
    // (getCategoryPriceFor tidak mensyaratkan margin terisi, cukup baris
    // AltPrices yg cocok productUnitId+priceCategoryId ada).
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: '${unitId}_alt_$categoryPrice',
          productUnitId: unitId,
          label: 'Grosir',
          price: categoryPrice,
          priceCategoryId: Value(catId),
        ));
    return catId;
  }

  group('resolvePrice activeCategoryId', () {
    test('kategori aktif MENANG atas qty-tier & base bila produk terdaftar',
        () async {
      final unitId = await seedProduct(id: 'p1', basePrice: 10000, costPrice: 7000);
      final catId = await addCategoryMember(unitId: unitId, categoryPrice: 8500);

      final resolved = await priceService.resolvePrice(
        productUnitId: unitId,
        qty: 1,
        activeCategoryId: catId,
      );
      expect(resolved.price, 8500);
      expect(resolved.source, PriceSource.category);
      expect(resolved.costPrice, 7000,
          reason: 'HPP diambil dari tier qty yg berlaku, bukan 0 palsu');
    });

    test(
        'produk TIDAK terdaftar di kategori aktif -> fallback normal '
        '(qty-tier/base), activeCategoryId diabaikan', () async {
      final unitId = await seedProduct(id: 'p1', basePrice: 10000, costPrice: 7000);
      // Kategori dibuat tapi produk INI tidak didaftarkan sbg anggotanya.
      final catId = await db.addPriceCategory('Grosir');

      final resolved = await priceService.resolvePrice(
        productUnitId: unitId,
        qty: 1,
        activeCategoryId: catId,
      );
      expect(resolved.price, 10000);
      expect(resolved.source, PriceSource.base);
    });

    test('kategori aktif MENANG atas customer group', () async {
      final unitId = await seedProduct(id: 'p1', basePrice: 10000, costPrice: 7000);
      final catId = await addCategoryMember(unitId: unitId, categoryPrice: 8500);

      const groupId = 'grp1';
      await db.into(db.customerGroups).insert(
          CustomerGroupsCompanion.insert(id: groupId, name: 'Member'));
      await db.into(db.customerGroupPrices).insert(
          CustomerGroupPricesCompanion.insert(
              id: 'cgp1',
              productUnitId: unitId,
              customerGroupId: groupId,
              price: 9000));

      final resolved = await priceService.resolvePrice(
        productUnitId: unitId,
        qty: 1,
        customerGroupId: groupId,
        activeCategoryId: catId,
      );
      expect(resolved.price, 8500,
          reason: 'kategori aktif harus menang atas harga grup pelanggan');
      expect(resolved.source, PriceSource.category);
    });

    test(
        'harga kategori LIVE-computed (margin) -> ikut berubah kalau tier '
        'dasar berubah, tanpa update manual baris AltPrice', () async {
      final unitId = await seedProduct(id: 'p1', basePrice: 10000, costPrice: 7000);
      final catId = await db.addPriceCategory('Grosir');
      await db.setPriceCategoryMargin(
        priceCategoryId: catId,
        productUnitId: unitId,
        categoryName: 'Grosir',
        marginAnchor: 'dasar',
        marginType: 'percent',
        marginValue: 20,
        computedPrice: 12000,
      );

      var resolved = await priceService.resolvePrice(
          productUnitId: unitId, qty: 1, activeCategoryId: catId);
      expect(resolved.price, 12000);

      await (db.update(db.priceTiers)
            ..where(
                (t) => t.productUnitId.equals(unitId) & t.minQty.equals(1)))
          .write(const PriceTiersCompanion(price: Value(20000)));

      resolved = await priceService.resolvePrice(
          productUnitId: unitId, qty: 1, activeCategoryId: catId);
      expect(resolved.price, 24000,
          reason: 'harga kategori harus live, ikut bergerak dgn tier dasar');
    });
  });

  group('getCategoryPriceFor', () {
    test('null bila produk bukan anggota kategori', () async {
      final unitId = await seedProduct(id: 'p1', basePrice: 10000, costPrice: 7000);
      final catId = await db.addPriceCategory('Grosir');
      final price = await db.getCategoryPriceFor(unitId, catId);
      expect(price, isNull);
    });

    test('mengembalikan harga live bila produk anggota', () async {
      final unitId = await seedProduct(id: 'p1', basePrice: 10000, costPrice: 7000);
      final catId = await addCategoryMember(unitId: unitId, categoryPrice: 8500);
      final price = await db.getCategoryPriceFor(unitId, catId);
      expect(price, 8500);
    });
  });
}
