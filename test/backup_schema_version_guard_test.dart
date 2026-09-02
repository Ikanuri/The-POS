import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/db_export_service.dart';

/// Bug nyata dilaporkan user (screenshot): owner restore backup dari device
/// kasirnya (app versi lebih baru, skema DB sudah migrasi ke kolom baru mis.
/// `transactions.method_name`) ke device pribadinya (app versi lebih lama,
/// skema lokal ketinggalan) -> `SqliteException(1): table transactions has
/// no column named method_name` mentah, membingungkan bagi pengguna awam.
///
/// Akar: `restoreFromDump` menyusun `INSERT` dari kolom apa pun yang ada di
/// dump TANPA tahu skema lokal ketinggalan migrasi. Fix: payload backup
/// sekarang membawa `schemaVersion` (dari `AppDatabase.schemaVersion` saat
/// export) — `DbExportService.restore()` menolak SEBELUM mencoba
/// `restoreFromDump` kalau `schemaVersion` payload > schemaVersion lokal,
/// dengan pesan actionable ("update aplikasi dulu").
void main() {
  test(
      'restore ke device dgn schemaVersion LEBIH LAMA dari backup ditolak '
      'dgn pesan jelas, BUKAN SqliteException mentah', () async {
    final dbSource = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => dbSource.close());
    final bytes =
        await DbExportService.exportPortable(db: dbSource, password: '123456');
    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'k',
      storeUuid: 'u',
      password: '123456',
    );
    // Simulasikan device TUJUAN yang app-nya lebih lama: paksa
    // schemaVersion payload lebih tinggi dari yang sebenarnya diekspor.
    final payload = Map<String, dynamic>.from(decrypted.payload);
    payload['schemaVersion'] = (payload['schemaVersion'] as int) + 1;

    final dbDest = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => dbDest.close());

    await expectLater(
      DbExportService.restore(db: dbDest, payload: payload),
      throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('versi lebih baru'))),
    );
  });

  test(
      'restore ke device dgn schemaVersion SAMA ATAU LEBIH BARU dari backup '
      'tetap berhasil (kasus normal)', () async {
    final dbSource = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => dbSource.close());
    await dbSource.into(dbSource.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Budi'));
    final bytes =
        await DbExportService.exportPortable(db: dbSource, password: '123456');
    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'k',
      storeUuid: 'u',
      password: '123456',
    );

    final dbDest = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => dbDest.close());
    await DbExportService.restore(db: dbDest, payload: decrypted.payload);

    final customers = await dbDest.select(dbDest.customers).get();
    expect(customers.map((c) => c.name), contains('Budi'));
  });

  test(
      'backup LAMA tanpa field schemaVersion sama sekali (dibuat sebelum fix '
      'ini) tetap bisa direstore -- backward compatible', () async {
    final dbSource = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => dbSource.close());
    await dbSource.into(dbSource.customers).insert(
        CustomersCompanion.insert(id: 'c1', name: 'Ani'));
    final bytes =
        await DbExportService.exportPortable(db: dbSource, password: '123456');
    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'k',
      storeUuid: 'u',
      password: '123456',
    );
    final payload = Map<String, dynamic>.from(decrypted.payload)
      ..remove('schemaVersion');

    final dbDest = AppDatabase(NativeDatabase.memory());
    addTearDown(() async => dbDest.close());
    await DbExportService.restore(db: dbDest, payload: payload);

    final customers = await dbDest.select(dbDest.customers).get();
    expect(customers.map((c) => c.name), contains('Ani'));
  });
}
