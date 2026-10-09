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
