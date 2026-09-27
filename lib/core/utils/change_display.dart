import '../database/app_database.dart';

// Item 88 (permintaan user) — SATU sumber kebenaran baris "Kembali" utk
// struk in-app, share/gambar & cetak ESC/POS (tunggal maupun gabung nota).
//
// Sebelumnya ada tiga definisi berbeda: in-app memakai pembayaran TERAKHIR
// (tanpa peduli centang), share & cetak memakai pembayaran terakhir yang
// PUNYA kembalian DAN belum dicentang "sudah diambil" (`e27bf8a`). Akibat
// nyata (foto struk dari user): begitu kembalian dicentang (hal wajar
// setelah diserahkan), cetak/share menghapus baris Kembali & menulis
// "Bayar" = Total, padahal riwayat pembayaran di bawahnya menjumlah lebih —
// struk menyesatkan.
//
// Aturan "last state": struk selalu menampilkan KEADAAN TERAKHIR nota.
//  * Nota masih kurang (kurang_bayar/tempo) -> hanya Sisa, TANPA Kembali
//    (inilah yang dulu coba dicapai lewat centang: kembalian ronde lama
//    tidak boleh muncul bersama Sisa ronde baru).
//  * Nota lunas -> Kembali dari ronde pembayaran TERAKHIR: `changeGiven`
//    momen pembayaran itu + kembalian Pra-Bayar yang diambil SEBELUM
//    checkout yang menempel di baris itu. Centang "sudah diambil" TIDAK
//    mengubah angka (murni penanda sudah diserahkan).
// Kembalian yang menumpuk & belum diambil di ronde-ronde lain tidak ikut
// otomatis — kasir menggabungkannya lewat tombol di struk in-app
// ([unclaimedChangeTotal]/[hasExtraUnclaimedChange]).

/// Pembayaran TERAKHIR yang tidak dibatalkan (paidAt terbesar; seri ->
/// yang lebih akhir di list).
TransactionPayment? latestActivePayment(Iterable<TransactionPayment> payments) {
  TransactionPayment? latest;
  for (final p in payments) {
    if (p.voided) continue;
    if (latest == null || !p.paidAt.isBefore(latest.paidAt)) latest = p;
  }
  return latest;
}

bool _isUnpaidStatus(String status) =>
    status == 'kurang_bayar' || status == 'tempo';

/// Kembalian "last state" ronde terakhir, TANPA memeriksa status nota —
/// dipakai [lastStateChange] & nota gabungan (status dicek pemanggil).
int latestRoundChange(Iterable<TransactionPayment> payments) {
  final latest = latestActivePayment(payments);
  if (latest == null) return 0;
  final v = latest.changeGiven + (latest.prabayarChangeTakenBeforeCheckout ?? 0);
  return v > 0 ? v : 0;
}

/// Kembalian yang tampil di struk (baris "Kembali") — lihat aturan di atas.
int lastStateChange(Transaction tx, List<TransactionPayment> payments) =>
    _isUnpaidStatus(tx.status) ? 0 : latestRoundChange(payments);

/// Porsi [lastStateChange] yang BELUM dicentang "sudah diambil" (kembalian
/// momen pembayaran terakhir; potongan Pra-Bayar pre-checkout selalu sudah
/// diambil).
int _lastStateUnclaimed(Transaction tx, List<TransactionPayment> payments) {
  if (_isUnpaidStatus(tx.status)) return 0;
  final latest = latestActivePayment(payments);
  if (latest == null || latest.changeTaken) return 0;
  return latest.changeGiven > 0 ? latest.changeGiven : 0;
}

/// Jumlah SEMUA kembalian yang belum dicentang "sudah diambil" di nota ini
/// (tiap ronde pembayaran). Status centang tetap ikut sync (OR-merge,
/// `mergeRows`), jadi angka ini sama di semua device setelah sinkron.
int unclaimedChangeTotal(List<TransactionPayment> payments) => payments
    .where((p) => !p.voided && !p.changeTaken && p.changeGiven > 0)
    .fold<int>(0, (s, p) => s + p.changeGiven);

/// True kalau ada kembalian belum diambil yang TIDAK terwakili baris
/// "Kembali" last-state (kembalian ronde lama yang menumpuk, atau nota
/// masih kurang tapi ada kembalian lama yang belum diserahkan) — syarat
/// tampilnya tombol "Gabungkan kembalian belum diambil". Tombol hilang
/// begitu semua kembalian dicentang.
bool hasExtraUnclaimedChange(
        Transaction tx, List<TransactionPayment> payments) =>
    unclaimedChangeTotal(payments) > _lastStateUnclaimed(tx, payments);
