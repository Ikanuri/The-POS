import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 53 (permintaan user): saklar "Ikut harga satuan dasar" — begitu
/// harga satuan dasar produk INDUK diubah (lewat `saveProduct`, jalur form
/// Edit Produk), varian yg diberi `followsParentPrice=true` ikut disesuaikan
/// otomatis (harga baru × isi-per-satuan varian). Varian yg saklarnya mati
/// TIDAK ikut berubah sama sekali (perilaku lama, harga sepenuhnya manual).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> seedParent({int basePrice = 1000}) => db.saveProduct(
        product: ProductsCompanion.insert(id: 'p1', name: 'Sedap Goreng'),
        units: [
          ProductUnitsCompanion.insert(
              id: 'u1',
              productId: 'p1',
              isBaseUnit: const Value(true),
              unitTypeId: const Value(1)),
        ],
        tiersByUnitTempId: {
          'u1': [
            PriceTiersCompanion.insert(
                id: 't1', productUnitId: 'u1', minQty: const Value(1), price: basePrice)
          ],
        },
        barcodesByUnitTempId: const {},
        altPricesByUnitTempId: const {},
      );

  test(
      'varian follow=true, isi 10 -> harga induk naik dari 1000 ke 1100 -> '
      'harga varian ikut jadi 11000 (1100 x 10)', () async {
    await seedParent(basePrice: 1000);
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Pedas',
      price: 9500,
      costPrice: 7000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: true,
    );

    await seedParent(basePrice: 1100);

    final saleUnit =
        AppDatabase.variantSaleUnit(await db.getProductUnits(variantId))!;
    final tier = (await db.getPriceTiers(saleUnit.id))
        .firstWhere((t) => t.minQty == 1);
    expect(tier.price, 11000);
  });

  test('varian follow=false -> harga induk berubah, harga varian TIDAK ikut',
      () async {
    await seedParent(basePrice: 1000);
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Original',
      price: 9500,
      costPrice: 7000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: false,
    );

    await seedParent(basePrice: 1100);

    final saleUnit =
        AppDatabase.variantSaleUnit(await db.getProductUnits(variantId))!;
    final tier = (await db.getPriceTiers(saleUnit.id))
        .firstWhere((t) => t.minQty == 1);
    expect(tier.price, 9500, reason: 'harga varian tetap manual, tak ikut');
  });

  test(
      'varian tanpa satuan jual (isi=1, follow=true) -> harga dasar varian '
      'langsung = harga induk baru (rasio 1)', () async {
    await seedParent(basePrice: 1000);
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Original Kecil',
      price: 1000,
      costPrice: 700,
      unitTypeId: 1,
      baseUnitTypeId: 1,
      followsParentPrice: true,
    );

    await seedParent(basePrice: 1250);

    final units = await db.getProductUnits(variantId);
    expect(units, hasLength(1));
    final tier =
        (await db.getPriceTiers(units.single.id)).firstWhere((t) => t.minQty == 1);
    expect(tier.price, 1250);
  });

  test(
      'updateVariant menyalakan follow belakangan -> perubahan harga induk '
      'berikutnya ikut tercermin', () async {
    await seedParent(basePrice: 1000);
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Pedas',
      price: 9500,
      costPrice: 7000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
    );

    await db.updateVariant(
      variantProductId: variantId,
      name: 'Pedas',
      price: 9500,
      followsParentPrice: true,
    );

    await seedParent(basePrice: 1200);

    final saleUnit =
        AppDatabase.variantSaleUnit(await db.getProductUnits(variantId))!;
    final tier = (await db.getPriceTiers(saleUnit.id))
        .firstWhere((t) => t.minQty == 1);
    expect(tier.price, 12000);
  });

  test(
      'variant lain (produk BEDA) tidak ikut kecipratan cascade produk ini',
      () async {
    await seedParent(basePrice: 1000);
    final variantId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Pedas',
      price: 10000,
      costPrice: 7000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: true,
    );

    // Produk lain (p2, tidak terkait) juga punya varian follow=true.
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p2', name: 'Mie Lain'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u2',
            productId: 'p2',
            isBaseUnit: const Value(true),
            unitTypeId: const Value(1)),
      ],
      tiersByUnitTempId: {
        'u2': [
          PriceTiersCompanion.insert(
              id: 'tt2', productUnitId: 'u2', minQty: const Value(1), price: 2000)
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    final otherVariantId = await db.createVariant(
      parentProductId: 'p2',
      name: 'Rasa Lain',
      price: 20000,
      costPrice: 15000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: true,
    );

    // Harga p2 berubah -> variant p1 TIDAK BOLEH ikut tersentuh (scope
    // cascade harus per parentProductId, bukan global per unitTypeId).
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p2', name: 'Mie Lain'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u2',
            productId: 'p2',
            isBaseUnit: const Value(true),
            unitTypeId: const Value(1)),
      ],
      tiersByUnitTempId: {
        'u2': [
          PriceTiersCompanion.insert(
              id: 'tt2', productUnitId: 'u2', minQty: const Value(1), price: 5000)
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    final saleUnit =
        AppDatabase.variantSaleUnit(await db.getProductUnits(variantId))!;
    final tier = (await db.getPriceTiers(saleUnit.id))
        .firstWhere((t) => t.minQty == 1);
    expect(tier.price, 10000, reason: 'varian p1 tak boleh terpengaruh p2');

    final otherSaleUnit = AppDatabase.variantSaleUnit(
        await db.getProductUnits(otherVariantId))!;
    final otherTier = (await db.getPriceTiers(otherSaleUnit.id))
        .firstWhere((t) => t.minQty == 1);
    expect(otherTier.price, 50000,
        reason: 'varian p2 sendiri tetap ikut cascade produknya sendiri');
  });
}
