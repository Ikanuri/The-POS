import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../database/app_database.dart';
import 'catalog_sticker_service.dart';

/// Dua slot stiker animasi (Lottie `.tgs`) di layar Kasir — mengikuti stiker
/// katalog HTML: bawaan aplikasi, bisa diganti unggahan `.tgs` owner.
enum KasirStickerSlot {
  /// Landing Kasir, di atas "Mau jual apa hari ini?".
  landing('Landing Kasir', 'assets/stickers/home.tgs'),

  /// Daftar produk kosong karena pencarian tidak menemukan apa pun.
  notFound('Produk tidak ditemukan', 'assets/stickers/notfound.tgs');

  const KasirStickerSlot(this.label, this.assetPath);
  final String label;

  /// Berkas bawaan di `assets/stickers/` (sama dengan stiker katalog HTML).
  final String assetPath;

  /// Key setting (base64 `.tgs` unggahan; kosong = pakai bawaan). Terpisah
  /// dari slot katalog (`katalog_sticker_*`) — owner boleh memilih beda.
  String get settingKey => 'kasir_sticker_${name.toLowerCase()}';
}

/// Penyimpanan & pemuatan stiker Kasir. Validasi ketat memakai
/// [CatalogStickerService.validateTgs] (gzip -> JSON Lottie, tanpa
/// expression, batas ukuran/frame).
class KasirStickerService {
  KasirStickerService._();

  static Future<void> setCustom(
          AppDatabase db, KasirStickerSlot slot, Uint8List tgs) =>
      db.setSetting(slot.settingKey, base64Encode(tgs));

  static Future<void> resetToDefault(AppDatabase db, KasirStickerSlot slot) =>
      db.setSetting(slot.settingKey, '');

  static Future<bool> isCustom(AppDatabase db, KasirStickerSlot slot) async =>
      (await db.getSetting(slot.settingKey) ?? '').isNotEmpty;

  /// JSON Lottie slot [slot]: unggahan owner bila valid, kalau tidak aset
  /// bawaan; null bila keduanya gagal (slot disembunyikan, layar normal).
  /// [loadAsset] dapat diganti di test.
  static Future<String?> loadJson(
    AppDatabase db,
    KasirStickerSlot slot, {
    Future<Uint8List> Function(String path)? loadAsset,
  }) async {
    try {
      final custom = await db.getSetting(slot.settingKey) ?? '';
      if (custom.isNotEmpty) {
        final v = CatalogStickerService.validateTgs(base64Decode(custom));
        if (v.json != null) return v.json;
      }
      final load = loadAsset ??
          (String p) async => (await rootBundle.load(p)).buffer.asUint8List();
      return CatalogStickerService.validateTgs(await load(slot.assetPath))
          .json;
    } catch (_) {
      return null;
    }
  }
}

/// Teks di bawah stiker pada landing Kasir (judul + subjudul). Diubah HANYA
/// oleh owner (UI dibatasi di Pengaturan) dan ikut tersinkron ke perangkat
/// lain lewat setting toko (`AppDatabase.syncableSettingKeys`, arah
/// host -> klien). Kosong = pakai teks bawaan.
class KasirLandingText {
  const KasirLandingText({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  static const titleKey = 'kasir_landing_title';
  static const subtitleKey = 'kasir_landing_subtitle';
  static const maxTitle = 40;
  static const maxSubtitle = 80;

  static const defaults = KasirLandingText(
    title: 'Mau jual apa hari ini?',
    subtitle: 'Scan barang, ketik nama, atau pilih kategori',
  );

  static Future<KasirLandingText> load(AppDatabase db) async {
    final t = (await db.getSetting(titleKey))?.trim() ?? '';
    final s = (await db.getSetting(subtitleKey))?.trim() ?? '';
    return KasirLandingText(
      title: t.isEmpty ? defaults.title : t,
      subtitle: s.isEmpty ? defaults.subtitle : s,
    );
  }

  /// Teks kosong = kembali ke bawaan (disimpan sbg string kosong).
  static Future<void> save(
      AppDatabase db, {required String title, required String subtitle}) async {
    await db.setSetting(titleKey, title.trim());
    await db.setSetting(subtitleKey, subtitle.trim());
  }

  /// true bila teks yang tersimpan bukan bawaan.
  static Future<bool> isCustom(AppDatabase db) async =>
      ((await db.getSetting(titleKey)) ?? '').trim().isNotEmpty ||
      ((await db.getSetting(subtitleKey)) ?? '').trim().isNotEmpty;
}
