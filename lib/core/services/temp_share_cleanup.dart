import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Item 8 — file gambar/HTML sementara yang dibuat utk "Bagikan Struk"/
/// "Bagikan Katalog" (`receipt_screen.dart`, `merged_receipt_screen.dart`,
/// `catalog_share.dart`, `order_share_screen.dart`) ditulis ke
/// `getTemporaryDirectory()` untuk diserahkan ke `Share.shareXFiles`, TAPI
/// sebelumnya tidak pernah dihapus lagi — menumpuk selamanya di OS temp dir.
/// Dibersihkan best-effort saat startup (bukan langsung setelah share,
/// karena OS mungkin masih butuh file itu selagi share sheet/app tujuan
/// masih membacanya).
class TempShareCleanup {
  TempShareCleanup._();

  static const _prefixes = ['struk_', 'katalog_'];
  static const _maxAge = Duration(hours: 24);

  static Future<void> run() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!dir.existsSync()) return;
      final now = DateTime.now();
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!_prefixes.any((p) => name.startsWith(p))) continue;
        try {
          final modified = entity.statSync().modified;
          if (now.difference(modified) > _maxAge) {
            entity.deleteSync();
          }
        } catch (_) {
          // Best-effort per file — lanjut ke file berikutnya.
        }
      }
    } catch (_) {
      // Non-fatal — kegagalan bersih-bersih tidak boleh mengganggu startup.
    }
  }
}
