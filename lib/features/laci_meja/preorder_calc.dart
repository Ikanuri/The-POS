import '../../core/database/app_database.dart';

/// Jaminan (DP wadah fisik) yang MASIH tersisa dari satu entri pre-order —
/// diasumsikan terkonsumsi 1:1 dgn qty yang sudah diambil (`taken`), sama
/// seperti wadah kosong dikembalikan begitu barangnya diserahkan.
///
/// SATU logic dipakai dashboard (`laci_meja_dashboard_screen.dart`,
/// `_buildPreorderList`/`_preorderTile`) MAUPUN laporan salin-teks
/// (`preorder_report.dart`) — sebelumnya laporan salin-teks salah pakai
/// `depositQty` MENTAH (jaminan awal, tidak dikurangi walau pre-order sudah
/// dipenuhi sebagian), padahal itu bukan keputusan desain, cuma bug: contoh
/// dummy yang dipakai saat implementasi kebetulan tidak menunjukkan kasus
/// "dipenuhi sebagian" jadi lolos tanpa ketahuan. Lihat CHANGELOG.
///
/// [taken] = qty yang sudah diambil dari entri ini (dari `takenQty[e.id]`).
double sisaDeposit(PreorderEntry e, double taken) {
  if (e.depositQty <= 0) return 0.0;
  return (e.depositQty - taken).clamp(0.0, e.depositQty);
}
