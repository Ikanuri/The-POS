import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Item 40 — usulan harga/produk dari device non-owner via sync LAN.
/// `markProductLocallyModified` menandai produk yg diedit lokal,
/// `dumpLocalProposals` mengumpulkan paket utuh (produk+satuan+harga+
/// alt harga+barcode), `applyProductProposals` menulis subset yg disetujui
/// owner ke DB host & memaksa `locallyModified=false` (menutup usulan).
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<void> addProduct(String id, String name,
      {int price = 1000, String? barcode}) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
        ));
    final unitId = '$id-u';
    await db.into(db.productUnits).insert(ProductUnitsCompanion.insert(
          id: unitId,
          productId: id,
          isBaseUnit: const Value(true),
        ));
    await db.into(db.priceTiers).insert(PriceTiersCompanion.insert(
          id: '$id-t',
          productUnitId: unitId,
          price: price,
        ));
    if (barcode != null) {
      await db.into(db.productBarcodes).insert(
          ProductBarcodesCompanion.insert(
              id: '$id-b', productUnitId: unitId, barcode: barcode));
    }
  }

  test('migrasi v15->v16: kolom locally_modified ada, default false',
      () async {
    final p = await (db.select(db.products)).get();
    expect(p, isEmpty); // sanity: DB baru kosong, tidak crash
    await addProduct('p1', 'Gula');
    final row =
        await (db.select(db.products)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(row.locallyModified, isFalse);
  });

  test('markProductLocallyModified menandai produk true', () async {
    await addProduct('p1', 'Gula');
    await db.markProductLocallyModified('p1');
    final row =
        await (db.select(db.products)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(row.locallyModified, isTrue);
  });

  test('dumpLocalProposals kosong kalau tidak ada produk ditandai',
      () async {
    await addProduct('p1', 'Gula');
    final dump = await db.dumpLocalProposals();
    expect(dump, isEmpty);
  });

  test(
      'dumpLocalProposals kumpulkan paket UTUH (produk+satuan+harga+barcode) '
      'utk produk yang ditandai, TIDAK ikutkan produk lain', () async {
    await addProduct('p1', 'Gula', price: 15000, barcode: '111');
    await addProduct('p2', 'Kopi', price: 5000);
    await db.markProductLocallyModified('p1');

    final dump = await db.dumpLocalProposals();
    expect(dump['products']!.map((r) => r['id']), ['p1']);
    expect(dump['product_units']!.map((r) => r['product_id']), ['p1']);
    expect(dump['price_tiers']!.single['price'], 15000);
    expect(dump['product_barcodes']!.single['barcode'], '111');
  });

  test(
      'applyProductProposals: produk BARU (belum ada di host) ditulis '
      'lengkap dgn id yg sama (identitas lintas-device terjaga)', () async {
    // Simulasi: asisten sudah punya produk baru "p-new" lokal (DB asisten),
    // owner (db ini) BELUM punya produk itu sama sekali.
    final proposalDb = AppDatabase(NativeDatabase.memory());
    await proposalDb.into(proposalDb.products).insert(
        ProductsCompanion.insert(id: 'p-new', name: 'Produk Baru Asisten'));
    await proposalDb.into(proposalDb.productUnits).insert(
        ProductUnitsCompanion.insert(
            id: 'p-new-u', productId: 'p-new', isBaseUnit: const Value(true)));
    await proposalDb.into(proposalDb.priceTiers).insert(
        PriceTiersCompanion.insert(
            id: 'p-new-t', productUnitId: 'p-new-u', price: 7000));
    await proposalDb.markProductLocallyModified('p-new');
    final proposals = await proposalDb.dumpLocalProposals();
    await proposalDb.close();

    final applied =
        await db.applyProductProposals(proposals, {'p-new'});
    expect(applied, greaterThan(0));

    final hostProduct =
        await (db.select(db.products)..where((t) => t.id.equals('p-new')))
            .getSingle();
    expect(hostProduct.name, 'Produk Baru Asisten');
    expect(hostProduct.locallyModified, isFalse,
        reason: 'host bukan sumber usulan, harus false');
    final hostTier = await (db.select(db.priceTiers)
          ..where((t) => t.productUnitId.equals('p-new-u')))
        .getSingle();
    expect(hostTier.price, 7000);
  });

  test('applyProductProposals: produk yang TIDAK disetujui tidak ditulis',
      () async {
    final proposalDb = AppDatabase(NativeDatabase.memory());
    await proposalDb.into(proposalDb.products).insert(
        ProductsCompanion.insert(id: 'p-reject', name: 'Ditolak'));
    await proposalDb.into(proposalDb.productUnits).insert(
        ProductUnitsCompanion.insert(
            id: 'p-reject-u',
            productId: 'p-reject',
            isBaseUnit: const Value(true)));
    await proposalDb.markProductLocallyModified('p-reject');
    final proposals = await proposalDb.dumpLocalProposals();
    await proposalDb.close();

    final applied = await db.applyProductProposals(proposals, {});
    expect(applied, 0);
    final hostProducts = await (db.select(db.products)
          ..where((t) => t.id.equals('p-reject')))
        .get();
    expect(hostProducts, isEmpty);
  });
}
