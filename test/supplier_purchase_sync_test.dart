import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Modul Supplier & Pembelian (`suppliers`/`purchases`/`purchase_items`)
/// sebelumnya CUMA ikut backup penuh/"Alihkan Owner" (`_allTables`), TIDAK
/// PERNAH ikut sync LAN harian (`dumpSince`) — device kasir lain di toko
/// yang sama tidak pernah melihat data supplier/pembelian yang diinput
/// owner di device lain. Fix: ketiganya masuk `masterData`, dan
/// `suppliers`/`purchases` dapat kolom `updated_at` baru (skema v41) supaya
/// perubahan SETELAH baris dibuat — `outstandingDebt`/`isActive`,
/// `status`/`paid`/`syncedAt` — tetap ikut ter-sync (delta by `updated_at`,
/// bukan cuma `created_at`).
void main() {
  test(
      'suppliers/purchases/purchase_items ikut dumpSince & sampai ke klien '
      'via mergeRows (sebelumnya sama sekali tidak ada di masterData)',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await hostDb.into(hostDb.suppliers).insert(SuppliersCompanion.insert(
          id: 'sup1',
          name: 'Toko Grosir Jaya',
          updatedAt: Value(DateTime.now()),
        ));
    await hostDb.into(hostDb.purchases).insert(PurchasesCompanion.insert(
          id: 'pur1',
          localId: 'loc1',
          status: 'draft',
          supplierId: const Value('sup1'),
          updatedAt: Value(DateTime.now()),
        ));
    await hostDb.into(hostDb.purchaseItems).insert(
        PurchaseItemsCompanion.insert(
          id: 'pi1',
          purchaseId: 'pur1',
          productUnitId: 'unit1',
          qty: 2.0,
          pricePerUnit: 25000,
          subtotal: 50000,
          createdAt: Value(DateTime.now()),
        ));

    final dump = await hostDb.dumpSince(DateTime(2000));
    expect(dump['suppliers']?.any((r) => r['id'] == 'sup1'), isTrue,
        reason: 'suppliers harus ikut dumpSince — sebelumnya tabel ini '
            'tidak ada sama sekali di masterData');
    expect(dump['purchases']?.any((r) => r['id'] == 'pur1'), isTrue);
    expect(dump['purchase_items']?.any((r) => r['id'] == 'pi1'), isTrue);

    await clientDb.mergeRows('suppliers', dump['suppliers']!, false);
    await clientDb.mergeRows('purchases', dump['purchases']!, false);
    await clientDb.mergeRows('purchase_items', dump['purchase_items']!, false);

    final clientSupplier = await (clientDb.select(clientDb.suppliers)
          ..where((t) => t.id.equals('sup1')))
        .getSingle();
    expect(clientSupplier.name, 'Toko Grosir Jaya');

    final clientPurchase = await (clientDb.select(clientDb.purchases)
          ..where((t) => t.id.equals('pur1')))
        .getSingle();
    expect(clientPurchase.status, 'draft');

    final clientItem = await (clientDb.select(clientDb.purchaseItems)
          ..where((t) => t.id.equals('pi1')))
        .getSingle();
    expect(clientItem.subtotal, 50000);
  });

  test(
      'perubahan status/paid pembelian SETELAH sync pertama ikut ter-sync '
      'lagi di sync kedua (delta by updated_at yang di-restamp ulang)',
      () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    final createdLongAgo = DateTime.now().subtract(const Duration(days: 2));
    await hostDb.into(hostDb.purchases).insert(PurchasesCompanion.insert(
          id: 'pur1',
          localId: 'loc1',
          status: 'draft',
          total: const Value(50000),
          createdAt: Value(createdLongAgo),
          updatedAt: Value(createdLongAgo),
        ));

    // Sync PERTAMA: klien terima draft, watermark-nya maju ke SEKARANG.
    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows('purchases', firstDump['purchases']!, false);
    var clientPurchase = await (clientDb.select(clientDb.purchases)
          ..where((t) => t.id.equals('pur1')))
        .getSingle();
    expect(clientPurchase.status, 'draft');

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Owner terima barang: status berubah + `paid` bertambah (cicilan),
    // `updated_at` DIRESTAMP eksplisit ke SEKARANG — pola yang WAJIB
    // dipakai fungsi mutasi manapun yang menyentuh baris ini nanti.
    await (hostDb.update(hostDb.purchases)..where((t) => t.id.equals('pur1')))
        .write(PurchasesCompanion(
      status: const Value('received'),
      paid: const Value(30000),
      updatedAt: Value(DateTime.now()),
    ));

    // Sync KEDUA: klien minta data sejak watermark-nya (setelah sync
    // pertama, sebelum update barusan).
    final secondDump = await hostDb.dumpSince(clientWatermark);
    expect(secondDump['purchases']!.any((r) => r['id'] == 'pur1'), isTrue,
        reason: 'tanpa updated_at direstamp ulang, baris ini tidak akan '
            'pernah ikut dump kedua — bug persis yg sudah terjadi 2x di '
            'fungsi lain (lihat gotcha CLAUDE.md)');
    await clientDb.mergeRows('purchases', secondDump['purchases']!, false);

    clientPurchase = await (clientDb.select(clientDb.purchases)
          ..where((t) => t.id.equals('pur1')))
        .getSingle();
    expect(clientPurchase.status, 'received',
        reason: 'status pembelian yang berubah di host harus sampai ke '
            'klien setelah sync kedua');
    expect(clientPurchase.paid, 30000);
  });
}
