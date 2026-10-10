import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../database/app_database.dart';

/// Empat slot stiker animasi (Lottie `.tgs`) di katalog HTML.
enum StickerSlot {
  /// Halaman awal, di atas "Mau pesan apa hari ini?".
  home('Halaman awal'),

  /// Pencarian tanpa hasil.
  notFound('Produk tidak ditemukan'),

  /// Halaman toko tutup.
  closed('Toko tutup'),

  /// Halaman "Pesanan dikirim!".
  sent('Pesanan terkirim');

  const StickerSlot(this.label);
  final String label;

  /// Key setting (base64 `.tgs` unggahan owner; kosong = pakai bawaan).
  String get settingKey => 'katalog_sticker_${name.toLowerCase()}';

  /// Nama berkas bawaan di `assets/stickers/`.
  String get assetPath => 'assets/stickers/${name.toLowerCase()}.tgs';
}

/// Stiker animasi katalog HTML. Tiap slot punya stiker BAWAAN (aset app) yang
/// bisa diganti owner dengan unggahan `.tgs` sendiri (hasil validasi ketat:
/// gzip -> JSON Lottie, tanpa expression, ukuran dibatasi). Yang dikirim ke
/// halaman katalog adalah JSON Lottie ter-minify; pustaka pemutar HANYA
/// disematkan bila ada minimal satu stiker. Stiker gagal dimuat = slot itu
/// kosong, halaman tetap normal.
class CatalogStickerService {
  CatalogStickerService._();

  static const allKeys = [
    'katalog_sticker_home',
    'katalog_sticker_notfound',
    'katalog_sticker_closed',
    'katalog_sticker_sent',
  ];

  /// Batas berkas `.tgs` (terkompresi) & JSON hasil dekompresi. Berkas .tgs
  /// 200 KB bisa mengembang jauh lebih besar saat didekompresi (gzip JSON
  /// biasanya 5-10x), jadi batas JSON ikut dinaikkan (1 MB) supaya batas
  /// 200 KB itu benar-benar bisa dipakai; jumlah frame tetap dibatasi.
  static const maxTgsBytes = 200 * 1024;
  static const maxJsonBytes = 1024 * 1024;
  static const maxFrames = 600;

  /// Pustaka pemutar (lottie-web, MIT) — lihat assets/stickers/LOTTIE-LICENSE.md.
  static const playerAsset = 'assets/stickers/lottie_light.min.js';

  /// Validasi berkas `.tgs`. Sukses -> JSON ter-minify; gagal -> pesan Indonesia.
  static ({String? json, String? error}) validateTgs(Uint8List bytes) {
    if (bytes.isEmpty) return (json: null, error: 'Berkas kosong');
    if (bytes.length > maxTgsBytes) {
      return (json: null, error: 'Berkas terlalu besar (maks 200 KB)');
    }
    List<int> raw;
    try {
      raw = gzip.decode(bytes);
    } catch (_) {
      return (json: null, error: 'Bukan berkas stiker .tgs yang valid');
    }
    if (raw.length > maxJsonBytes) {
      return (json: null, error: 'Isi stiker terlalu besar (maks 1 MB setelah dibuka)');
    }
    Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(raw));
    } catch (_) {
      return (json: null, error: 'Isi stiker rusak');
    }
    if (parsed is! Map ||
        parsed['layers'] is! List ||
        parsed['fr'] is! num ||
        parsed['ip'] is! num ||
        parsed['op'] is! num ||
        parsed['w'] is! num ||
        parsed['h'] is! num) {
      return (json: null, error: 'Bukan animasi Lottie yang valid');
    }
    final frames = (parsed['op'] as num) - (parsed['ip'] as num);
    if (frames <= 0 || frames > maxFrames) {
      return (json: null, error: 'Animasi terlalu panjang (maks $maxFrames frame)');
    }
    final minified = jsonEncode(parsed);
    // Expression Lottie = JavaScript yang dieksekusi di HP pelanggan.
    if (RegExp(r'"x"\s*:\s*"').hasMatch(minified)) {
      return (json: null, error: 'Stiker memakai expression - tidak diizinkan');
    }
    return (json: minified, error: null);
  }

  /// Simpan unggahan owner (sudah divalidasi pemanggil lewat [validateTgs]).
  static Future<void> setCustom(
          AppDatabase db, StickerSlot slot, Uint8List tgs) =>
      db.setSetting(slot.settingKey, base64Encode(tgs));

  /// Kembali ke stiker bawaan.
  static Future<void> resetToDefault(AppDatabase db, StickerSlot slot) =>
      db.setSetting(slot.settingKey, '');

  static Future<bool> isCustom(AppDatabase db, StickerSlot slot) async =>
      (await db.getSetting(slot.settingKey) ?? '').isNotEmpty;

  /// JSON Lottie tiap slot untuk Publish: unggahan owner bila valid, kalau
  /// tidak aset bawaan. Slot yang gagal dimuat dilewati. [loadAsset] bisa
  /// diganti di test; bawaannya `rootBundle` (di luar binding Flutter ->
  /// kosong, bukan error).
  static Future<Map<StickerSlot, String>> loadForPublish(
    AppDatabase db, {
    Future<Uint8List> Function(String path)? loadAsset,
  }) async {
    final load = loadAsset ??
        (String p) async => (await rootBundle.load(p)).buffer.asUint8List();
    final out = <StickerSlot, String>{};
    for (final slot in StickerSlot.values) {
      try {
        final custom = await db.getSetting(slot.settingKey) ?? '';
        if (custom.isNotEmpty) {
          final v = validateTgs(base64Decode(custom));
          if (v.json != null) {
            out[slot] = v.json!;
            continue;
          }
        }
        final v = validateTgs(await load(slot.assetPath));
        if (v.json != null) out[slot] = v.json!;
      } catch (_) {}
    }
    return out;
  }

  /// Teks pustaka pemutar, atau null bila gagal dimuat.
  static Future<String?> loadPlayer({
    Future<String> Function(String path)? loadText,
  }) async {
    try {
      return await (loadText ?? rootBundle.loadString)(playerAsset);
    } catch (_) {
      return null;
    }
  }
}
