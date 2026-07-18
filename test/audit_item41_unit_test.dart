import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/database/app_database.dart';
import 'package:the_pos/core/providers/device_provider.dart';
import 'package:the_pos/core/services/crash_log_service.dart';
import 'package:the_pos/core/services/crypto_service.dart';
import 'package:the_pos/core/services/db_export_service.dart';
import 'package:the_pos/core/utils/input_formatters.dart';

/// Item 41 (audit 18 Juli) — regresi unit murni:
///  A.5  password salah pada restore SELALU BackupException (bukan
///       FormatException mentah saat padding CBC kebetulan valid).
///  A.7  parseValue tidak throw utk input digit sangat panjang.
///  A.6  DeviceIdentity.storeKeyLost membedakan "kunci hilang" dari
///       "belum setup".
///  B.3  mergeRows menolak nama tabel non-identifier (defense-in-depth
///       injeksi identifier SQL dari payload sync).
///  B.4  buildEntry memotong pesan/stack panjang (log ada di Downloads
///       publik — jangan tumpahkan data bulat-bulat).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A.7 parseValue', () {
    test('input >15 digit dipotong, TIDAK melempar FormatException', () {
      // 25 digit '9' — dulu int.parse melempar (lewat batas int 64-bit).
      final result = ThousandsSeparatorFormatter.parseValue('9' * 25);
      expect(result, 999999999999999); // 15 digit pertama
    });

    test('perilaku normal tidak berubah', () {
      expect(ThousandsSeparatorFormatter.parseValue('150.000'), 150000);
      expect(ThousandsSeparatorFormatter.parseValue(''), 0);
      expect(ThousandsSeparatorFormatter.parseValue('Rp 5.000'), 5000);
    });
  });

  group('A.5 DbExportService.decrypt', () {
    test(
        'ciphertext yang ter-decrypt mulus tapi BUKAN gzip → BackupException '
        '(bukan FormatException mentah)', () async {
      // Simulasi kasus padding-kebetulan-valid secara deterministik: payload
      // terenkripsi dgn kunci yang BENAR (decrypt pasti sukses), tapi isinya
      // bukan gzip — persis titik yang dulu lolos dari try/catch.
      final salt = CryptoService.randomIV();
      final iv = CryptoService.randomIV();
      final key = CryptoService.derivePortableKeyV2('password-benar', salt);
      final cipher = CryptoService.encryptBytes(
          utf8.encode('bukan gzip sama sekali'), key, iv);
      final fileBytes = <int>[
        ...ascii.encode('BPOP2'),
        ...salt,
        ...iv,
        ...cipher,
      ];

      await expectLater(
        DbExportService.decrypt(
          fileBytes: Uint8List.fromList(fileBytes),
          storeKey: '',
          storeUuid: '',
          password: 'password-benar',
        ),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('A.6 DeviceIdentity.storeKeyLost', () {
    test('storeUuid ada tapi storeKey null → kunci hilang, BUKAN belum setup',
        () {
      const identity = DeviceIdentity(storeUuid: 'uuid-x', storeKey: null);
      expect(identity.storeKeyLost, isTrue);
      expect(identity.isConfigured, isFalse);
    });

    test('belum setup sama sekali → bukan kunci hilang', () {
      const identity = DeviceIdentity();
      expect(identity.storeKeyLost, isFalse);
    });

    test('terkonfigurasi normal → bukan kunci hilang', () {
      const identity = DeviceIdentity(storeUuid: 'uuid-x', storeKey: 'key-x');
      expect(identity.storeKeyLost, isFalse);
      expect(identity.isConfigured, isTrue);
    });
  });

  group('B.3 mergeRows guard identifier', () {
    test('nama tabel non-identifier ditolak ArgumentError', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await expectLater(
        db.mergeRows(
          'stock_ledger" (id) VALUES (\'x\'); --',
          [
            {'id': 'x'}
          ],
          true,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('nama tabel sah tetap diterima', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      // Tabel sah + baris kosong efektif → tidak throw, 0 diterima.
      final n = await db.mergeRows('stock_ledger', const [], true);
      expect(n, 0);
    });
  });

  group('B.4 CrashLogService.buildEntry', () {
    test('pesan & stack panjang dipotong (file log di Downloads publik)', () {
      final entry = CrashLogService.buildEntry(
        error: 'X' * 10000,
        stack: StackTrace.fromString('S' * 20000),
        time: DateTime(2026, 7, 18),
        context: 'test',
      );
      final decoded = jsonDecode(entry) as Map<String, dynamic>;
      final pesan = decoded['pesan'] as String;
      final stack = decoded['stackTrace'] as String;
      expect(pesan.length, lessThan(2100));
      expect(pesan.endsWith('...[dipotong]'), isTrue);
      expect(stack.length, lessThan(6100));
      expect(stack.endsWith('...[dipotong]'), isTrue);
    });

    test('pesan pendek tidak berubah', () {
      final entry = CrashLogService.buildEntry(
        error: 'pesan pendek',
        stack: null,
        time: DateTime(2026, 7, 18),
        context: 'test',
      );
      final decoded = jsonDecode(entry) as Map<String, dynamic>;
      expect(decoded['pesan'], 'pesan pendek');
      expect(decoded['stackTrace'], '');
    });
  });
}
