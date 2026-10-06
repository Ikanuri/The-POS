import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../database/app_database.dart';

/// Jam buka & kode akses per pelanggan untuk katalog HTML (Item toko tutup).
///
/// Katalog HTML statis: semua pengecekan jam/kode berjalan di browser
/// pelanggan, jadi ini PENGHALANG UNTUK PELANGGAN BIASA/SPAM IKUT-IKUTAN,
/// bukan pagar mutlak (harga tetap ada di sumber HTML). Kode TIDAK pernah
/// dikirim ke HTML — hanya hash PBKDF2-nya; hash dihitung SEKALI saat kode
/// dibuat (bukan tiap Publish), jadi Publish tidak melambat walau
/// pelanggannya ratusan.
class CatalogHours {
  const CatalogHours({
    this.enabled = false,
    this.openMinutes = 7 * 60,
    this.closeMinutes = 21 * 60,
    this.forcedClosed = false,
  });

  /// Jadwal otomatis aktif. Mati = katalog selalu buka (kecuali [forcedClosed]).
  final bool enabled;

  /// Menit sejak 00:00 (waktu toko).
  final int openMinutes;
  final int closeMinutes;

  /// Tombol darurat "Tutup sekarang" — menimpa jadwal.
  final bool forcedClosed;

  static String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
      '${(minutes % 60).toString().padLeft(2, '0')}';

  CatalogHours copyWith({
    bool? enabled,
    int? openMinutes,
    int? closeMinutes,
    bool? forcedClosed,
  }) =>
      CatalogHours(
        enabled: enabled ?? this.enabled,
        openMinutes: openMinutes ?? this.openMinutes,
        closeMinutes: closeMinutes ?? this.closeMinutes,
        forcedClosed: forcedClosed ?? this.forcedClosed,
      );
}

class CatalogAccessService {
  CatalogAccessService._();

  static const hoursEnabledKey = 'catalog_hours_enabled';
  static const hoursOpenKey = 'catalog_hours_open';
  static const hoursCloseKey = 'catalog_hours_close';
  static const forcedClosedKey = 'catalog_forced_closed';
  static const codesKey = 'catalog_customer_codes';
  static const saltKey = 'catalog_code_salt';

  /// PBKDF2-HMAC-SHA256. Sengaja ringan (10.000 putaran): kode hanya
  /// penghalang tampilan, dan browser pelanggan menghitung SATU hash saat
  /// kode diketik (~10-20 ms).
  static const iterations = 10000;

  /// Tanpa 0/O/1/I/L supaya tidak salah baca saat diketik pelanggan.
  static const _alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  // ── Jam buka ─────────────────────────────────────────────────────────

  static Future<CatalogHours> loadHours(AppDatabase db) async {
    final enabled = (await db.getSetting(hoursEnabledKey)) == '1';
    final open = int.tryParse(await db.getSetting(hoursOpenKey) ?? '');
    final close = int.tryParse(await db.getSetting(hoursCloseKey) ?? '');
    final forced = (await db.getSetting(forcedClosedKey)) == '1';
    return CatalogHours(
      enabled: enabled,
      openMinutes: _validMinutes(open) ?? 7 * 60,
      closeMinutes: _validMinutes(close) ?? 21 * 60,
      forcedClosed: forced,
    );
  }

  static int? _validMinutes(int? m) =>
      (m != null && m >= 0 && m < 24 * 60) ? m : null;

  static Future<void> saveHours(AppDatabase db, CatalogHours h) async {
    await db.setSetting(hoursEnabledKey, h.enabled ? '1' : '0');
    await db.setSetting(hoursOpenKey, '${h.openMinutes}');
    await db.setSetting(hoursCloseKey, '${h.closeMinutes}');
    await db.setSetting(forcedClosedKey, h.forcedClosed ? '1' : '0');
  }

  // ── Kode per pelanggan ───────────────────────────────────────────────

  /// Huruf besar, tanpa spasi/tanda hubung — dipakai SAMA di app & browser
  /// (lihat `normCode` di katalog HTML) sebelum di-hash.
  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  /// "XXXX-XXXX" (8 karakter acak aman-kripto).
  static String generateCode([Random? rng]) {
    final r = rng ?? Random.secure();
    String chunk() =>
        List.generate(4, (_) => _alphabet[r.nextInt(_alphabet.length)]).join();
    return '${chunk()}-${chunk()}';
  }

  /// PBKDF2-HMAC-SHA256 (dkLen 32 byte) -> hex. Sama persis dgn
  /// `crypto.subtle.deriveBits` di browser.
  static String pbkdf2Hex(String password, String salt, int iters) {
    final pw = utf8.encode(password);
    final s = utf8.encode(salt);
    final mac = Hmac(sha256, pw);
    // Blok tunggal (dkLen 32 = 1 blok SHA-256): U1 = HMAC(P, S || INT(1)).
    var u = mac.convert([...s, 0, 0, 0, 1]).bytes;
    final t = List<int>.of(u);
    for (var i = 1; i < iters; i++) {
      u = mac.convert(u).bytes;
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<String> _salt(AppDatabase db) async {
    final existing = await db.getSetting(saltKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final r = Random.secure();
    final salt = List.generate(
        16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await db.setSetting(saltKey, salt);
    return salt;
  }

  static Future<Map<String, Map<String, dynamic>>> _loadCodes(
      AppDatabase db) async {
    final raw = await db.getSetting(codesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          e.key as String: Map<String, dynamic>.from(e.value as Map)
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveCodes(
      AppDatabase db, Map<String, Map<String, dynamic>> codes) async {
    await db.setSetting(codesKey, jsonEncode(codes));
  }

  /// Kode aktif pelanggan (null = belum pernah dibuat/sudah dicabut).
  static Future<String?> codeFor(AppDatabase db, String customerId) async =>
      (await _loadCodes(db))[customerId]?['code'] as String?;

  /// Buat kode BARU (atau ganti yang lama) utk [customerId] dan simpan hash-nya.
  /// Perubahan baru berlaku di katalog setelah Publish/bagikan ulang.
  static Future<String> rotateCode(AppDatabase db, String customerId,
      {Random? rng}) async {
    final codes = await _loadCodes(db);
    final salt = await _salt(db);
    final code = generateCode(rng);
    codes[customerId] = {
      'code': code,
      'hash': pbkdf2Hex(normalizeCode(code), salt, iterations),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _saveCodes(db, codes);
    return code;
  }

  static Future<void> revokeCode(AppDatabase db, String customerId) async {
    final codes = await _loadCodes(db);
    if (codes.remove(customerId) != null) await _saveCodes(db, codes);
  }

  /// Data akses utk HTML: HANYA hash (urutan acak-stabil tak diperlukan) dan
  /// parameter turunannya — tanpa kode asli, tanpa nama pelanggan. Kode milik
  /// pelanggan yang sudah dihapus/nonaktif tidak ikut.
  static Future<Map<String, Object?>?> accessJson(AppDatabase db) async {
    final codes = await _loadCodes(db);
    if (codes.isEmpty) return null;
    final active = await (db.select(db.customers)
          ..where((t) => t.isActive.equals(true)))
        .get();
    final activeIds = {for (final c in active) c.id};
    final hashes = [
      for (final e in codes.entries)
        if (activeIds.contains(e.key)) e.value['hash'] as String
    ];
    if (hashes.isEmpty) return null;
    return {
      'salt': await _salt(db),
      'iters': iterations,
      'hashes': hashes,
    };
  }

  /// Blok `hours` utk HTML. `tz` = selisih UTC zona HP owner saat Publish
  /// (menit) — jam toko dihitung dari zona ini, bukan jam lokal pelanggan.
  static Future<Map<String, Object?>?> hoursJson(AppDatabase db,
      {Duration? tzOffset}) async {
    final h = await loadHours(db);
    if (!h.enabled && !h.forcedClosed) return null;
    return {
      'enabled': h.enabled,
      'open': h.openMinutes,
      'close': h.closeMinutes,
      'forced': h.forcedClosed,
      'tz': (tzOffset ?? DateTime.now().timeZoneOffset).inMinutes,
    };
  }
}
