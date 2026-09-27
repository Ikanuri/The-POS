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
//  * Nota lunas -> Kembali dari ronde pembayaran TERAKHIR (`changeGiven`
//    + kembalian Pra-Bayar pre-checkout di baris itu), dicentang atau
//    tidak. Kalau ronde terakhir tanpa kembalian, kembalian terakhir yang
//    BELUM dicentang dari ronde sebelumnya (lihat [displayedChangePayment]).
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

/// Pembayaran yang kembaliannya tampil di baris "Kembali" (status nota
/// TIDAK diperiksa di sini — lihat [lastStateChange]):
///  1. Pembayaran TERAKHIR kalau ronde itu menghasilkan kembalian
///     (changeGiven / potongan Pra-Bayar pre-checkout) — dicentang atau
///     tidak (foto struk user: centang tidak boleh menghapus Kembali).
///  2. Kalau ronde terakhir TANPA kembalian (mis. Tambah Belanjaan dibayar
///     pas), kembalian paling akhir yang BELUM dicentang dari ronde
///     sebelumnya — laporan user: nota dibayar lebih, kembalian tidak
///     dicentang, lalu tambah barang dibayar pas -> struk harus tetap
///     gross (kembaliannya cuma terjadi SEKALI, bukan menumpuk). Kembalian
///     ronde lama yang SUDAH dicentang dianggap selesai (umumnya dipakai
///     ulang memotong tagihan tambahan, lihat `e27bf8a`) & tidak tampil.
TransactionPayment? displayedChangePayment(
    Iterable<TransactionPayment> payments) {
  final latest = latestActivePayment(payments);
  if (latest == null) return null;
  if (latest.changeGiven + (latest.prabayarChangeTakenBeforeCheckout ?? 0) >
      0) {
    return latest;
  }
  TransactionPayment? fallback;
  for (final p in payments) {
    if (p.voided || p.changeTaken || p.changeGiven <= 0) continue;
    if (fallback == null || !p.paidAt.isBefore(fallback.paidAt)) fallback = p;
  }
  return fallback;
}

/// Nominal kembalian [displayedChangePayment] — changeGiven + potongan
/// pre-checkout di baris itu. Status nota TIDAK diperiksa (dipakai nota
/// gabungan, status dicek pemanggil).
int latestRoundChange(Iterable<TransactionPayment> payments) {
  final p = displayedChangePayment(payments);
  if (p == null) return 0;
  final v = p.changeGiven + (p.prabayarChangeTakenBeforeCheckout ?? 0);
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
  final shown = displayedChangePayment(payments);
  if (shown == null || shown.changeTaken) return 0;
  return shown.changeGiven > 0 ? shown.changeGiven : 0;
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
