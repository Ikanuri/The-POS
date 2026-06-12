import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../database/app_database.dart';
import 'crypto_service.dart';

/// Format file .berkahpos:
///   "BPOS1" (5 bytes) + IV (16 bytes) + AES-256-CBC(gzip(JSON dump))
///   "BPOSP" — varian portable: key hanya dari password (tanpa store_key),
///             bisa di-restore di toko mana pun (dataset contoh / migrasi).
///
/// Key BPOS1: CryptoService.deriveFileKey(storeKey, password, storeUuid)
/// Key BPOSP: CryptoService.derivePortableKey(password)
class DbExportService {
  DbExportService._();

  static const _magic = [0x42, 0x50, 0x4F, 0x53, 0x31]; // "BPOS1"
  static const _magicPortable = [0x42, 0x50, 0x4F, 0x53, 0x50]; // "BPOSP"

  /// Export semua tabel ke bytes terenkripsi.
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
    final isPortable = _listEquals(magic, Uint8List.fromList(_magicPortable));
    if (!isPortable && !_listEquals(magic, Uint8List.fromList(_magic))) {
      throw BackupException('Bukan file backup .berkahpos yang valid');
    }
    final iv = fileBytes.sublist(5, 21);
    final cipher = fileBytes.sublist(21);
    final key = isPortable
        ? CryptoService.derivePortableKey(password)
        : CryptoService.deriveFileKey(storeKey, password, storeUuid);
    late List<int> compressed;
    try {
      compressed = CryptoService.decryptBytes(Uint8List.fromList(cipher), key, Uint8List.fromList(iv));
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
