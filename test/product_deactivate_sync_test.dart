import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// User bertanya: "kalau owner nonaktifkan produk, apakah ikut terhapus
/// (tersembunyi) di klien saat sync?" — jawabannya SEHARUSNYA ya (app ini
/// tidak punya hard-delete produk sama sekali, cuma soft-delete via
/// `isActive=false`, dan protokol sync `products` sudah dirancang delta by
/// `updated_at` + last-write-wins persis utk kasus ini), TAPI ketemu bug
/// nyata: `deactivateProduct` (dipanggil tombol "Nonaktifkan" di form
/// produk) TIDAK PERNAH mencap ulang `updated_at` saat men-set
/// `isActive=false` — beda dari `deleteVariant` yang sudah benar. Akibatnya
/// `dumpSince` (host→klien, filter `WHERE updated_at >= since`) tidak akan
/// pernah lagi menyertakan produk itu begitu watermark klien sudah lewat
/// dari kapan produk itu TERAKHIR DIEDIT (bukan kapan dinonaktifkan) —
/// nonaktifnya produk di owner tidak pernah sampai ke klien, produk itu
/// jadi "hantu" yang tetap muncul selamanya di HP kasir/asisten. Akar
/// masalah SAMA PERSIS dgn bug `applyProductProposals` (lihat
/// `proposal_apply_updated_at_test.dart`).
void main() {
  test(
      'deactivateProduct mencap updated_at ke SAAT INI, supaya tetap ikut '
      'dumpSince berikutnya (bukan cuma set isActive=false)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Produk terakhir diedit 2 hari lalu — klien sudah sinkron & watermark
    // download-nya sudah lewat dari waktu edit lama itu.
    final oldUpdatedAt =
        DateTime.now().subtract(const Duration(days: 2));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p1',
          name: 'Produk Lama',
          updatedAt: Value(oldUpdatedAt),
        ));

    final beforeDeactivate =
        DateTime.now().subtract(const Duration(seconds: 1));
    await db.deactivateProduct('p1');

    final row =
        await (db.select(db.products)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(row.isActive, isFalse);
    expect(
        row.updatedAt.isAfter(beforeDeactivate) ||
            row.updatedAt.isAtSameMomentAs(beforeDeactivate),
        isTrue,
        reason: 'updated_at HARUS dicap ke saat nonaktifkan (sekarang), '
            'bukan dibiarkan basi dari terakhir diedit — kalau tidak, baris '
            'ini jatuh di bawah watermark download klien pada sync '
            'berikutnya dan TIDAK PERNAH terkirim ke klien');

    // Watermark klien: SETELAH edit lama, TAPI SEBELUM nonaktifkan barusan.
    final sinceAfterOldEdit = DateTime.now().subtract(const Duration(hours: 1));
    final dump = await db.dumpSince(sinceAfterOldEdit);
    final products = dump['products'] ?? const [];
    expect(products.any((r) => r['id'] == 'p1'), isTrue,
        reason: 'produk yang baru dinonaktifkan harus ikut dumpSince '
            'berikutnya supaya status nonaktifnya sampai ke klien');
  });

  test(
      'end-to-end host→klien: produk dinonaktifkan owner → klien sync → '
      'produk hilang dari daftar aktif klien', () async {
    final hostDb = AppDatabase(NativeDatabase.memory());
    final clientDb = AppDatabase(NativeDatabase.memory());
    addTearDown(hostDb.close);
    addTearDown(clientDb.close);

    await hostDb.saveProduct(
      product: ProductsCompanion.insert(id: 'p1', name: 'Indomie Goreng'),
      units: [
        ProductUnitsCompanion.insert(
            id: 'u1', productId: 'p1', isBaseUnit: const Value(true)),
      ],
      tiersByUnitTempId: {
        'u1': [
          PriceTiersCompanion.insert(id: 't1', productUnitId: 'u1', price: 3000),
        ],
      },
      barcodesByUnitTempId: const {},
      altPricesByUnitTempId: const {},
    );

    // Sync PERTAMA: klien terima produk, watermark klien maju ke SEKARANG.
    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows('products', firstDump['products']!, false);
    var clientProducts = await clientDb.searchProducts('');
    expect(clientProducts.map((p) => p.id), contains('p1'));

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Owner nonaktifkan produk di host.
    await hostDb.deactivateProduct('p1');

    // Sync KEDUA: klien minta data sejak watermark-nya (setelah sync
    // pertama, sebelum nonaktifkan barusan).
    final secondDump = await hostDb.dumpSince(clientWatermark);
    expect(secondDump['products']!.any((r) => r['id'] == 'p1'), isTrue,
        reason: 'tanpa fix, baris ini tidak akan pernah ikut dump kedua');
    await clientDb.mergeRows('products', secondDump['products']!, false);

    clientProducts = await clientDb.searchProducts('');
    expect(clientProducts.map((p) => p.id), isNot(contains('p1')),
        reason: 'produk yang dinonaktifkan owner harus ikut hilang dari '
            'daftar produk aktif klien setelah sync');
  });
}
