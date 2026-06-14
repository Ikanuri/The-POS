import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/core/models/cart_item.dart';
import 'package:the_pos/core/services/crypto_service.dart';
import 'package:the_pos/core/services/csv_import_service.dart';
import 'package:the_pos/core/services/db_export_service.dart';
import 'package:the_pos/core/services/pairing_service.dart';
import 'package:the_pos/features/kasir/cart_provider.dart';

CartItem _parent({double qty = 1}) => CartItem(
      productId: 'P',
      productUnitId: 'P-base',
      productName: 'Induk',
      unitName: 'Pcs',
      qty: qty,
      price: 1000,
      originalPrice: 1000,
      costPrice: 500,
    );

CartItem _variant(String id, {double qty = 1}) => CartItem(
      productId: 'V$id',
      productUnitId: 'V$id-base',
      productName: 'Varian $id',
      unitName: 'Pcs',
      qty: qty,
      price: 1200,
      originalPrice: 1200,
      costPrice: 600,
      parentProductId: 'P',
      isVariant: true,
    );

double _effParent(CartNotifier n) =>
    n.effectiveQtyFor(n.state.firstWhere((c) => !c.isVariant));

void main() {
  group('CryptoService', () {
    test('generateStoreKey menghasilkan 32 byte base64url', () {
      final key = CryptoService.generateStoreKey();
      expect(key.length, greaterThanOrEqualTo(43));
      expect(CryptoService.generateStoreKey(), isNot(equals(key)));
    });

    test('deriveDbKeyHex deterministik, 64 char hex', () {
      const storeKey = 'dGVzdC1zdG9yZS1rZXktMzItYnl0ZXMtcGFkZGluZyE=';
      final a = CryptoService.deriveDbKeyHex(storeKey);
      final b = CryptoService.deriveDbKeyHex(storeKey);
      expect(a, equals(b));
      expect(a.length, 64);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(a), isTrue);
    });

    test('encrypt/decrypt roundtrip', () {
      final key = CryptoService.deriveSyncKey('store-key', 'ABC123');
      const plain = '{"transactions":[{"id":"x","total":212000}]}';
      final cipher = CryptoService.encryptText(plain, key);
      expect(CryptoService.decryptText(cipher, key), equals(plain));
    });

    test('decrypt dengan key salah gagal', () {
      final key1 = CryptoService.deriveSyncKey('store-key', 'ABC123');
      final key2 = CryptoService.deriveSyncKey('store-key', 'XYZ789');
      final cipher = CryptoService.encryptText('rahasia', key1);
      expect(() => CryptoService.decryptText(cipher, key2),
          throwsA(anything));
    });
  });

  group('PairingService', () {
    test('generate -> encode -> validate roundtrip', () {
      final payload = PairingService.generate(
        storeUuid: 'uuid-1234',
        storeKey: 'key-base64',
        storeName: 'Berkah Grosir',
        role: 'kasir',
      );
      final decoded = PairingService.validate(payload.encode());
      expect(decoded, isNotNull);
      expect(decoded!.storeUuid, 'uuid-1234');
      expect(decoded.storeKey, 'key-base64');
      expect(decoded.role, 'kasir');
    });

    test('QR sampah ditolak', () {
      expect(PairingService.validate('bukan-qr-valid!!'), isNull);
    });

    test('payload expired ditolak', () {
      final expired = PairingPayload(
        storeUuid: 'u',
        storeKey: 'k',
        storeName: 's',
        role: 'kasir',
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      );
      expect(() => PairingService.validate(expired.encode()),
          throwsA(isA<PairingExpiredException>()));
    });

    test('role tidak valid ditolak', () {
      final bad = PairingPayload(
        storeUuid: 'u',
        storeKey: 'k',
        storeName: 's',
        role: 'owner', // owner tidak boleh di-pair via QR
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
      );
      expect(PairingService.validate(bad.encode()), isNull);
    });
  });

  // ── CSV Parser ────────────────────────────────────────────────────────────

  group('CsvImportService._parseCsv', () {
    test('simple CSV parsed correctly', () {
      const csv = 'nama,harga_jual,barcode\nIndomie Goreng,3500,8992388011178\n';
      final rows = CsvImportService.testParseCsv(csv);
      expect(rows.length, 2); // header + 1 data row
      expect(rows[1][0], 'Indomie Goreng');
      expect(rows[1][1], '3500');
      expect(rows[1][2], '8992388011178');
    });

    test('quoted fields with commas handled', () {
      const csv = 'nama,satuan\n"Gula, 1 kg",Kg\n';
      final rows = CsvImportService.testParseCsv(csv);
      expect(rows[1][0], 'Gula, 1 kg');
      expect(rows[1][1], 'Kg');
    });

    test('escaped double quotes in field', () {
      const csv = 'nama\n"He said ""hello"""\n';
      final rows = CsvImportService.testParseCsv(csv);
      expect(rows[1][0], 'He said "hello"');
    });

    test('empty lines skipped', () {
      const csv = 'nama,harga\n\nProduk A,1000\n\n';
      final rows = CsvImportService.testParseCsv(csv);
      expect(rows.length, 2);
    });

    test('CRLF line endings handled', () {
      const csv = 'nama,harga\r\nProduk A,1000\r\n';
      final rows = CsvImportService.testParseCsv(csv);
      expect(rows.length, 2);
      expect(rows[1][0], 'Produk A');
    });
  });

  // ── .berkahpos encrypt/decrypt round-trip ─────────────────────────────────

  group('DbExportService', () {
    const storeKey = 'dGVzdC1zdG9yZS1rZXktMzItYnl0ZXMtcGFkZGluZyE=';
    const storeUuid = 'test-store-uuid-1234';
    const password = 'test-password-123';

    test('magic bytes prefix correct', () {
      // Build a minimal fake export
      final key = CryptoService.deriveFileKey(storeKey, password, storeUuid);
      final iv = CryptoService.randomIV();
      final fakePayload = <String, dynamic>{
        'storeUuid': storeUuid,
        'exportedAt': DateTime.now().toIso8601String(),
        'tables': <String, dynamic>{},
      };
      final jsonBytes = utf8.encode(jsonEncode(fakePayload));
      final compressed = GZipCodec().encode(jsonBytes);
      final encrypted = CryptoService.encryptBytes(compressed, key, iv);
      final fileBytes = Uint8List.fromList(
          [0x42, 0x50, 0x4F, 0x53, 0x31, ...iv, ...encrypted]);

      expect(fileBytes[0], 0x42); // 'B'
      expect(fileBytes[1], 0x50); // 'P'
      expect(fileBytes[2], 0x4F); // 'O'
      expect(fileBytes[3], 0x53); // 'S'
      expect(fileBytes[4], 0x31); // '1'
    });

    test('decrypt roundtrip with correct password', () async {
      final key = CryptoService.deriveFileKey(storeKey, password, storeUuid);
      final iv = CryptoService.randomIV();
      final fakePayload = <String, dynamic>{
        'storeUuid': storeUuid,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'tables': {'products': []},
      };
      final jsonBytes = utf8.encode(jsonEncode(fakePayload));
      final compressed = GZipCodec().encode(jsonBytes);
      final encrypted = CryptoService.encryptBytes(compressed, key, iv);
      final fileBytes = Uint8List.fromList(
          [0x42, 0x50, 0x4F, 0x53, 0x31, ...iv, ...encrypted]);

      final result = await DbExportService.decrypt(
        fileBytes: fileBytes,
        storeKey: storeKey,
        storeUuid: storeUuid,
        password: password,
      );
      expect(result['storeUuid'], storeUuid);
      expect(result['tables'], isA<Map>());
    });

    test('decrypt with wrong password throws BackupException', () async {
      final key = CryptoService.deriveFileKey(storeKey, password, storeUuid);
      final iv = CryptoService.randomIV();
      final fakePayload = <String, dynamic>{
        'storeUuid': storeUuid,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'tables': {},
      };
      final jsonBytes = utf8.encode(jsonEncode(fakePayload));
      final compressed = GZipCodec().encode(jsonBytes);
      final encrypted = CryptoService.encryptBytes(compressed, key, iv);
      final fileBytes = Uint8List.fromList(
          [0x42, 0x50, 0x4F, 0x53, 0x31, ...iv, ...encrypted]);

      expect(
        () => DbExportService.decrypt(
          fileBytes: fileBytes,
          storeKey: storeKey,
          storeUuid: storeUuid,
          password: 'wrong-password',
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('invalid magic bytes throws BackupException', () async {
      final garbage = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]);
      expect(
        () => DbExportService.decrypt(
          fileBytes: garbage,
          storeKey: storeKey,
          storeUuid: storeUuid,
          password: password,
        ),
        throwsA(isA<BackupException>()),
      );
    });
  });

  group('CartItem.copyWith', () {
    test('mengirim null ke itemNote menghapus catatan', () {
      final item = _parent().copyWith(itemNote: 'tanpa saus');
      expect(item.itemNote, 'tanpa saus');
      final cleared = item.copyWith(itemNote: null);
      expect(cleared.itemNote, isNull);
    });

    test('tidak menyebut itemNote mempertahankan catatan', () {
      final item = _parent().copyWith(itemNote: 'pedas');
      final bumped = item.copyWith(qty: 5);
      expect(bumped.itemNote, 'pedas');
      expect(bumped.qty, 5);
    });
  });

  group('CartNotifier varian/induk', () {
    test('scan 1 varian saja → induk placeholder, effective base 0', () {
      final n = CartNotifier();
      n.addItem(_parent(qty: 0)); // _ensureParentInCart: placeholder qty 0
      n.addItem(_variant('A')); // bump varian + induk
      expect(_effParent(n), 0);
      expect(n.totalAmount, 1200); // hanya varian yang ditagih
    });

    test('campur qty dasar + varian: base tidak tertelan', () {
      final n = CartNotifier();
      n.addItem(_parent(qty: 2)); // 2 qty dasar
      n.addItem(_variant('A')); // scan varian pertama kali
      expect(_effParent(n), 2); // qty dasar tetap 2
      expect(n.totalAmount, 2 * 1000 + 1200);
    });

    test('hapus varian terakhir tanpa base → induk ikut hilang', () {
      final n = CartNotifier();
      n.addItem(_parent(qty: 0));
      n.addItem(_variant('A'));
      n.removeItem('VA-base');
      expect(n.state, isEmpty); // induk hilang, sesuai aturan
    });

    test('hapus varian saat masih ada qty dasar → induk tetap', () {
      final n = CartNotifier();
      n.addItem(_parent(qty: 2));
      n.addItem(_variant('A'));
      n.removeItem('VA-base');
      expect(n.state.length, 1);
      expect(_effParent(n), 2);
    });

    test('dua varian: hapus satu, sisanya & induk konsisten', () {
      final n = CartNotifier();
      n.addItem(_parent(qty: 0));
      n.addItem(_variant('A'));
      n.addItem(_variant('B'));
      expect(_effParent(n), 0);
      n.removeItem('VA-base');
      expect(_effParent(n), 0);
      expect(n.state.where((c) => c.isVariant).length, 1);
    });

    test('setEffectiveQty varian menjaga qty dasar induk', () {
      final n = CartNotifier();
      n.addItem(_parent(qty: 2));
      n.addItem(_variant('A'));
      n.setEffectiveQty('VA-base', 3); // varian 1 → 3
      expect(_effParent(n), 2); // base tetap 2
      final variant = n.state.firstWhere((c) => c.isVariant);
      expect(variant.qty, 3);
    });
  });
}
