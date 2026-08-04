import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Susulan (pertanyaan user): "untuk produk yang dinonaktifkan owner,
/// apakah juga bisa ikut nonaktif di client ketika sync? ... apakah tidak
/// ada cara utk menanggulangi hilangnya data produk yang benar-benar baru
/// ditambahkan client sekaligus bisa menghilangkan produk yang sudah
/// dinonaktifkan owner ketika sync?"
///
/// Jawabannya: KEDUANYA sudah terpenuhi SEKALIGUS oleh desain sync yang
/// SUDAH ADA — bukan trade-off yang perlu dipilih salah satu:
/// - Deaktivasi produk LAMA di host SUDAH otomatis ikut ke klien (dibuktikan
///   `product_deactivate_sync_test.dart` — TIDAK diulang di sini).
/// - Produk BARU yang baru dibuat client (`locallyModified=true`, belum
///   pernah sampai ke host) TIDAK PERNAH ikut terhapus/tertimpa oleh sync
///   host→klien manapun — karena `mergeRows('products', ...)` cuma
///   memproses baris yang BENAR-BENAR ADA di payload host (`dumpSince`
///   hanya mengirim apa yang host TAHU/PUNYA). Host tidak pernah mengirim
///   baris utk produk yang belum pernah ia terima, jadi `mergeRows` tidak
///   pernah punya kesempatan menyentuhnya sama sekali — bukan soal
///   "dilindungi flag khusus", tapi soal payload-nya memang tidak pernah
///   menyebut produk itu.
///
/// Test ini membuktikan KEDUA klaim itu SEKALIGUS dalam satu skenario
/// realistis: kasir tambah produk baru (belum sempat sync ke owner) DI
/// SAAT YANG SAMA owner menonaktifkan produk LAIN yang tidak berhubungan
/// — sync berikutnya harus membawa KEDUA efek itu dengan benar, tanpa
/// saling mengganggu.
void main() {
  test(
      'produk baru buatan client (locallyModified, belum di-approve) tetap '
      'utuh SEKALIGUS produk lain yang dinonaktifkan owner ikut nonaktif — '
      'dalam satu sync yang sama', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    // Produk LAMA yang sudah dikenal kedua belah pihak (hasil sync
    // sebelumnya) — akan dinonaktifkan owner di tengah skenario ini.
    await hostDb.saveProduct(
      product: ProductsCompanion.insert(id: 'p-lama', name: 'Indomie Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u-lama', productId: 'p-lama', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u-lama': [
          PriceTiersCompanion.insert(
              id: 't-lama', productUnitId: 'u-lama', price: 3000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );
    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows('products', firstDump['products']!, false);
    await clientDb.mergeRows(
        'product_units', firstDump['product_units']!, false);
    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Kasir (device non-owner) tambah produk BARU secara lokal — belum
    // pernah sync ke owner sama sekali, ditandai locallyModified spt pola
    // Item 40 (usulan produk).
    await clientDb.saveProduct(
      product: ProductsCompanion.insert(
          id: 'p-baru-client',
          name: 'Produk Baru dari Kasir',
          locallyModified: const Value(true)),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u-baru-client',
            productId: 'p-baru-client',
            isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u-baru-client': [
          PriceTiersCompanion.insert(
              id: 't-baru-client', productUnitId: 'u-baru-client', price: 5000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    // Owner (TIDAK tahu-menahu soal produk baru kasir) nonaktifkan produk
    // LAIN yang tidak berhubungan.
    await hostDb.deactivateProduct('p-lama');

    // Sync berikutnya: klien tarik data host sejak watermark-nya.
    final secondDump = await hostDb.dumpSince(clientWatermark);
    // Prasyarat: host memang TIDAK PERNAH menyebut produk baru client sama
    // sekali (baik karena belum di-approve MAUPUN karena arah proposal
    // client->host itu jalur payload TERPISAH, bukan bagian dari dumpSince).
    expect(secondDump['products']!.any((r) => r['id'] == 'p-baru-client'),
        isFalse,
        reason: 'prasyarat: host memang tidak pernah tahu produk ini');
    await clientDb.mergeRows('products', secondDump['products']!, false);

    // KLAIM 1 — produk LAMA yang dinonaktifkan owner ikut nonaktif di client.
    final lama = await (clientDb.select(clientDb.products)
          ..where((t) => t.id.equals('p-lama')))
        .getSingle();
    expect(lama.isActive, isFalse,
        reason: 'deaktivasi owner harus ikut sampai ke client');

    // KLAIM 2 — produk BARU buatan client TETAP UTUH, tidak terhapus/
    // tertimpa/ke-set locallyModified=false secara diam-diam.
    final baru = await (clientDb.select(clientDb.products)
          ..where((t) => t.id.equals('p-baru-client')))
        .getSingle();
    expect(baru.isActive, isTrue,
        reason: 'produk baru client TIDAK BOLEH ikut terhapus/nonaktif '
            'hanya karena ada sync tak terkait berjalan');
    expect(baru.name, 'Produk Baru dari Kasir');
    expect(baru.locallyModified, isTrue,
        reason: 'status "menunggu approve" harus tetap menggantung sampai '
            'owner benar-benar meninjau usulan ini lewat jalur proposal, '
            'BUKAN ikut ter-reset oleh sync data lain yang tidak terkait');
  });
}
