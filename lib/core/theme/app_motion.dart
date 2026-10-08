import 'package:flutter/material.dart';

/// Token gerak terpusat — SATU set durasi & kurva untuk seluruh app, supaya
/// semua transisi terasa seirama (prinsip yang sama dgn Telegram: nilai UI
/// tidak pernah berganti mendadak, kurva yang dipakai hanya segelintir).
///
/// Pakai [dur] (bukan konstanta mentah) di widget: bila pengguna mematikan
/// animasi di sistem (`MediaQuery.disableAnimations`), durasi jadi nol.
class AppMotion {
  AppMotion._();

  // ── Durasi ──────────────────────────────────────────────────────────
  /// Umpan balik sentuh (tekan tombol, ganti warna kecil).
  static const fast = Duration(milliseconds: 120);

  /// Perubahan nilai/tampilan biasa (angka, badge, ganti isi).
  static const base = Duration(milliseconds: 200);

  /// Elemen masuk/keluar (sheet, dialog, baris baru).
  static const medium = Duration(milliseconds: 260);

  /// Perpindahan halaman.
  static const page = Duration(milliseconds: 300);

  /// Angka/badge yang berubah (CounterView Telegram: ganti angka 430 ms).
  static const counter = Duration(milliseconds: 430);

  // ── Kurva ───────────────────────────────────────────────────────────
  /// Bawaan umum (CSS `ease`).
  static const Curve standard = Cubic(0.25, 0.1, 0.25, 1);

  /// Mulai cepat, mendarat sangat halus — pilihan utama untuk elemen
  /// yang masuk atau berpindah.
  static const Curve easeOutQuint = Cubic(0.23, 1, 0.32, 1);

  /// Keluar/menutup: pelan di awal lalu mempercepat.
  static const Curve easeIn = Cubic(0.42, 0, 1, 1);

  /// Mendarat lembut tanpa melampaui.
  static const Curve easeOut = Cubic(0, 0, 0.58, 1);

  /// Melampaui sedikit lalu kembali — hanya untuk elemen yang BARU muncul
  /// (badge, chip), jangan untuk perpindahan halaman.
  static const Curve easeOutBack = Cubic(0.34, 1.56, 0.64, 1);

  /// Pengguna mematikan animasi di sistem?
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Durasi yang menghormati pengaturan "kurangi animasi".
  static Duration dur(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
