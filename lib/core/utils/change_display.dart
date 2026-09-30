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

/// Item 89 — sisa kembalian tiap ronde SETELAH dipakai ronde berikutnya
/// (`changeReused`, lihat dok kolom). Kunci: id pembayaran; hanya ronde
/// aktif (tidak voided) dgn `changeGiven > 0`.
///  * Ronde-konsumen dgn `changeReused` bernilai (>=0): mengurangi sisa
///    ronde SEBELUMNYA, yang terbaru dulu (jumlah total sama berapa pun
///    urutannya; ini cuma menentukan ronde mana yang tampil).
///  * Ronde-konsumen `changeReused == null` (data LAMA / HP versi lama):
///    jatuh ke aturan centang lama — kembalian ronde sebelumnya yang
///    dicentang dianggap sudah dipakai (habis).
/// Centang "diserahkan" pada data BARU tidak pernah memengaruhi angka.
Map<String, int> _remainingChangeByRound(
    Iterable<TransactionPayment> payments) {
  final active = payments.where((p) => !p.voided).toList()
    ..sort((a, b) => a.paidAt.compareTo(b.paidAt));
  final remaining = <String, int>{
    for (final p in active)
      if (p.changeGiven > 0) p.id: p.changeGiven,
  };
  for (var j = 1; j < active.length; j++) {
    final consumer = active[j];
    if (consumer.changeReused == null) {
      for (var i = 0; i < j; i++) {
        if (active[i].changeTaken) remaining.remove(active[i].id);
      }
    } else {
      var need = consumer.changeReused!;
      for (var i = j - 1; i >= 0 && need > 0; i--) {
        final rem = remaining[active[i].id];
        if (rem == null || rem <= 0) continue;
        final cut = rem < need ? rem : need;
        remaining[active[i].id] = rem - cut;
        need -= cut;
      }
    }
  }
  remaining.removeWhere((_, v) => v <= 0);
  return remaining;
}

/// Pembayaran yang kembaliannya tampil di baris "Kembali" (status nota
/// TIDAK diperiksa di sini — lihat [lastStateChange]):
///  1. Pembayaran TERAKHIR kalau ronde itu menghasilkan kembalian
///     (changeGiven / potongan Pra-Bayar pre-checkout) — dicentang atau
///     tidak (foto struk user: centang tidak boleh menghapus Kembali).
///  2. Kalau ronde terakhir TANPA kembalian (mis. Tambah Belanjaan dibayar
///     pas), ronde lama paling akhir yang kembaliannya MASIH ada sisa
///     ([_remainingChangeByRound]) — struk tetap gross (kembaliannya cuma
///     terjadi SEKALI). Kembalian yang dipakai membayar ronde berikutnya
///     ("Pakai kembalian") habis; centang "diserahkan" TIDAK menghabiskan.
TransactionPayment? displayedChangePayment(
    Iterable<TransactionPayment> payments) {
  final latest = latestActivePayment(payments);
  if (latest == null) return null;
  if (latest.changeGiven + (latest.prabayarChangeTakenBeforeCheckout ?? 0) >
      0) {
    return latest;
  }
  final remaining = _remainingChangeByRound(payments);
  TransactionPayment? fallback;
  for (final p in payments) {
    if (p.voided || !remaining.containsKey(p.id)) continue;
    if (fallback == null || !p.paidAt.isBefore(fallback.paidAt)) fallback = p;
  }
  return fallback;
}

/// Nominal kembalian [displayedChangePayment] — ronde terakhir: changeGiven
/// + potongan pre-checkout; ronde lama (fallback): SISA-nya setelah dipakai.
/// Status nota TIDAK diperiksa (dipakai nota gabungan, dicek pemanggil).
int latestRoundChange(Iterable<TransactionPayment> payments) {
  final p = displayedChangePayment(payments);
  if (p == null) return 0;
  final latest = latestActivePayment(payments);
  if (p.id == latest?.id) {
    final v = p.changeGiven + (p.prabayarChangeTakenBeforeCheckout ?? 0);
    return v > 0 ? v : 0;
  }
  return _remainingChangeByRound(payments)[p.id] ?? 0;
}

/// Porsi "kembalian tunai" dari [displayedChangePayment] (tanpa potongan
/// Pra-Bayar pre-checkout): `changeGiven` utk ronde terakhir, SISA utk
/// ronde lama. Dipakai baris Kembalian + checkbox di Ringkasan struk.
int displayedChangeGiven(Iterable<TransactionPayment> payments) {
  final p = displayedChangePayment(payments);
  if (p == null) return 0;
  if (p.id == latestActivePayment(payments)?.id) return p.changeGiven;
  return _remainingChangeByRound(payments)[p.id] ?? 0;
}

/// Kembalian yang tampil di struk (baris "Kembali") — lihat aturan di atas.
int lastStateChange(Transaction tx, List<TransactionPayment> payments) =>
    _isUnpaidStatus(tx.status) ? 0 : latestRoundChange(payments);

/// Porsi [lastStateChange] yang BELUM dicentang "sudah diserahkan"
/// (potongan Pra-Bayar pre-checkout selalu sudah diambil).
int _lastStateUnclaimed(Transaction tx, List<TransactionPayment> payments) {
  if (_isUnpaidStatus(tx.status)) return 0;
  final shown = displayedChangePayment(payments);
  if (shown == null || shown.changeTaken) return 0;
  final own = shown.id == latestActivePayment(payments)?.id
      ? shown.changeGiven
      : (_remainingChangeByRound(payments)[shown.id] ?? 0);
  return own > 0 ? own : 0;
}

/// Jumlah kembalian yang BELUM diserahkan (tak dicentang) dan belum dipakai
/// membayar ronde berikutnya: Σ changeGiven ronde tak-dicentang dikurangi
/// Σ `changeReused` (null/data lama dianggap 0 — kembalian lama yang
/// dicentang sudah tak ikut hitungan). Angka yang sama di semua device
/// setelah sinkron (centang OR-merge, `changeReused` ikut baris).
int unclaimedChangeTotal(List<TransactionPayment> payments) {
  final active = payments.where((p) => !p.voided);
  final unhanded = active
      .where((p) => !p.changeTaken && p.changeGiven > 0)
      .fold<int>(0, (s, p) => s + p.changeGiven);
  final reused = active.fold<int>(0, (s, p) => s + (p.changeReused ?? 0));
  final v = unhanded - reused;
  return v > 0 ? v : 0;
}

/// True kalau ada kembalian belum diambil yang TIDAK terwakili baris
/// "Kembali" last-state (kembalian ronde lama yang menumpuk, atau nota
/// masih kurang tapi ada kembalian lama yang belum diserahkan) — syarat
/// tampilnya tombol "Gabungkan kembalian belum diambil". Tombol hilang
/// begitu semua kembalian dicentang/dipakai.
bool hasExtraUnclaimedChange(
        Transaction tx, List<TransactionPayment> payments) =>
    unclaimedChangeTotal(payments) > _lastStateUnclaimed(tx, payments);

/// Nominal kembalian yang boleh ditawarkan "Pakai kembalian" di layar Bayar
/// (Tambah Belanjaan) — sama dgn [unclaimedChangeTotal] (semua ronde, bukan
/// cuma pembayaran terakhir).
int reusableChangeTotal(List<TransactionPayment> payments) =>
    unclaimedChangeTotal(payments);
