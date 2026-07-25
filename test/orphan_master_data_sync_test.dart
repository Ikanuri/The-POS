import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Bug nyata dilaporkan user (25 Juli): owner edit barcode produk di host ->
/// setelah sync ke klien, barcode LAMA masih ada (bisa di-scan) BERDAMPINGAN
/// dgn yg baru, padahal sudah "diganti". Akar: `saveProduct` HAPUS baris
/// barcode lama + INSERT baris baru (id UUID baru) saat barcode diedit
/// (bukan update in-place) — dan `product_barcodes` (sama seperti
/// `price_tiers`/`alt_prices`) SELALU disinkron full-dump tanpa `updated_at`
/// (lihat `dumpSince`), jadi `INSERT OR REPLACE` di `mergeRows` tidak pernah
/// menghapus baris lokal yang sudah tak ada di payload — persis pola bug
/// yang sudah pernah terjadi & diperbaiki di `product_group_tags` (lihat
/// `product_group_tags_sync_test.dart`). Fix: sweep orphan-cleanup yang sama
/// diterapkan juga ke `product_barcodes`, `price_tiers`, `alt_prices`.
void main() {
  late AppDatabase host;
  late AppDatabase client;

  setUp(() async {
    host = AppDatabase(NativeDatabase.memory());
    client = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await host.close();
    await client.close();
  });

  Future<void> syncHostToClient() async {
    final dump = await host.dumpSince(DateTime.fromMillisecondsSinceEpoch(0));
    for (final entry in dump.entries) {
      final isAppendOnly = const {
        'transactions',
        'transaction_items',
        'transaction_payments',
        'stock_ledger',
        'loyalty_point_ledger',
        'expenses',
      }.contains(entry.key);
      await client.mergeRows(entry.key, entry.value, isAppendOnly);
    }
  }

  Future<void> seedProduct(AppDatabase db, String barcode,
      {String barcodeId = 'bc1'}) async {
    await db.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Kopi'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000),
        ],
      },
      barcodesByUnitTempId: {
        'u1': [
          ProductBarcodesCompanion.insert(
              id: barcodeId,
              productUnitId: 'u1',
              barcode: barcode,
              isPrimary: const Value(true)),
        ],
      },
      altPricesByUnitTempId: {
        'u1': [
          AltPricesCompanion.insert(
              id: 'ap1', productUnitId: 'u1', label: 'Grosir', price: 4000),
        ],
      },
    );
  }

  test(
      'barcode lama yang diganti di host TIDAK BOLEH menetap di klien '
      'setelah sync', () async {
    await seedProduct(host, '1110000000000');
    await syncHostToClient();
    expect((await client.lookupBarcode('1110000000000'))?.productUnitId, 'u1');

    // Owner edit barcode -> baris lama dihapus, baris baru (id beda) dibuat
    // (persis `saveProduct` sungguhan: id UUID baru tiap kali barcode diedit).
    await seedProduct(host, '2220000000000', barcodeId: 'bc2');
    await syncHostToClient();

    expect(await client.lookupBarcode('1110000000000'), isNull,
        reason: 'barcode lama sudah dihapus di host, wajib ikut hilang di '
            'klien juga setelah sync, bukan tetap bisa di-scan');
    expect((await client.lookupBarcode('2220000000000'))?.productUnitId, 'u1');
  });

  test(
      'tier grosir yang DIHAPUS di host (tanpa pengganti) ikut terhapus di '
      'klien, bukan menetap selamanya', () async {
    await seedProduct(host, '1110000000000');
    await syncHostToClient();
    Future<List<PriceTier>> tiersOf(AppDatabase db) => (db.select(db.priceTiers)
          ..where((t) => t.productUnitId.equals('u1')))
        .get();
    var tiers = await tiersOf(client);
    expect(tiers, hasLength(1));

    // Owner hapus tier grosir lewat form (form re-save tanpa tier baru).
    await host.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Kopi'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: const {},
      barcodesByUnitTempId: {
        'u1': [
          ProductBarcodesCompanion.insert(
              id: 'bc1', productUnitId: 'u1', barcode: '1110000000000'),
        ],
      },
      altPricesByUnitTempId: {
        'u1': [
          AltPricesCompanion.insert(
              id: 'ap1', productUnitId: 'u1', label: 'Grosir', price: 4000),
        ],
      },
    );
    await syncHostToClient();

    tiers = await tiersOf(client);
    expect(tiers, isEmpty,
        reason: 'tier yg sudah tak ada di dump host wajib ikut terhapus di '
            'klien, bukan diam menumpuk dari sync sebelumnya');
  });

  test(
      'baris milik unit yang locally_modified (usulan blm di-approve owner) '
      'TIDAK ikut kehapus oleh orphan-cleanup', () async {
    await seedProduct(host, '1110000000000');
    await seedProduct(client, '1110000000000');
    await client.markProductLocallyModified('p1');
    // `updated_at` presisi detik (unix seconds) — di test cepat, panggilan
    // host & klien bisa jatuh di detik yang SAMA (timestamp seri), dan
    // last-write-wins pakai `<` ketat jadi TIDAK skip saat seri (host
    // menang telak) — bukan bug fix ini, tapi resolusi timestamp. Paksa
    // klien lebih baru scr eksplisit spy independen dari kecepatan mesin.
    await (client.update(client.products)..where((t) => t.id.equals('p1')))
        .write(ProductsCompanion(
            updatedAt: Value(DateTime.now().add(const Duration(seconds: 5)))));

    // Host hapus barcode itu (mis. produk diedit tanpa barcode lagi).
    await host.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Kopi'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 5000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    await syncHostToClient();

    expect((await client.lookupBarcode('1110000000000'))?.productUnitId, 'u1',
        reason: 'unit ini locally_modified (usulan blm di-review owner) — '
            'orphan-cleanup wajib skip baris ini spt guard proteksi lain');
  });
}
