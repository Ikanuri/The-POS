import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/db_export_service.dart';

/// Item 27 "Alihkan Owner" — mode ekspor BARU (BPOT1) yang membawa
/// storeUuid/storeKey/storeName toko asal, TERPISAH dari exportPortable
/// (BPOP2/.berkahpos biasa) yang sengaja lintas-toko & tidak membawa
/// identitas. `decrypt()` harus bisa membedakan keduanya via `isOwnerTransfer`
/// supaya pemanggil tahu apakah perlu menerapkan identitas ke device.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test(
      'exportOwnerTransfer -> decrypt: isOwnerTransfer true, payload bawa '
      'storeUuid/storeKey/storeName', () async {
    final bytes = await DbExportService.exportOwnerTransfer(
      db: db,
      password: 'rahasia123',
      storeUuid: 'uuid-asal',
      storeKey: 'key-asal-base64',
      storeName: 'Toko Asal',
    );

    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'key-device-ini-yang-beda',
      storeUuid: 'uuid-device-ini-yang-beda',
      password: 'rahasia123',
    );

    expect(decrypted.isOwnerTransfer, isTrue);
    expect(decrypted.payload['storeUuid'], 'uuid-asal');
    expect(decrypted.payload['storeKey'], 'key-asal-base64');
    expect(decrypted.payload['storeName'], 'Toko Asal');
    expect(decrypted.payload['tables'], isNotNull);
  });

  test(
      'exportOwnerTransfer TIDAK terikat storeUuid/storeKey device penerima '
      '(lintas-toko by design, sama seperti portable biasa)', () async {
    final bytes = await DbExportService.exportOwnerTransfer(
      db: db,
      password: 'pw',
      storeUuid: 'uuid-a',
      storeKey: 'key-a',
      storeName: 'Toko A',
    );

    // storeKey/storeUuid device penerima SAMA SEKALI berbeda dari toko asal
    // — harus tetap berhasil decrypt (bukan ditolak "toko berbeda").
    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'sama-sekali-lain',
      storeUuid: 'sama-sekali-lain-juga',
      password: 'pw',
    );
    expect(decrypted.isOwnerTransfer, isTrue);
  });

  test(
      'exportPortable (.berkahpos biasa) -> decrypt: isOwnerTransfer FALSE, '
      'payload TIDAK bawa storeUuid/storeKey', () async {
    final bytes =
        await DbExportService.exportPortable(db: db, password: 'pw');

    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'apa saja',
      storeUuid: 'apa saja',
      password: 'pw',
    );

    expect(decrypted.isOwnerTransfer, isFalse);
    expect(decrypted.payload['storeUuid'], isNull);
    expect(decrypted.payload['storeKey'], isNull);
  });

  test('password salah pada file BPOT1 tetap ditolak rapi (tidak crash)',
      () async {
    final bytes = await DbExportService.exportOwnerTransfer(
      db: db,
      password: 'password-benar',
      storeUuid: 'u',
      storeKey: 'k',
      storeName: 'T',
    );

    expect(
      () => DbExportService.decrypt(
        fileBytes: bytes,
        storeKey: 'x',
        storeUuid: 'x',
        password: 'password-SALAH',
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test('restore payload BPOT1 mengisi ulang tabel persis seperti restore biasa',
      () async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c-lama',
          name: 'Pelanggan Lama Sebelum Transfer',
        ));

    final bytes = await DbExportService.exportOwnerTransfer(
      db: db,
      password: 'pw',
      storeUuid: 'u',
      storeKey: 'k',
      storeName: 'T',
    );

    // Simulasikan device penerima: DB kosong/beda isi sebelum restore.
    final dbPenerima = AppDatabase(NativeDatabase.memory());
    await dbPenerima.into(dbPenerima.customers).insert(
        CustomersCompanion.insert(id: 'c-beda', name: 'Data Device Penerima'));

    final decrypted = await DbExportService.decrypt(
      fileBytes: bytes,
      storeKey: 'apa saja',
      storeUuid: 'apa saja',
      password: 'pw',
    );
    await DbExportService.restore(db: dbPenerima, payload: decrypted.payload);

    final rows = await dbPenerima.select(dbPenerima.customers).get();
    expect(rows, hasLength(1));
    expect(rows.single.name, 'Pelanggan Lama Sebelum Transfer');
    await dbPenerima.close();
  });

  group('AppDatabase.rekey — validasi input (perilaku enkripsi fisik SQLCipher '
      'sendiri TIDAK bisa dites di sini, NativeDatabase.memory() test pakai '
      'sqlite3 polos yg menganggap PRAGMA rekey sbg no-op, bukan SQLCipher '
      'asli — cukup diverifikasi manual di device sungguhan)', () {
    test('key hex tidak valid (ada karakter non-hex) ditolak', () async {
      expect(() => db.rekey('bukan-hex-!!'), throwsArgumentError);
    });

    test('key hex valid (64 char) tidak throw', () async {
      await db.rekey('a' * 64);
    });
  });
}
