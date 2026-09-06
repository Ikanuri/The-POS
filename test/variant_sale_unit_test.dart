import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Susulan (permintaan user): "varian terjangkar ke satuan dasar, namun di
/// varian, berikan pilih satuan (misal ret, dos, dll) serta juga terkonversi
/// ke satuan dasar (jadi juga ada isi per satuan)".
///
/// Desainnya: varian TETAP punya satuan dasar (jangkar, pemegang stok —
/// seluruh `stock_ledger` app ini memang ditulis dalam satuan dasar), plus
/// SATU satuan non-dasar sebagai satuan JUAL bila isi per satuan != 1.
/// Harga/barcode/Harga Lain menempel di satuan jual; stok dibaca lewat
/// pembagian rasio oleh `currentStock` yang sudah ada.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(201), name: 'Pcs'));
    await db.into(db.unitTypes).insert(
        UnitTypesCompanion.insert(id: const Value(202), name: 'Renteng'));
    await db.into(db.products)
        .insert(ProductsCompanion.insert(id: 'p1', name: 'Pop Ice'));
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
        id: 'u1',
        productId: 'p1',
        isBaseUnit: const Value(true),
        unitTypeId: const Value(201)));
  });
  tearDown(() async => db.close());

  test('isi per satuan 1 (default) -> tetap SATU satuan, persis varian lama',
      () async {
    final vId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 1000,
      costPrice: 700,
      unitTypeId: 201,
      baseUnitTypeId: 201,
    );
    final units = await db.getProductUnits(vId);
    expect(units, hasLength(1));
    expect(units.single.isBaseUnit, isTrue);
    expect(units.single.ratioToBase, 1.0);
    expect(AppDatabase.variantSaleUnit(units)!.id, units.single.id,
        reason: 'varian satu-satuan: satuan jual = satuan dasarnya sendiri');
  });

  test(
      'isi per satuan 10 -> 2 satuan (dasar jangkar + satuan jual), harga & '
      'barcode & Harga Lain menempel di satuan JUAL', () async {
    final vId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 9000,
      costPrice: 7000,
      unitTypeId: 202, // Renteng
      baseUnitTypeId: 201, // Pcs (jangkar, ikut satuan dasar induk)
      contentPerUnit: 10,
      barcode: '2911111111116',
      altPrices: const [(label: 'Toko A', price: 8500, priceCategoryId: null, marginAnchor: null, marginType: null, marginValue: null)],
      isNonStock: false,
    );

    final units = await db.getProductUnits(vId);
    expect(units, hasLength(2));
    final base = units.firstWhere((u) => u.isBaseUnit);
    final sale = AppDatabase.variantSaleUnit(units)!;
    expect(sale.id, isNot(base.id),
        reason: 'satuan jual harus satuan NON-dasar, bukan jangkarnya');
    expect(base.unitTypeId, 201, reason: 'jangkar ikut satuan dasar induk');
    expect(base.ratioToBase, 1.0);
    expect(sale.unitTypeId, 202);
    expect(sale.ratioToBase, 10.0);

    final tiers = await db.getPriceTiers(sale.id);
    expect(tiers.single.price, 9000);
    expect(await db.getPriceTiers(base.id), isEmpty,
        reason: 'harga varian dijual per satuan jual, bukan per satuan dasar');
    expect((await db.getProductBarcodes(sale.id)).single.barcode,
        '2911111111116');
    expect((await db.getAltPrices(sale.id)).single.label, 'Toko A');
  });

  test('stok varian dibaca terkonversi: 30 satuan dasar = 3 satuan jual isi 10',
      () async {
    final vId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 9000,
      costPrice: 7000,
      unitTypeId: 202,
      baseUnitTypeId: 201,
      contentPerUnit: 10,
      isNonStock: false,
    );
    final units = await db.getProductUnits(vId);
    final sale = AppDatabase.variantSaleUnit(units)!;

    // Diisi 3 satuan jual (renteng) -> ledger menyimpan 30 satuan dasar.
    await db.adjustStock(productUnitId: sale.id, newQty: 3);
    expect(await db.currentStock(sale.id), 3.0);
    expect(await db.currentStock(units.firstWhere((u) => u.isBaseUnit).id), 30.0,
        reason: 'ledger tetap disimpan dalam satuan dasar (30 pcs)');
  });

  test(
      'updateVariant menambah satuan jual belakangan: harga/barcode/Harga Lain '
      'PINDAH ke satuan jual, stok yang sudah tercatat TIDAK berubah',
      () async {
    final vId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 1000,
      costPrice: 700,
      unitTypeId: 201,
      baseUnitTypeId: 201,
      barcode: '2911111111116',
      altPrices: const [(label: 'Toko A', price: 900, priceCategoryId: null, marginAnchor: null, marginType: null, marginValue: null)],
      isNonStock: false,
    );
    final baseId = (await db.getProductUnits(vId)).single.id;
    await db.adjustStock(productUnitId: baseId, newQty: 30);

    await db.updateVariant(
      variantProductId: vId,
      name: 'Coklat',
      price: 9000,
      barcode: '2911111111116',
      unitTypeId: 202,
      contentPerUnit: 10,
    );

    final units = await db.getProductUnits(vId);
    expect(units, hasLength(2));
    final sale = AppDatabase.variantSaleUnit(units)!;
    expect(sale.id, isNot(baseId));
    expect(sale.ratioToBase, 10.0);
    expect(sale.unitTypeId, 202);

    expect((await db.getPriceTiers(sale.id)).single.price, 9000);
    expect(await db.getPriceTiers(baseId), isEmpty);
    expect((await db.getProductBarcodes(sale.id)).single.barcode,
        '2911111111116');
    expect((await db.getAltPrices(sale.id)).single.label, 'Toko A');

    expect(await db.currentStock(baseId), 30.0,
        reason: 'stok yang sudah tercatat tidak boleh berubah sama sekali');
    expect(await db.currentStock(sale.id), 3.0,
        reason: '30 satuan dasar = 3 satuan jual berisi 10');
  });

  test(
      'isi dikembalikan ke 1: satuan jual TIDAK dihapus (nota lama menunjuk '
      'ke id-nya), cuma rasionya jadi 1', () async {
    final vId = await db.createVariant(
      parentProductId: 'p1',
      name: 'Coklat',
      price: 9000,
      costPrice: 7000,
      unitTypeId: 202,
      baseUnitTypeId: 201,
      contentPerUnit: 10,
      isNonStock: false,
    );
    final saleId = AppDatabase.variantSaleUnit(await db.getProductUnits(vId))!.id;

    await db.updateVariant(
      variantProductId: vId,
      name: 'Coklat',
      price: 1000,
      unitTypeId: 201,
      contentPerUnit: 1,
    );

    final units = await db.getProductUnits(vId);
    expect(units, hasLength(2), reason: 'satuan jual tidak dihapus');
    final sale = AppDatabase.variantSaleUnit(units)!;
    expect(sale.id, saleId, reason: 'satuan jual yang sama, bukan dibuat ulang');
    expect(sale.ratioToBase, 1.0);
    expect(sale.unitTypeId, 201);
  });
}
