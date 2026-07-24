import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/db_export_service.dart';

/// Membuktikan 2 bug yang dilaporkan user lewat test di device asli:
///
/// 1. "Password salah atau data rusak" saat restore di device/toko BARU
///    (fresh install). Root cause: `DbExportService.export()` (format
///    BPOS1) menurunkan kunci dari storeKey TOKO ASAL + password — storeKey
///    acak-baru di-generate ulang tiap setup toko, jadi device/toko tujuan
///    TIDAK MUNGKIN py kunci yang sama walau password persis benar. Fix:
///    backup_screen.dart sekarang pakai `exportPortable()` (format BPOP2,
///    kunci HANYA dari password) — sesuai yang sudah dijanjikan di teks UI
///    ("file ini hanya bisa dibuka dengan password yang Anda tentukan").
///
/// 2. Restore bilang "berhasil" tapi data pelanggan yang dihapus/ditambah
///    SETELAH backup tidak ikut kembali/hilang setelah restore. Root cause:
///    `restoreFromDump` menulis lewat `customStatement`/`customInsert` TANPA
///    parameter `updates:`, jadi Drift tidak tahu tabel mana yang berubah —
///    StreamProvider (mis. daftar pelanggan) yang bergantung pada `.watch()`
///    TIDAK di-notify sama sekali, walau data di DB sungguhan sudah benar.
void main() {
  test(
      'exportPortable + decrypt: restore SUKSES walau storeKey device tujuan '
      'berbeda dari device asal (skenario restore di HP baru)', () async {
    final dbSource = AppDatabase(NativeDatabase.memory());
    await dbSource.into(dbSource.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Budi'));

    final bytes = await DbExportService.exportPortable(
      db: dbSource,
      password: '123456',
    );
    await dbSource.close();

    // Device/toko TUJUAN: storeKey & storeUuid BEDA dari device asal —
    // persis skenario "restore di HP baru".
    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'storeKey-DEVICE-TUJUAN-BEDA-TOTAL',
      storeUuid: 'storeUuid-DEVICE-TUJUAN-BEDA-TOTAL',
      password: '123456',
    );

    final dbDest = AppDatabase(NativeDatabase.memory());
    await DbExportService.restore(db: dbDest, payload: decrypted.payload);
    final customers = await dbDest.select(dbDest.customers).get();
    expect(customers.map((c) => c.name), contains('Budi'));
    await dbDest.close();
  });

  test(
      'exportPortable + decrypt dengan password SALAH tetap ditolak '
      '(bukan cuma storeKey yang longgar)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final bytes = await DbExportService.exportPortable(
      db: db,
      password: 'password-benar',
    );
    await db.close();

    await expectLater(
      DbExportService.decrypt(
        fileBytes: bytes,
        storeKey: 'apa-saja',
        storeUuid: 'apa-saja',
        password: 'password-SALAH',
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test(
      'restoreFromDump men-trigger notifyUpdates — StreamProvider (mis. '
      'daftar pelanggan) HARUS ikut ter-update, bukan tetap stale',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.customers).insert(
        CustomersCompanion.insert(id: 'c-lama', name: 'Pelanggan Lama'));

    // Simulasikan StreamProvider (mis. _pelangganStreamProvider) yang sedang
    // dipakai layar Pelanggan — sama seperti .watch() di produksi.
    final emissions = <List<String>>[];
    final sub = db
        .select(db.customers)
        .watch()
        .listen((rows) => emissions.add(rows.map((c) => c.name).toList()));
    await Future<void>.delayed(Duration.zero);
    expect(emissions.last, ['Pelanggan Lama']);

    // Restore dump yang TIDAK menyertakan "Pelanggan Lama" (dihapus dari
    // backup) tapi menyertakan pelanggan baru dari file backup.
    await db.restoreFromDump({
      'customers': [
        {
          'id': 'c-dari-backup',
          'name': 'Pelanggan Dari Backup',
          'phone': null,
          'address': null,
          'customer_group_id': null,
          'credit_limit': 0,
          'outstanding_debt': 0,
          'loyalty_points': 0,
          'notes': null,
          'is_active': 1,
          'created_at': 1700000000,
          'updated_at': 1700000000,
        }
      ],
    });
    await Future<void>.delayed(Duration.zero);

    expect(emissions.last, ['Pelanggan Dari Backup'],
        reason:
            'StreamProvider pelanggan harus langsung dapat notifikasi dari '
            'Drift setelah restore — bukan tetap menampilkan data lama '
            'sampai app di-restart manual');

    await sub.cancel();
    await db.close();
  });

  test(
      'dumpAllTables + restoreFromDump: toko yang pernah pakai kategori-'
      'tambahan (product_group_tags) TIDAK gagal dgn FOREIGN KEY constraint '
      'saat restore (bug nyata: DELETE FROM product_groups ditolak SQLite)',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.productGroups).insert(
        ProductGroupsCompanion.insert(id: const Value(1), name: const Value('Sembako')));
    await db.into(db.products).insert(
        ProductsCompanion.insert(id: 'p1', name: 'Gula Pasir'));
    // Kategori TAMBAHAN (Item 54) — baris ini yg dulu bikin restore gagal
    // krn tabelnya lupa dimasukkan ke `_allTables`.
    await db.into(db.productGroupTags).insert(
        ProductGroupTagsCompanion.insert(productId: 'p1', groupId: 1));

    final dump = await db.dumpAllTables();
    expect(dump['product_group_tags'], isNotEmpty,
        reason: 'harus ikut ter-backup, bukan cuma tidak error saat restore');

    // Restore dump yang SAMA ke DB yang sama (skenario nyata: backup lalu
    // restore file itu lagi) — dulu ini melempar SqliteException(787) di
    // "DELETE FROM product_groups" krn baris product_group_tags lama tidak
    // pernah ikut dihapus duluan.
    await db.restoreFromDump(dump);

    final tags = await db.select(db.productGroupTags).get();
    expect(tags, hasLength(1));
    expect(tags.single.productId, 'p1');

    await db.close();
  });
}
