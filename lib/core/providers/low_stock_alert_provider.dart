import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Item 46 — antrian pesan "stok menipis" hasil checkout terakhir, untuk
/// ditampilkan sebagai banner inline di layar kasir SAAT pengguna kembali ke
/// kasir (bukan sesaat setelah bayar, yang masih di layar struk). Diisi oleh
/// `payment_screen.dart` setelah transaksi tersimpan; dikuras (di-set ke [])
/// oleh `kasir_screen.dart` saat menampilkannya.
final pendingLowStockAlertsProvider =
    StateProvider<List<String>>((ref) => const []);
