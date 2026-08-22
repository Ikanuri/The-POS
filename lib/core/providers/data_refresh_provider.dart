import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ticker yang di-bump SETIAP KALI ada perubahan data hasil SYNC (baik
/// klien menerima kiriman dari host, maupun host menerima approve dari
/// klien) — lihat pemanggilnya di `SyncStateNotifier` (`sync_state_
/// provider.dart`).
///
/// Kenapa provider ini perlu ada: sebagian besar layar Ringkasan/Laporan
/// (mis. `_ringkasanProvider` di `ringkasan_screen.dart`, hampir semua tab
/// di `laporan/tabs/`) memakai `FutureProvider` biasa (BUKAN
/// `StreamProvider`/`.watch()` ke tabel DB) — dipilih krn query-nya agregat
/// berat (rentang tanggal, JOIN multi-tabel) yang mahal kalau dijalankan
/// ulang tiap kali ADA PERUBAHAN SEKECIL APA PUN di tabel transaksi
/// (`StreamProvider` biasa akan re-run di SETIAP insert/update, bukan cuma
/// saat user benar-benar butuh angka terbaru).
///
/// Konsekuensinya: provider itu HANYA re-fetch saat pertama kali dibuka,
/// user tekan tombol refresh, atau parameter (rentang tanggal) berubah —
/// TIDAK PERNAH otomatis begitu ada transaksi BARU masuk lewat sync LAN.
/// Bug nyata dilaporkan user: total pendapatan hari ini di Ringkasan klien
/// tidak bertambah setelah klien sync dari host (padahal data transaksi di
/// DB lokal klien sudah benar — bisa dibuktikan dgn tekan tombol refresh
/// manual, angkanya langsung benar).
///
/// Fix: provider2 itu WAJIB `ref.watch(dataSyncedTickProvider)` di baris
/// PALING ATAS (sebelum query apa pun) — Riverpod akan menganggap provider
/// itu "dirty" & re-fetch begitu tick ini berubah, TANPA perlu mengubah
/// query-nya jadi live-stream yang mahal.
final dataSyncedTickProvider = StateProvider<int>((ref) => 0);
