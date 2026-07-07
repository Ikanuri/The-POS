import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// AES-256-CBC + PBKDF2-SHA256. Semua enkripsi app lewat sini:
/// - key database SQLCipher (turunan store_key)
/// - payload WiFi sync
/// - file backup .berkahpos
class CryptoService {
  CryptoService._();

  static final _rng = Random.secure();

  /// 32 byte random, base64url — dipakai sebagai store_key master secret.
  static String generateStoreKey() {
    final bytes = Uint8List.fromList(
        List<int>.generate(32, (_) => _rng.nextInt(256)));
    return base64UrlEncode(bytes);
  }

  /// Token sync 12 karakter alfanumerik (~60-bit entropy). Perangkat yang
  /// sudah pairing menyimpan tokennya sendiri, jadi menaikkan panjang ini
  /// hanya berlaku untuk pairing baru (tidak memutus pasangan lama).
  static String generateSyncToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(12, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  static Uint8List randomIV() =>
      Uint8List.fromList(List<int>.generate(16, (_) => _rng.nextInt(256)));

  /// PBKDF2-HMAC-SHA256.
  static Uint8List pbkdf2(
    List<int> password,
    List<int> salt, {
    int iterations = 10000,
    int keyLength = 32,
  }) {
    final hmac = Hmac(sha256, password);
    final blocks = (keyLength / 32).ceil();
    final out = BytesBuilder();
    for (var block = 1; block <= blocks; block++) {
      final blockBytes = ByteData(4)..setUint32(0, block);
      var u = hmac.convert([...salt, ...blockBytes.buffer.asUint8List()]).bytes;
      var t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, keyLength));
  }

  /// Key SQLCipher: PBKDF2(store_key) → hex 64 char.
  /// store_key sudah 256-bit acak, jadi 10 000 iterasi sudah aman; menaikkan
  /// iterasi tidak menambah keamanan untuk input ber-entropi tinggi.
  static String deriveDbKeyHex(String storeKeyBase64) {
    final key = pbkdf2(
      utf8.encode(storeKeyBase64),
      utf8.encode('the-pos-db-v1'),
    );
    return key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Key WiFi sync: PBKDF2(store_key + sync_token).
  static Uint8List deriveSyncKey(String storeKeyBase64, String syncToken) =>
      pbkdf2(utf8.encode(storeKeyBase64 + syncToken), utf8.encode('the-pos-sync-v1'));

  /// HMAC-SHA256 key untuk validasi payload sync (anti-tamper + anti-replay).
  static Uint8List deriveSyncHmacKey(String storeKeyBase64, String syncToken) =>
      pbkdf2(
        utf8.encode(storeKeyBase64 + syncToken),
        utf8.encode('the-pos-hmac-v1'),
        iterations: 1000,
      );

  /// Hitung HMAC-SHA256 dari [data] menggunakan [keyBytes].
  static List<int> hmacSha256(List<int> data, List<int> keyBytes) =>
      Hmac(sha256, keyBytes).convert(data).bytes;

  /// Key file backup: PBKDF2(store_key + password, salt = store_uuid).
  static Uint8List deriveFileKey(
          String storeKeyBase64, String password, String storeUuid) =>
      pbkdf2(utf8.encode(storeKeyBase64 + password), utf8.encode(storeUuid));

  /// Key file backup portable v1 (BPOSP): salt hardcoded. Hanya untuk baca
  /// file lama — export baru pakai derivePortableKeyV2.
  static Uint8List derivePortableKey(String password) =>
      pbkdf2(utf8.encode(password), utf8.encode('the-pos-portable-v1'));

  /// Key file backup portable v2 (BPOP2): salt acak tersimpan di header file.
  /// Di sini input HANYA password (low-entropy), jadi iterasi tinggi (210k)
  /// benar-benar berguna melawan brute-force — beda dari kunci DB yang
  /// inputnya store_key acak. Hanya jalan saat backup/restore manual, bukan
  /// startup, jadi biayanya tidak terasa.
  static Uint8List derivePortableKeyV2(String password, List<int> salt) =>
      pbkdf2(utf8.encode(password), salt, iterations: 210000);

  /// AES-256-CBC dengan IV acak. Output: base64(IV + ciphertext).
  static String encryptText(String plain, Uint8List keyBytes) {
    final key = enc.Key(keyBytes);
    final ivBytes = randomIV();
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plain, iv: enc.IV(ivBytes));
    return base64Encode([...ivBytes, ...encrypted.bytes]);
  }

  /// Kebalikan dari [encryptText] tanpa iv eksplisit.
  static String decryptText(String payloadBase64, Uint8List keyBytes) {
    final raw = base64Decode(payloadBase64);
    final iv = enc.IV(Uint8List.fromList(raw.sublist(0, 16)));
    final cipher = enc.Encrypted(Uint8List.fromList(raw.sublist(16)));
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    return encrypter.decrypt(cipher, iv: iv);
  }

  /// Encrypt bytes dengan IV eksplisit (untuk format file .berkahpos).
  static Uint8List encryptBytes(
      List<int> plain, Uint8List keyBytes, Uint8List iv) {
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    return encrypter.encryptBytes(plain, iv: enc.IV(iv)).bytes;
  }

  static List<int> decryptBytes(
      Uint8List cipher, Uint8List keyBytes, Uint8List iv) {
    final encrypter = enc.Encrypter(enc.AES(enc.Key(keyBytes), mode: enc.AESMode.cbc));
    return encrypter.decryptBytes(enc.Encrypted(cipher), iv: enc.IV(iv));
  }
}
