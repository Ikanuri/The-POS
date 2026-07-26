import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// User bertanya sambil menyetujui fix: "mungkin tambahkan juga itu
/// updated_at [ke setMarkedOutOfStock]". Akar masalah SAMA PERSIS dgn
/// `deactivateProduct`/`applyProductProposals` (lihat
/// `product_deactivate_sync_test.dart`): tanpa cap ulang `updated_at`,
/// `dumpSince` (host→klien, filter `WHERE updated_at >= since`) tidak akan
/// pernah lagi menyertakan produk yang ditandai habis owner begitu watermark
/// klien sudah lewat dari kapan produk itu TERAKHIR DIEDIT.
///
/// CATATAN PENTING (dari pertanyaan susulan user, "bagaimana jika dari
/// client ke host?"): fix ini HANYA menutup arah HOST → KLIEN. Arah
/// sebaliknya — kasir/asisten menandai stok habis di device-nya sendiri —
/// TIDAK diuji di sini krn TIDAK PERNAH sampai ke host sama sekali, bahkan
/// dgn fix ini: `syncToHost` mengirim `dumpSince(..., includeMasterData:
/// false)` (`products` adalah master data, sengaja tidak diunggah klien),
/// dan `setMarkedOutOfStock` tidak memanggil `markProductLocallyModified`
/// jadi TIDAK IKUT `dumpLocalProposals` (jalur "usulan" Item 40) juga. Ini
/// celah arsitektur terpisah, bukan bug watermark — perlu keputusan desain
/// tersendiri (lihat diskusi di chat), BUKAN cuma tambahan baris kode.
void main() {
  test(
      'setMarkedOutOfStock mencap updated_at ke SAAT INI, supaya tetap ikut '
      'dumpSince berikutnya (bukan cuma set markedOutOfStock)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final oldUpdatedAt = DateTime.now().subtract(const Duration(days: 2));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'p1',
          name: 'Produk Lama',
          updatedAt: Value(oldUpdatedAt),
        ));

    final beforeToggle = DateTime.now().subtract(const Duration(seconds: 1));
    await db.setMarkedOutOfStock('p1', true);

    final row =
        await (db.select(db.products)..where((t) => t.id.equals('p1')))
            .getSingle();
    expect(row.markedOutOfStock, isTrue);
    expect(
        row.updatedAt.isAfter(beforeToggle) ||
            row.updatedAt.isAtSameMomentAs(beforeToggle),
        isTrue,
        reason: 'updated_at HARUS dicap ke saat ditandai habis (sekarang), '
            'bukan dibiarkan basi dari terakhir diedit — kalau tidak, baris '
            'ini jatuh di bawah watermark download klien pada sync '
            'berikutnya dan TIDAK PERNAH terkirim ke klien');

    final sinceAfterOldEdit =
        DateTime.now().subtract(const Duration(hours: 1));
    final dump = await db.dumpSince(sinceAfterOldEdit);
    final products = dump['products'] ?? const [];
    expect(products.any((r) => r['id'] == 'p1'), isTrue,
        reason: 'produk yang baru ditandai habis harus ikut dumpSince '
            'berikutnya supaya statusnya sampai ke klien');
  });

  test(
      'end-to-end host→klien: owner tandai stok habis → klien sync → '
      'flag ikut muncul di klien', () async {
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

    final firstDump = await hostDb.dumpSince(DateTime(2000));
    await clientDb.mergeRows('products', firstDump['products']!, false);
    var clientProduct = (await clientDb.searchProducts(''))
        .firstWhere((p) => p.id == 'p1');
    expect(clientProduct.markedOutOfStock, isFalse);

    final clientWatermark = DateTime.now();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    await hostDb.setMarkedOutOfStock('p1', true);

    final secondDump = await hostDb.dumpSince(clientWatermark);
    expect(secondDump['products']!.any((r) => r['id'] == 'p1'), isTrue,
        reason: 'tanpa fix, baris ini tidak akan pernah ikut dump kedua');
    await clientDb.mergeRows('products', secondDump['products']!, false);

    clientProduct = (await clientDb.searchProducts(''))
        .firstWhere((p) => p.id == 'p1');
    expect(clientProduct.markedOutOfStock, isTrue,
        reason: 'tanda stok habis yang di-set owner harus sampai ke klien '
            'setelah sync');
  });
}
