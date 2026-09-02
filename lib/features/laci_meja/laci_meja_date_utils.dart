/// Selisih HARI KALENDER (bukan `Duration.inDays` mentah) — dipakai SEMUA
/// tempat "N hari lalu" fitur Laci Meja (dashboard, riwayat, laporan
/// pre-order) supaya cuma ada SATU logic yang bisa dites & diperbaiki,
/// bukan disalin-tempel di tiap file (sudah pernah kejadian pola begini di
/// app lain, lihat gotcha CLAUDE.md soal cache kedua yang bisa menyimpang).
///
/// BUG YANG SUDAH DIPERBAIKI: versi lama tiap file pakai
/// `DateTime.now().difference(createdAt).inDays` — literal selisih 24 jam,
/// jadi entri yang dibuat KEMARIN jam 23:50 & dilihat HARI INI jam 00:10
/// (baru lewat ~20 menit, tapi sudah GANTI TANGGAL KALENDER) salah tampil
/// "0 hari lalu" padahal seharusnya "1 hari lalu" begitu lewat tengah
/// malam. Fix: buang jam/menit/detik dari KEDUA sisi (normalisasi ke
/// tengah malam) SEBELUM diselisihkan — begitu tanggal beda 1, langsung
/// terhitung 1 hari, tidak peduli jam pastinya.
///
/// [now] opsional utk testability (default `DateTime.now()`).
int calendarDaysSince(DateTime from, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final fromDate = DateTime(from.year, from.month, from.day);
  final nowDate = DateTime(n.year, n.month, n.day);
  return nowDate.difference(fromDate).inDays;
}
