import '../database/app_database.dart';

/// Jaminan (DP wadah fisik) yang MASIH tersisa dari satu entri pre-order —
/// diasumsikan terkonsumsi 1:1 dgn qty yang sudah diambil (`taken`), sama
/// seperti wadah kosong dikembalikan begitu barangnya diserahkan.
///
/// SATU logic dipakai dashboard (`laci_meja_dashboard_screen.dart`,
/// `_buildPreorderList`/`_preorderTile`), laporan salin-teks
/// (`preorder_report.dart`), MAUPUN penanda inline "· Titip N" di baris
/// item nota (`AppDatabase.getPreorderDepositForTransaction`, dipakai struk
/// in-app/share/ESC-POS) — sebelumnya laporan salin-teks & penanda inline
/// salah pakai `depositQty` MENTAH (jaminan awal, tidak dikurangi walau
/// pre-order sudah dipenuhi sebagian), padahal itu bukan keputusan desain,
/// cuma bug: contoh dummy yang dipakai saat implementasi kebetulan tidak
/// menunjukkan kasus "dipenuhi sebagian" jadi lolos tanpa ketahuan. Lihat
/// CHANGELOG.
///
/// Ditaruh di `core/utils` (bukan `features/laci_meja`) supaya `AppDatabase`
/// bisa memakainya tanpa import balik ke layer features;
/// `features/laci_meja/preorder_calc.dart` tinggal re-export.
///
/// [taken] = qty yang sudah diambil dari entri ini (dari `takenQty[e.id]`).
double sisaDeposit(PreorderEntry e, double taken) {
  if (e.depositQty <= 0) return 0.0;
  return (e.depositQty - taken).clamp(0.0, e.depositQty);
}

/// Jaminan pre-order yang dititip utk SATU baris item nota, dari peta hasil
/// `AppDatabase.getPreorderDepositForTransaction` — dipakai ketiga penampil
/// struk (in-app, share `_ReceiptPaper`, ESC/POS `printer_service.dart`)
/// supaya aturan pencocokannya SATU: key presisi `transaction_item_id`
/// (`item.id`) dicek dulu, baru fallback `'$productId|$productUnitId'` utk
/// entri lama yang belum punya tautan baris. Null = tidak ada penanda.
///
/// Bug nyata dilaporkan user: satu nota punya 2 baris LPG (baris asli +
/// "Tambahan") dgn entri pre-order masing-masing — peta lama HANYA keyed
/// produk+satuan, entri kedua MENIMPA yang pertama, jadi kedua baris sama-
/// sama tertulis "Titip 1" padahal kartu Pre-order (benar) menampilkan 2+1.
double? preorderDepositForLine(
    Map<String, double> marks, TransactionItem item) {
  return marks[item.id] ?? marks['${item.productId}|${item.productUnitId}'];
}
