import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../database/app_database.dart';
import 'catalog_sticker_service.dart';

/// Slot stiker animasi (Lottie `.tgs`) di layar Kasir — mengikuti stiker
/// katalog HTML: bawaan aplikasi, bisa diganti unggahan `.tgs` owner.
enum KasirStickerSlot {
  /// Landing Kasir, di atas "Mau jual apa hari ini?".
  landing('Landing Kasir', 'assets/stickers/home.tgs'),

  /// Daftar produk kosong karena pencarian tidak menemukan apa pun.
  notFound('Produk tidak ditemukan', 'assets/stickers/notfound.tgs'),

  /// Daftar produk kosong (belum ada produk / kategori tanpa produk) di Kasir
  /// dan halaman Produk.
  empty('Belum ada produk', 'assets/stickers/empty.tgs');

  const KasirStickerSlot(this.label, this.assetPath);
  final String label;

  /// Berkas bawaan di `assets/stickers/` (sama dengan stiker katalog HTML).
  final String assetPath;

  /// Key setting (base64 `.tgs` unggahan; kosong = pakai bawaan). Terpisah
  /// dari slot katalog (`katalog_sticker_*`) — owner boleh memilih beda.
  String get settingKey => 'kasir_sticker_${name.toLowerCase()}';

  /// Override LOKAL perangkat non-owner (kasir/asisten): TIDAK ada di
  /// `AppDatabase.syncableSettingKeys` -> tak pernah ikut sync; dibuang setelah
  /// sync berhasil dgn host ([KasirLocalOverrides.clear]). Host (owner) adalah
  /// sumber kebenaran.
  String get localKey => 'local_$settingKey';
}

/// Override LOKAL stiker & teks landing Kasir di perangkat NON-owner.
///
/// Kasir/asisten boleh mengubah stiker & teks landing di perangkatnya, tapi
/// itu hanya SEMENTARA: nilai disimpan di key lokal terpisah (bukan key yang
/// disinkronkan — nilai dari host tetap utuh di key aslinya), dan begitu sync
/// dengan host berhasil, override dibuang sehingga tampilan kembali mengikuti
/// host (owner = sumber kebenaran). Tanpa perubahan protokol sync.
class KasirLocalOverrides {
  KasirLocalOverrides._();

  static const titleKey = 'local_kasir_landing_title';
  static const subtitleKey = 'local_kasir_landing_subtitle';

  static final allKeys = <String>[
    for (final s in KasirStickerSlot.values) s.localKey,
    titleKey,
    subtitleKey,
  ];

  /// Ada override lokal yang aktif?
  static Future<bool> any(AppDatabase db) async {
    for (final k in allKeys) {
      if (((await db.getSetting(k)) ?? '').isNotEmpty) return true;
    }
    return false;
  }

  /// Buang SEMUA override lokal (dipanggil setelah sync dgn host berhasil).
  static Future<void> clear(AppDatabase db) async {
    await (db.delete(db.appSettings)..where((t) => t.key.isIn(allKeys))).go();
  }
}

/// Penyimpanan & pemuatan stiker Kasir. Validasi ketat memakai
/// [CatalogStickerService.validateTgs] (gzip -> JSON Lottie, tanpa
/// expression, batas ukuran/frame).
class KasirStickerService {
  KasirStickerService._();

  /// [local] true (perangkat non-owner): simpan sbg override LOKAL sementara
  /// (kembali mengikuti host saat sync); false (owner): setting toko yang
  /// disinkronkan ke semua perangkat.
  static Future<void> setCustom(
          AppDatabase db, KasirStickerSlot slot, Uint8List tgs,
          {bool local = false}) =>
      db.setSetting(
          local ? slot.localKey : slot.settingKey, base64Encode(tgs));

  /// Owner: kembali ke bawaan aplikasi. Non-owner ([local] true): buang
  /// override lokal -> kembali mengikuti host.
  static Future<void> resetToDefault(AppDatabase db, KasirStickerSlot slot,
      {bool local = false}) async {
    if (local) {
      await (db.delete(db.appSettings)
            ..where((t) => t.key.equals(slot.localKey)))
          .go();
    } else {
      await db.setSetting(slot.settingKey, '');
    }
  }

  /// Slot memakai unggahan (override lokal ATAU setting host)?
  static Future<bool> isCustom(AppDatabase db, KasirStickerSlot slot) async =>
      (await db.getSetting(slot.localKey) ?? '').isNotEmpty ||
      (await db.getSetting(slot.settingKey) ?? '').isNotEmpty;

  /// Slot ini sedang memakai override LOKAL (sementara) di perangkat ini?
  static Future<bool> isLocalOverride(
          AppDatabase db, KasirStickerSlot slot) async =>
      (await db.getSetting(slot.localKey) ?? '').isNotEmpty;

  /// JSON Lottie slot [slot]: unggahan owner bila valid, kalau tidak aset
  /// bawaan; null bila keduanya gagal (slot disembunyikan, layar normal).
  /// [loadAsset] dapat diganti di test.
  static Future<String?> loadJson(
    AppDatabase db,
    KasirStickerSlot slot, {
    Future<Uint8List> Function(String path)? loadAsset,
  }) async {
    try {
      // Urutan: override lokal (non-owner, sementara) -> unggahan owner
      // (tersinkron) -> bawaan aplikasi. Yang tak valid dilewati.
      for (final key in [slot.localKey, slot.settingKey]) {
        final custom = await db.getSetting(key) ?? '';
        if (custom.isNotEmpty) {
          final v = CatalogStickerService.validateTgs(base64Decode(custom));
          if (v.json != null) return v.json;
        }
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

/// Teks di bawah stiker pada landing Kasir (judul + subjudul). Nilai resmi
/// ditetapkan owner dan tersinkron ke perangkat lain lewat setting toko
/// (`AppDatabase.syncableSettingKeys`, arah host -> klien). Perangkat non-owner
/// boleh mengubahnya SEMENTARA (override lokal, lihat [KasirLocalOverrides]):
/// kembali mengikuti host setelah sync. Kosong = pakai teks bawaan.
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
    // Override lokal (non-owner, sementara) menang atas setting host.
    var t = (await db.getSetting(KasirLocalOverrides.titleKey))?.trim() ?? '';
    if (t.isEmpty) t = (await db.getSetting(titleKey))?.trim() ?? '';
    var s =
        (await db.getSetting(KasirLocalOverrides.subtitleKey))?.trim() ?? '';
    if (s.isEmpty) s = (await db.getSetting(subtitleKey))?.trim() ?? '';
    return KasirLandingText(
      title: t.isEmpty ? defaults.title : t,
      subtitle: s.isEmpty ? defaults.subtitle : s,
    );
  }

  /// Teks kosong = kembali ke bawaan (disimpan sbg string kosong).
  ///
  /// [local] true (perangkat non-owner): simpan sbg override LOKAL sementara
  /// (kosong = buang override -> ikut host); false (owner): setting toko yang
  /// disinkronkan.
  static Future<void> save(AppDatabase db,
      {required String title,
      required String subtitle,
      bool local = false}) async {
    final tk = local ? KasirLocalOverrides.titleKey : titleKey;
    final sk = local ? KasirLocalOverrides.subtitleKey : subtitleKey;
    if (local) {
      for (final e in {tk: title.trim(), sk: subtitle.trim()}.entries) {
        if (e.value.isEmpty) {
          await (db.delete(db.appSettings)..where((t) => t.key.equals(e.key)))
              .go();
        } else {
          await db.setSetting(e.key, e.value);
        }
      }
      return;
    }
    await db.setSetting(tk, title.trim());
    await db.setSetting(sk, subtitle.trim());
  }

  /// true bila teks yang berlaku bukan bawaan (override lokal ATAU host).
  static Future<bool> isCustom(AppDatabase db) async =>
      ((await db.getSetting(titleKey)) ?? '').trim().isNotEmpty ||
      ((await db.getSetting(subtitleKey)) ?? '').trim().isNotEmpty ||
      ((await db.getSetting(KasirLocalOverrides.titleKey)) ?? '')
          .trim()
          .isNotEmpty ||
      ((await db.getSetting(KasirLocalOverrides.subtitleKey)) ?? '')
          .trim()
          .isNotEmpty;
}
