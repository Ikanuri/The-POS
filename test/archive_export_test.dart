import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/services/crypto_service.dart';
import 'package:the_pos/core/services/db_export_service.dart';

/// Fitur "Ekspor Arsip" — audit sesi ini menemukan file arsip tahunan
/// (`archive_YYYY.db`, dari Tutup Buku) TIDAK PERNAH ikut backup app sama
/// sekali (`exportPortable`/`exportOwnerTransfer` cuma baca `main.db`).
/// `DbExportService.exportArchive` menambahkan jalur ekspor TERPISAH
/// (format .posarsip, magic "BPOA1") — sengaja beda dari backup biasa
/// (BPOP2) supaya tidak disalahpahami sbg pengganti backup penuh.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          id: 'tx1',
          localId: 'K1-A',
          status: 'lunas',
          total: 15000,
          paid: 15000,
          changeAmount: 0,
          paymentMethod: 'tunai',
        ));
  });
  tearDown(() async => db.close());

  test('exportArchive: magic bytes = BPOA1 (beda dari BPOP2/BPOS1/dst)',
      () async {
    final bytes =
        await DbExportService.exportArchive(archiveDb: db, password: 'rahasia123', year: 2024);

    expect(bytes.sublist(0, 5), [0x42, 0x50, 0x4F, 0x41, 0x31],
        reason: '"BPOA1" harus jadi 5 byte pertama, format berbeda dari '
            'backup biasa (BPOP2/BPOS1/BPOSP/BPOT1/BPRC1)');
  });

  test('exportArchive: round-trip manual decrypt mengembalikan payload valid '
      'dgn field year & tabel transaksi arsip', () async {
    final bytes = await DbExportService.exportArchive(
        archiveDb: db, password: 'rahasia123', year: 2024);

    // Manual decrypt (BUKAN via decrypt() biasa — format ini sengaja belum
    // punya jalur restore) utk membuktikan payload benar2 bisa dibongkar
    // dgn key yg sama, meniru bagaimana restore-nya nanti akan bekerja.
    final salt = bytes.sublist(5, 21);
    final iv = bytes.sublist(21, 37);
    final cipher = bytes.sublist(37);
    final key = CryptoService.derivePortableKeyV2('rahasia123', salt);
    final compressed = CryptoService.decryptBytes(cipher, key, iv);
    final jsonBytes = GZipCodec().decode(compressed);
    final payload = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;

    expect(payload['year'], 2024);
    expect(payload['schemaVersion'], db.schemaVersion);
    final tables = payload['tables'] as Map<String, dynamic>;
    final txRows = tables['transactions'] as List;
    expect(txRows, hasLength(1));
    expect(txRows.single['id'], 'tx1');
  });

  test('exportArchive: password salah menghasilkan payload gzip/JSON yg gagal '
      'dibongkar (bukti enkripsi benar2 diikat ke password)', () async {
    final bytes = await DbExportService.exportArchive(
        archiveDb: db, password: 'rahasia123', year: 2024);

    final salt = bytes.sublist(5, 21);
    final iv = bytes.sublist(21, 37);
    final cipher = bytes.sublist(37);
    final wrongKey = CryptoService.derivePortableKeyV2('salah-password', salt);

    expect(() {
      final compressed = CryptoService.decryptBytes(cipher, wrongKey, iv);
      final jsonBytes = GZipCodec().decode(compressed);
      jsonDecode(utf8.decode(jsonBytes));
    }, throwsA(anything));
  });

  test('decrypt() biasa menolak file BPOA1 dgn pesan jelas ("file arsip"), '
      'bukan "password salah/file rusak" yg membingungkan', () async {
    final bytes = await DbExportService.exportArchive(
        archiveDb: db, password: 'rahasia123', year: 2024);

    expect(
      () => DbExportService.decrypt(
        fileBytes: bytes,
        storeKey: 'k',
        storeUuid: 'u',
        password: 'rahasia123',
      ),
      throwsA(predicate((e) =>
          e is BackupException && e.message.toLowerCase().contains('arsip'))),
    );
  });
}
