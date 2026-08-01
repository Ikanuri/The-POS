import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Susulan (permintaan user): "Apakah bisa dibuat sync juga?" — gap yang
/// dicatat sebelumnya di PLAN.md: cascade "ikut harga satuan dasar" cuma
/// tersambung ke `saveProduct` (form Edit Produk biasa), TIDAK ke jalur
/// owner approve usulan harga dari device lain (`applyProductProposals`).
void main() {
  Future<void> seedProduct(AppDatabase db,
      {required int price,
      required String tierId,
      bool locallyModified = false}) async {
    await db.saveProduct(
      product: ProductsCompanion.insert(
          id: 'P', name: 'Sedap Goreng', locallyModified: Value(locallyModified)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'U',
            productId: 'P',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true),
            ratioToBase: const Value(1.0)),
      ],
      tiersByUnitTempId: {
        'U': [
          PriceTiersCompanion.insert(id: tierId, productUnitId: 'U', price: price)
        ],
      },
      barcodesByUnitTempId: const {},
    );
  }

  test(
      'owner approve usulan harga dari asisten -> varian follow=true ikut '
      'ter-cascade otomatis', () async {
    final host = AppDatabase(NativeDatabase.memory());
    final asisten = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await host.close();
      await asisten.close();
    });

    await seedProduct(host, price: 1000, tierId: 't1');
    await seedProduct(asisten, price: 1000, tierId: 't1');

    // Varian di HOST (biasanya sudah ada sebelum ada usulan harga masuk),
    // isi 10, saklar "ikut harga satuan dasar" aktif.
    final variantId = await host.createVariant(
      parentProductId: 'P',
      name: 'Pedas',
      price: 9500,
      costPrice: 7000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: true,
    );

    // Asisten ubah harga satuan dasar -> tandai usulan.
    await seedProduct(asisten, price: 1200, tierId: 't2', locallyModified: true);

    final proposal = await asisten.dumpLocalProposals();
    final applied = await host.applyProductProposals(proposal, {'P'});
    expect(applied, greaterThan(0));

    expect((await host.getPriceTiers('U')).single.price, 1200,
        reason: 'prasyarat: harga induk di host memang ter-approve jadi 1200');

    final saleUnit =
        AppDatabase.variantSaleUnit(await host.getProductUnits(variantId))!;
    final tier =
        (await host.getPriceTiers(saleUnit.id)).firstWhere((t) => t.minQty == 1);
    expect(tier.price, 12000,
        reason: 'varian follow=true harus ikut ter-cascade (1200 x 10) lewat '
            'jalur approve usulan sync, bukan cuma lewat form Edit Produk');
  });

  test(
      'varian follow=false tetap TIDAK ikut walau lewat jalur approve usulan',
      () async {
    final host = AppDatabase(NativeDatabase.memory());
    final asisten = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await host.close();
      await asisten.close();
    });

    await seedProduct(host, price: 1000, tierId: 't1');
    await seedProduct(asisten, price: 1000, tierId: 't1');

    final variantId = await host.createVariant(
      parentProductId: 'P',
      name: 'Original',
      price: 9500,
      costPrice: 7000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: false,
    );

    await seedProduct(asisten, price: 1200, tierId: 't2', locallyModified: true);
    final proposal = await asisten.dumpLocalProposals();
    await host.applyProductProposals(proposal, {'P'});

    final saleUnit =
        AppDatabase.variantSaleUnit(await host.getProductUnits(variantId))!;
    final tier =
        (await host.getPriceTiers(saleUnit.id)).firstWhere((t) => t.minQty == 1);
    expect(tier.price, 9500, reason: 'harga varian tetap manual, tak ikut');
  });

  test(
      'usulan produk LAIN yg diapprove bersamaan tidak ikut mencascade '
      'varian produk ini (scope ketat per parentProductId)', () async {
    final host = AppDatabase(NativeDatabase.memory());
    final asisten = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await host.close();
      await asisten.close();
    });

    await seedProduct(host, price: 1000, tierId: 't1');
    await seedProduct(asisten, price: 1000, tierId: 't1');

    final variantId = await host.createVariant(
      parentProductId: 'P',
      name: 'Pedas',
      price: 9500,
      costPrice: 7000,
      unitTypeId: 2,
      baseUnitTypeId: 1,
      contentPerUnit: 10,
      followsParentPrice: true,
    );

    // Produk LAIN (Q) juga diusulkan & diapprove dalam batch yg sama —
    // tidak boleh menyentuh varian milik produk P sama sekali.
    await asisten.saveProduct(
      product: ProductsCompanion.insert(
          id: 'Q', name: 'Teh Botol', locallyModified: const Value(true)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'UQ',
            productId: 'Q',
            unitTypeId: const Value(1),
            isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'UQ': [PriceTiersCompanion.insert(id: 'tq', productUnitId: 'UQ', price: 3000)],
      },
      barcodesByUnitTempId: const {},
    );

    final proposal = await asisten.dumpLocalProposals();
    await host.applyProductProposals(proposal, {'Q'});

    final saleUnit =
        AppDatabase.variantSaleUnit(await host.getProductUnits(variantId))!;
    final tier =
        (await host.getPriceTiers(saleUnit.id)).firstWhere((t) => t.minQty == 1);
    expect(tier.price, 9500,
        reason: 'varian produk P tidak boleh terpengaruh approve produk Q');
  });
}
