import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/services/price_service.dart';
import 'package:the_pos/features/kasir/cart_price_category_provider.dart';

/// Fase C "Kategori Harga" — level DB murni (tanpa widget): logika re-price
/// massal [repriceCartForCategoryChange] yang dipanggil `cart_sheet.dart`
/// tiap toggle kategori berganti. Manual override SELALU menang, prioritas
/// & arah "kembali normal" sesuai briefing.
void main() {
  late AppDatabase db;
  late PriceService priceService;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    priceService = PriceService(db);
  });
  tearDown(() async => db.close());

  Future<String> seedProduct(String id, int basePrice, int costPrice) async {
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
    return unitId;
  }

  Future<String> makeCategory(String unitId, int categoryPrice,
      {String label = 'Grosir'}) async {
    final catId = await db.addPriceCategory(label);
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
          id: '${unitId}_alt_$label',
          productUnitId: unitId,
          label: label,
          price: categoryPrice,
          priceCategoryId: Value(catId),
        ));
    return catId;
  }

  CartItem item(String productId, String unitId, int price, int cost,
      {bool overridden = false, String? fromCategoryId, double qty = 1}) {
    return CartItem(
      productId: productId,
      productUnitId: unitId,
      productName: 'Produk $productId',
      unitName: 'Pcs',
      qty: qty,
      price: price,
      originalPrice: price,
      costPrice: cost,
      priceOverridden: overridden,
      priceFromCategoryId: fromCategoryId,
    );
  }

  test('toggle ON: baris anggota kategori berubah harga+ditandai, baris '
      'BUKAN anggota dibiarkan apa adanya', () async {
    final memberUnit = await seedProduct('member', 10000, 7000);
    final catId = await makeCategory(memberUnit, 8500);
    final otherUnit = await seedProduct('other', 5000, 3000);

    final cart = [
      item('member', memberUnit, 10000, 7000),
      item('other', otherUnit, 5000, 3000),
    ];

    final result = await repriceCartForCategoryChange(
      priceService: priceService,
      cart: cart,
      newCategoryId: catId,
    );

    final memberLine = result.firstWhere((c) => c.productId == 'member');
    expect(memberLine.price, 8500);
    expect(memberLine.priceFromCategoryId, catId);

    final otherLine = result.firstWhere((c) => c.productId == 'other');
    expect(otherLine.price, 5000, reason: 'bukan anggota -> tidak berubah');
    expect(otherLine.priceFromCategoryId, isNull);
  });

  test('baris priceOverridden TIDAK PERNAH disentuh walau anggota kategori '
      'aktif', () async {
    final memberUnit = await seedProduct('member', 10000, 7000);
    final catId = await makeCategory(memberUnit, 8500);

    final cart = [
      item('member', memberUnit, 12345, 7000, overridden: true),
    ];

    final result = await repriceCartForCategoryChange(
      priceService: priceService,
      cart: cart,
      newCategoryId: catId,
    );

    expect(result.single.price, 12345,
        reason: 'manual override harus tetap menang, tidak boleh ditimpa');
    expect(result.single.priceFromCategoryId, isNull);
  });

  test('toggle OFF (newCategoryId null): baris yg SEBELUMNYA category-priced '
      'kembali ke harga normal (base/qty-tier), bukan nyangkut di harga '
      'kategori', () async {
    final memberUnit = await seedProduct('member', 10000, 7000);
    final catId = await makeCategory(memberUnit, 8500);

    final cart = [
      item('member', memberUnit, 8500, 7000, fromCategoryId: catId),
    ];

    final result = await repriceCartForCategoryChange(
      priceService: priceService,
      cart: cart,
      newCategoryId: null,
    );

    expect(result.single.price, 10000,
        reason: 'harus kembali ke harga dasar, bukan tetap 8500');
    expect(result.single.priceFromCategoryId, isNull);
  });

  test('ganti kategori A -> B: anggota B direprice ke harga B; baris yg '
      'HANYA anggota A (bukan B) kembali normal', () async {
    final unitBoth = await seedProduct('both', 10000, 7000);
    final unitOnlyA = await seedProduct('onlyA', 6000, 4000);
    final catA = await db.addPriceCategory('A');
    final catB = await db.addPriceCategory('B');
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'both_a', productUnitId: unitBoth, label: 'A', price: 9000,
        priceCategoryId: Value(catA)));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'both_b', productUnitId: unitBoth, label: 'B', price: 9500,
        priceCategoryId: Value(catB)));
    await db.into(db.altPrices).insert(AltPricesCompanion.insert(
        id: 'onlyA_a', productUnitId: unitOnlyA, label: 'A', price: 5500,
        priceCategoryId: Value(catA)));

    final cart = [
      item('both', unitBoth, 9000, 7000, fromCategoryId: catA),
      item('onlyA', unitOnlyA, 5500, 4000, fromCategoryId: catA),
    ];

    final result = await repriceCartForCategoryChange(
      priceService: priceService,
      cart: cart,
      newCategoryId: catB,
    );

    final bothLine = result.firstWhere((c) => c.productId == 'both');
    expect(bothLine.price, 9500);
    expect(bothLine.priceFromCategoryId, catB);

    final onlyALine = result.firstWhere((c) => c.productId == 'onlyA');
    expect(onlyALine.price, 6000, reason: 'kembali ke harga dasar (bukan B)');
    expect(onlyALine.priceFromCategoryId, isNull);
  });

  test('baris yg tidak pernah category-priced & tetap bukan anggota kategori '
      'baru dibiarkan sama sekali tidak berubah', () async {
    final unitUnrelated = await seedProduct('unrelated', 3000, 2000);
    final catId = await db.addPriceCategory('Grosir');

    final cart = [item('unrelated', unitUnrelated, 3000, 2000)];
    final result = await repriceCartForCategoryChange(
      priceService: priceService,
      cart: cart,
      newCategoryId: catId,
    );
    expect(result.single.price, 3000);
    expect(result.single.priceFromCategoryId, isNull);
  });
}
