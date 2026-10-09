import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [EKSPERIMENTAL] Bingkai pemindai ala Telegram (mengikuti posisi kode)
/// untuk SEMUA pemindai kamera: scan barcode produk (Kasir, form produk) dan
/// QR Sync LAN/Gabung Toko. Default MATI — pemindai lama tidak berubah.
/// Disimpan lokal per perangkat (SharedPreferences, tidak tersinkron).
class ScanFrameStyleNotifier extends StateNotifier<bool> {
  ScanFrameStyleNotifier() : super(false) {
    _load();
  }

  static const prefKey = 'scan_frame_telegram';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = prefs.getBool(prefKey) ?? false;
  }

  Future<void> set(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, v);
  }
}

final scanFrameTelegramProvider =
    StateNotifierProvider<ScanFrameStyleNotifier, bool>(
        (ref) => ScanFrameStyleNotifier());

/// [EKSPERIMENTAL] Kunci target pemindai: lama (ms) kode terkunci boleh tak
/// terbaca sebelum kunci dilepas. 0 = MATI (perilaku lama: tiap frame memilih
/// ulang barcode terdekat tengah). Berlaku untuk SEMUA pemindai kamera.
class ScanLockNotifier extends StateNotifier<int> {
  ScanLockNotifier() : super(0) {
    _load();
  }

  static const prefKey = 'scan_lock_ms';

  /// Pilihan dial: 0 (mati) lalu 300..1500 ms per 100.
  static const steps = <int>[
    0, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500
  ];

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final v = prefs.getInt(prefKey) ?? 0;
    state = steps.contains(v) ? v : 0;
  }

  Future<void> set(int ms) async {
    state = ms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(prefKey, ms);
  }
}

final scanLockMsProvider = StateNotifierProvider<ScanLockNotifier, int>(
    (ref) => ScanLockNotifier());
