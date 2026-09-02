import 'package:flutter_test/flutter_test.dart';
import 'package:the_pos/features/laci_meja/laci_meja_date_utils.dart';

/// Susulan permintaan user (di luar tugas awal, tapi menyentuh logic yang
/// sama persis) — SEMUA perhitungan "N hari lalu" di fitur Laci Meja
/// (dashboard, riwayat, laporan pre-order) disatukan jadi SATU helper
/// `calendarDaysSince` (lihat `laci_meja_date_utils.dart`), supaya tidak ada
/// 3-4 salinan logic yang bisa menyimpang satu sama lain ke depannya.
///
/// BUG YANG DIPERBAIKI: versi lama tiap file pakai
/// `DateTime.now().difference(createdAt).inDays` — selisih LITERAL 24 jam.
/// Kasus nyata: entri dibuat KEMARIN jam 23:50, dilihat HARI INI jam 00:10
/// (baru lewat ~20 menit, TAPI sudah lewat tengah malam / ganti tanggal
/// kalender) — versi lama salah bilang "0 hari lalu", padahal seharusnya
/// "1 hari lalu".
void main() {
  test(
      'lewat tengah malam (kemarin 23:50 -> hari ini 00:10) dihitung 1 hari '
      'lalu, BUKAN 0 (walau durasi mentah cuma ~20 menit)', () {
    // Waktu eksplisit (BUKAN `subtract(Duration(hours: 1))` yang bisa
    // false-negative tergantung jam eksekusi test) supaya kasusnya PASTI
    // lewat tengah malam apa pun jam CI menjalankannya.
    final createdAt = DateTime(2026, 9, 1, 23, 50);
    final now = DateTime(2026, 9, 2, 0, 10);

    final days = calendarDaysSince(createdAt, now: now);

    expect(days, 1,
        reason: 'sudah ganti tanggal kalender (1 -> 2 September) walau '
            'durasi mentahnya cuma ~20 menit, jadi harus terhitung 1 hari '
            'lalu, bukan 0');
  });

  test('kasus normal: selisih 5 hari kalender penuh', () {
    final createdAt = DateTime(2026, 8, 28, 9, 12);
    final now = DateTime(2026, 9, 2, 14, 35);
    expect(calendarDaysSince(createdAt, now: now), 5);
  });

  test('waktu yang sama persis (baru dibuat) -> 0 hari lalu', () {
    final t = DateTime(2026, 9, 2, 10, 0);
    expect(calendarDaysSince(t, now: t), 0);
  });

  test('now default ke DateTime.now() kalau tidak diberikan', () {
    final createdAt = DateTime.now().subtract(const Duration(days: 2));
    expect(calendarDaysSince(createdAt), 2);
  });
}
