import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saklar diagnostik performa (build beta): mematikan SATU PER SATU hal yang
/// diduga membuat layar Kasir berat, supaya biang lag bisa dicari langsung di
/// HP. Semua `true` = tampilan normal. Saklar uji (`hideCartWhileTyping`,
/// `perfOverlay`, `meter`) default mati.
@immutable
class PerfDiagState {
  const PerfDiagState({
    this.stickers = true,
    this.shadows = true,
    this.blobs = true,
    this.pressScale = true,
    this.pageFade = true,
    this.heroAnim = true,
    this.hintRotate = true,
    this.tileDecor = true,
    this.recentQuery = true,
    this.perfOverlay = false,
    this.meter = false,
  });

  /// Stiker Lottie (landing & produk tidak ditemukan).
  final bool stickers;

  /// Semua bayangan blur (pil cari, cart bar, kartu produk, tombol header).
  final bool shadows;

  /// Blob warna di latar.
  final bool blobs;

  /// Animasi pantul tombol (`PressScale`) di kartu/tile/chip.
  final bool pressScale;

  /// Fade seluruh halaman saat pindah rute (saveLayer layar penuh).
  final bool pageFade;

  /// Animasi sapaan menciut & kolom cari berpindah (layout per frame).
  final bool heroAnim;

  /// Saran bergilir di kolom cari.
  final bool hintRotate;

  /// Dekorasi kartu produk (bayangan + potong sudut).
  final bool tileDecor;

  /// Query "terakhir dijual"/"sering dibeli" + saran pelanggan.
  final bool recentQuery;

  /// Overlay performa bawaan Flutter (grafik build/raster).
  final bool perfOverlay;

  /// Meter frame kecil di layar (rata-rata/maks ms, % frame patah).
  final bool meter;

  static const normal = PerfDiagState();

  PerfDiagState copyWith({
    bool? stickers,
    bool? shadows,
    bool? blobs,
    bool? pressScale,
    bool? pageFade,
    bool? heroAnim,
    bool? hintRotate,
    bool? tileDecor,
    bool? recentQuery,
    bool? perfOverlay,
    bool? meter,
  }) =>
      PerfDiagState(
        stickers: stickers ?? this.stickers,
        shadows: shadows ?? this.shadows,
        blobs: blobs ?? this.blobs,
        pressScale: pressScale ?? this.pressScale,
        pageFade: pageFade ?? this.pageFade,
        heroAnim: heroAnim ?? this.heroAnim,
        hintRotate: hintRotate ?? this.hintRotate,
        tileDecor: tileDecor ?? this.tileDecor,
        recentQuery: recentQuery ?? this.recentQuery,
        perfOverlay: perfOverlay ?? this.perfOverlay,
        meter: meter ?? this.meter,
      );

  Map<String, bool> toMap() => {
        'stickers': stickers,
        'shadows': shadows,
        'blobs': blobs,
        'pressScale': pressScale,
        'pageFade': pageFade,
        'heroAnim': heroAnim,
        'hintRotate': hintRotate,
        'tileDecor': tileDecor,
        'recentQuery': recentQuery,
        'perfOverlay': perfOverlay,
        'meter': meter,
      };

  factory PerfDiagState.fromMap(Map<String, dynamic> m) {
    bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
    return PerfDiagState(
      stickers: b('stickers', true),
      shadows: b('shadows', true),
      blobs: b('blobs', true),
      pressScale: b('pressScale', true),
      pageFade: b('pageFade', true),
      heroAnim: b('heroAnim', true),
      hintRotate: b('hintRotate', true),
      tileDecor: b('tileDecor', true),
      recentQuery: b('recentQuery', true),
      perfOverlay: b('perfOverlay', false),
      meter: b('meter', false),
    );
  }

  /// Hanya yang BERBEDA dari normal (kosong = semua normal).
  String summary() => toMap()
      .entries
      .where((e) => e.value != PerfDiagState.normal.toMap()[e.key])
      .map((e) => '${e.key}=${e.value ? "ON" : "OFF"}')
      .join(', ');

  /// SEMUA saklar (ON/OFF) - yang bukan normal diberi tanda `*`. Dipakai
  /// tombol "Salin pengaturan" supaya laporan uji lengkap & tak ambigu
  /// (saklar uji seperti meter/overlay/hideCart normalnya OFF).
  String summaryAll() {
    final normal = PerfDiagState.normal.toMap();
    return toMap()
        .entries
        .map((e) =>
            '${e.key}=${e.value ? "ON" : "OFF"}${e.value != normal[e.key] ? "*" : ""}')
        .join(', ');
  }
}

/// Penyimpanan global saklar diagnostik. Widget membaca `PerfDiag.s` pada
/// build; perubahan memberi tahu lewat [notifier].
class PerfDiag {
  PerfDiag._();

  static const prefKey = 'perf_diag_v1';
  static final ValueNotifier<PerfDiagState> notifier =
      ValueNotifier(PerfDiagState.normal);

  static PerfDiagState get s => notifier.value;

  /// Dipanggil sekali di `main()` sebelum `runApp`; gagal membaca = normal.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefKey);
      if (raw == null) return;
      notifier.value =
          PerfDiagState.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  static Future<void> set(PerfDiagState next) async {
    notifier.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (next.toMap().toString() == PerfDiagState.normal.toMap().toString()) {
        await prefs.remove(prefKey);
      } else {
        await prefs.setString(prefKey, jsonEncode(next.toMap()));
      }
    } catch (_) {}
  }
}
