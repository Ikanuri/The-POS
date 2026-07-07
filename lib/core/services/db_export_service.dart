import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../database/app_database.dart';
import 'crypto_service.dart';

/// Format file .berkahpos:
///   "BPOS1" (5 bytes) + IV (16) + AES-256-CBC(gzip(JSON))           ← toko v1
///   "BPOSP" (5 bytes) + IV (16) + ...                                ← portable v1 (salt hardcoded)
///   "BPOP2" (5 bytes) + salt (16) + IV (16) + ...                   ← portable v2 (salt acak)
///
/// Key BPOS1: PBKDF2(storeKey+password, storeUuid)
/// Key BPOSP: PBKDF2(password, 'the-pos-portable-v1')          ← insecure, backward compat only
/// Key BPOP2: PBKDF2(password, salt_from_file)                 ← aman, salt unik per file
class DbExportService {
  DbExportService._();

  static const _magic = [0x42, 0x50, 0x4F, 0x53, 0x31]; // "BPOS1"
  static const _magicPortable = [0x42, 0x50, 0x4F, 0x53, 0x50]; // "BPOSP"
  static const _magicPortableV2 = [0x42, 0x50, 0x4F, 0x50, 0x32]; // "BPOP2"

  /// Export semua tabel ke bytes terenkripsi (BPOS1 — toko spesifik).
  static Future<Uint8List> export({
    required AppDatabase db,
    required String storeKey,
    required String storeUuid,
    required String password,
  }) async {
    final dump = await db.dumpAllTables();
    final payload = <String, dynamic>{
      'storeUuid': storeUuid,
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': dump,
    };
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final compressed = GZipCodec().encode(jsonBytes);
    final key = CryptoService.deriveFileKey(storeKey, password, storeUuid);
    final iv = CryptoService.randomIV();
    final encrypted = CryptoService.encryptBytes(compressed, key, iv);
    return Uint8List.fromList([..._magic, ...iv, ...encrypted]);
  }

  /// Export portable BPOP2 — lintas toko, salt acak disimpan di header.
  static Future<Uint8List> exportPortable({
    required AppDatabase db,
    required String password,
  }) async {
    final dump = await db.dumpAllTables();
    final payload = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'tables': dump,
    };
    final jsonBytes = utf8.encode(jsonEncode(payload));
    final compressed = GZipCodec().encode(jsonBytes);
    final salt = CryptoService.randomIV(); // 16 random bytes
    final key = CryptoService.derivePortableKeyV2(password, salt);
    final iv = CryptoService.randomIV();
    final encrypted = CryptoService.encryptBytes(compressed, key, iv);
    return Uint8List.fromList([..._magicPortableV2, ...salt, ...iv, ...encrypted]);
  }

  /// Decrypt dan parse file. Throws [BackupException] jika invalid.
  static Future<Map<String, dynamic>> decrypt({
    required Uint8List fileBytes,
    required String storeKey,
    required String storeUuid,
    required String password,
  }) async {
    if (fileBytes.length < 5 + 16) {
      throw BackupException('File terlalu kecil atau rusak');
    }
    final magic = fileBytes.sublist(0, 5);
    final isPortableV1 = _listEquals(magic, Uint8List.fromList(_magicPortable));
    final isPortableV2 = _listEquals(magic, Uint8List.fromList(_magicPortableV2));
    final isPortable = isPortableV1 || isPortableV2;

    if (!isPortable && !_listEquals(magic, Uint8List.fromList(_magic))) {
      throw BackupException('Bukan file backup .berkahpos yang valid');
    }

    late List<int> iv;
    late List<int> cipherBytes;
    late Uint8List key;

    if (isPortableV2) {
      // BPOP2: magic(5) + salt(16) + IV(16) + ciphertext
      if (fileBytes.length < 5 + 16 + 16) {
        throw BackupException('File terlalu kecil atau rusak');
      }
      final salt = fileBytes.sublist(5, 21);
      iv = fileBytes.sublist(21, 37);
      cipherBytes = fileBytes.sublist(37);
      key = CryptoService.derivePortableKeyV2(password, salt);
    } else if (isPortableV1) {
      // BPOSP: magic(5) + IV(16) + ciphertext — salt hardcoded (legacy)
      iv = fileBytes.sublist(5, 21);
      cipherBytes = fileBytes.sublist(21);
      key = CryptoService.derivePortableKey(password);
    } else {
      // BPOS1: magic(5) + IV(16) + ciphertext — salt = storeUuid
      iv = fileBytes.sublist(5, 21);
      cipherBytes = fileBytes.sublist(21);
      key = CryptoService.deriveFileKey(storeKey, password, storeUuid);
    }

    late List<int> compressed;
    try {
      compressed = CryptoService.decryptBytes(
          Uint8List.fromList(cipherBytes), key, Uint8List.fromList(iv));
    } catch (_) {
      throw BackupException('Password salah atau file rusak');
    }
    final jsonBytes = GZipCodec().decode(compressed);
    final payload = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    final payloadUuid = payload['storeUuid'] as String?;
    // File portable sengaja lintas-toko — lewati pengecekan asal toko.
    if (!isPortable && payloadUuid != null && payloadUuid != storeUuid) {
      throw BackupException('File backup berasal dari toko yang berbeda');
    }
    return payload;
  }

  /// Restore dari parsed payload ke DB.
  static Future<void> restore({
    required AppDatabase db,
    required Map<String, dynamic> payload,
  }) async {
    final raw = payload['tables'] as Map<String, dynamic>;
    final dump = raw.map((k, v) {
      final rows = (v as List).cast<Map<String, dynamic>>().map((row) {
        return row.map<String, Object?>((rk, rv) => MapEntry(rk, rv));
      }).toList();
      return MapEntry(k, rows);
    });
    await db.restoreFromDump(dump);
  }

  static bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}
