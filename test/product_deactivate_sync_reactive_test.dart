import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';

/// Follow-up dari `product_deactivate_sync_test.dart` — user lapor "produk
/// di sisi client tetap tidak terhapus" WALAU fix `deactivateProduct`
/// (Task #14) sudah benar mencap `updated_at` & baris ikut terkirim ke
/// klien lewat `dumpSince`. Akar masalah KEDUA, terpisah dari yang pertama:
/// `mergeRows` menulis via `customInsert` RAW SQL TANPA parameter
/// `updates:` — Drift TIDAK TAHU tabel `products` berubah, jadi
/// `StreamProvider`/`.watch()` (dipakai `watchProducts()` di
/// `produk_list_screen.dart` & katalog `kasir_screen.dart`) TIDAK
/// auto-refresh, walau data DI DB SUDAH BENAR (`isActive=false`). UI klien
/// terlihat "tidak berubah" sampai dipaksa reload manual (restart app dll)
/// — persis gejala yang dilaporkan user. Test SEBELUMNYA
/// (`product_deactivate_sync_test.dart`) pakai `searchProducts()` (one-shot
/// Future) yang SELALU dapat data fresh terlepas dari bug ini, jadi TIDAK
/// menangkap kelas bug ini sama sekali — makanya perlu test terpisah yang
/// benar-benar mendengarkan STREAM live, bukan cuma query ulang.
void main() {
  test(
      'watchProducts() (Stream live) ikut ter-refresh otomatis setelah '
      'mergeRows — bukan cuma searchProducts() one-shot', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.saveProduct(
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

    final emissions = <List<String>>[];
    final sub = db
        .watchProducts()
        .listen((rows) => emissions.add(rows.map((p) => p.id).toList()));
    addTearDown(sub.cancel);

    // Tunggu emission pertama (data awal, sebelum sync).
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(emissions, isNotEmpty);
    expect(emissions.last, contains('p1'));
    final emissionCountBeforeMerge = emissions.length;

    // Simulasikan produk dinonaktifkan di HOST lalu diterima klien lewat
    // sync (persis alur nyata: dumpSince di host -> mergeRows di klien).
    await db.mergeRows('products', [
      {
        'id': 'p1',
        'name': 'Indomie Goreng',
        'product_group_id': null,
        'kode_produk': null,
        'parent_product_id': null,
        'is_active': 0,
        'marked_out_of_stock': 0,
        'locally_modified': 0,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }
    ], false);

    // Beri waktu stream Drift meng-emit ulang (async gap sungguhan, BUKAN
    // simulasi manual re-query).
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(emissions.length, greaterThan(emissionCountBeforeMerge),
        reason: 'watchProducts() HARUS meng-emit lagi setelah mergeRows '
            'mengubah tabel products — kalau jumlah emission tidak '
            'bertambah, berarti Drift tidak tahu tabel ini berubah '
            '(customInsert tanpa `updates:`) dan UI klien akan terlihat '
            '"tidak berubah" walau data DB sudah benar');
    expect(emissions.last, isNot(contains('p1')),
        reason: 'produk yang dinonaktifkan owner harus ikut hilang dari '
            'stream produk aktif klien SEGERA setelah sync, tanpa perlu '
            'restart app/reload manual');
  });
}
