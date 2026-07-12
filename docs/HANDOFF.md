# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 12 Juli 2026 (sesi Item 24/25 — kalkulator Uang Pas,
katalog HTML font/light mode, swipe-delete produk, tanda Stok Habis,
tap-to-scan + redesign scanner kapsul melayang; + diskusi panjang & desain
lengkap sistem lisensi offline yang SENGAJA belum dieksekusi)._

**schemaVersion sekarang 14** (naik dari 13 — Item 25a menambah kolom
`products.marked_out_of_stock`). Full `flutter test`: **241 test hijau**,
`flutter analyze` bersih.

## Status Item 24 & 25 (PLAN.md)

- **24a** (chip "Uang Pas" di modal Tambah Bayar/Lunasi) — SELESAI, `37ca76e`.
- **24c** (katalog HTML: font Hanken Grotesk/Newsreader disamakan POS,
  default mode TERANG bukan ikut dark-mode HP pelanggan) — SELESAI, `6285481`.
- **24e** (tap-to-scan, opsi tambahan default OFF) + **24f** (redesign
  kontrol scanner jadi kapsul-kapsul melayang in-frame gaya kamera bawaan
  HP, bukan AppBar+menu titik-tiga) — SELESAI, `5a18301`.
- **25a** (tanda cepat "Stok Habis" dari modal item kasir — kolom
  `markedOutOfStock`, kosmetik saja/tidak menonaktifkan tombol tambah di
  kasir, TAPI benar-benar menonaktifkan tombol tambah di katalog HTML
  statis) — SELESAI, inti `d9e1f2e` + badge kosmetik kartu kasir `5a18301`.
- **25b** (hapus produk via swipe di tab Produk, pola sama seperti tab
  Pelanggan) — SELESAI, `29d7400`.
- **MENGGANTUNG: 24b+24d** (payment gate role Pegawai — rename KOSMETIK
  "Kasir"→"Pegawai" di UI, `deviceRole` internal TETAP `'kasir'`; permission
  baru `terima_pembayaran` default OFF; tombol "Bayar" pegawai tanpa izin
  jadi "Kirim ke Owner/Asisten" via `held_orders` bertanda khusus; checklist
  centang struk ikut tersinkron sebagai bagian payload; notifikasi realtime
  LAN ke pegawai saat owner selesai bayar, nyambung ke Item 21 sync UI
  persisten yang juga masih menggantung). Detail lengkap masih di PLAN.md.
- **25c (lisensi/aktivasi offline) — desain SUDAH FINAL & komprehensif,
  TAPI SENGAJA BELUM dieksekusi** atas instruksi eksplisit user ("eksekusi
  semua... kecuali aspek security"). Dokumentasi lengkap dikirim sebagai
  file terpisah (`keamanan-lisensi-offline.md`, TIDAK di-commit ke repo).
  Ringkasan arsitektur (3 tingkat independen: ratchet offline + re-lock
  via versi APK baru + remote-revoke JSON opsional) ada di PLAN.md Item
  25c kalau dokumentasi lengkapnya hilang. **Jangan eksekusi tanpa
  instruksi baru dari user.**

## Gotcha teknis baru sesi ini

**Test widget scanner kamera (`mobile_scanner`) BISA di-test asli, bukan
cuma dilewati.** Paket ini federated (`MobileScannerPlatform.instance`
settable) — di test env, `MobileScannerController.start()` gagal diam-diam
tanpa exception fatal (widget tetap render `ColoredBox` placeholder), TAPI
untuk menembakkan barcode palsu & menguji logika `onDetect`, buat
`FakeMobileScannerPlatform extends MobileScannerPlatform` dengan
`StreamController<BarcodeCapture?>` sendiri untuk `barcodesStream`, pasang
via `MobileScannerPlatform.instance = fake` di `setUp()`/kembalikan di
`tearDown()`. `MobileScannerViewAttributes`/`StartOptions` TIDAK
di-export lewat `package:mobile_scanner/mobile_scanner.dart` — import
langsung dari `package:mobile_scanner/src/mobile_scanner_view_attributes.dart`
& `.../src/objects/start_options.dart`. Lihat `test/kasir_tap_to_scan_test.dart`.
**Icon findByIcon ambigu**: kalau 2 widget berbeda kebetulan pakai
`IconData` yang sama di state tertentu (mis. tombol bidik manual & toggle
"Tap to Scan" sama-sama `Icons.center_focus_strong` saat aktif), jangan
andalkan `find.byIcon` — kasih `Key` eksplisit ke widget yang perlu
ditarget test (lihat `Key('scan_shutter_button')` di `_ScanShutterButton`).
Widget yang secara visual "tersembunyi" via `AnimatedOpacity`/`AnimatedScale`
tetap ADA di element tree (cuma diskalakan/opacity 0) — `find.byIcon`
tetap menemukannya walau tidak kelihatan, JANGAN pakai `findsNothing` untuk
membuktikan "tidak tampil"; buktikan lewat fungsi (tap via key +
`warnIfMissed:false` lalu assert TIDAK ada efek) karena `IgnorePointer`
yang benar-benar memblokir interaksi, bukan visibilitas piksel.

**Migrasi schemaVersion baru butuh audit SEMUA fixture test migrasi lama.**
Naikkan `schemaVersion` (13→14, Item 25a) berarti fixture raw-SQL di
`migration_v7/v9/v10/v13_test.dart` (yang mensimulasikan DB versi lama lalu
buka via `AppDatabase` untuk memicu SEMUA `onUpgrade` step berurutan sampai
versi terkini) butuh tabel MINIMAL untuk setiap migrasi BARU yang dilewati
di tengah jalan — bukan cuma tabel yang relevan dengan migrasi yang sedang
diuji fixture itu. Utk 25a: keempat fixture itu ditambah
`CREATE TABLE products(id TEXT PRIMARY KEY);` (kolom `marked_out_of_stock`
ditambah via `addColumn`, butuh tabel induknya sudah ada) + assert versi
akhir diupdate 13→14 di kelimanya. Gejala kalau lupa: `SqliteException(1):
no such table: products` yang KETUTUP oleh `\r` progress-overwrite di
capture `flutter test` biasa — redirect langsung ke file
(`flutter test ... > file.txt 2>&1`) lalu `tr '\r' '\n'` sebelum grep kalau
curiga ada exception yang tidak kelihatan di output biasa.

## Lingkungan sesi ini
Flutter TIDAK terpasang default — dipasang manual ke `/tmp/flutter`
(versi 3.24.5 stable, samakan CI `build-apk.yml`). `/opt/flutter` yang
disebut CLAUDE.md TIDAK ADA di environment ini — selalu `which flutter`
dulu kalau command CLAUDE.md gagal. Jalankan sebagai non-root
menghasilkan warning "Woah!... trying to run as root" yang TIDAK
menggagalkan perintah (aman diabaikan).

## Menggantung / Kandidat Berikutnya
- **Item 24b+24d** (payment gate role Pegawai) — item terbesar yang belum
  dikerjakan, lihat ringkasan di atas + detail penuh PLAN.md.
- **Item 21+17** (sync UI persisten lintas tab + persist antrian approval)
  — masih sengaja ditunda dari sesi-sesi sebelumnya, nyambung erat ke 24d
  (notifikasi realtime butuh infrastruktur sync/global state yang sama).
- **Item 23** (scope bug "Sisa Tagihan" understated di lokasi lain: Buku
  Hutang, Tutup Kasir, dll) — lihat PLAN.md untuk daftar lengkap lokasi
  yang sengaja belum disentuh.
- **Item 3c/4/5/8** (import data toko lama dari dataset Griyo POS) — lihat
  PLAN.md, menunggu keputusan/data lanjutan dari user.
- **25c (lisensi)** — desain final, tunggu instruksi eksplisit user untuk
  mulai eksekusi.

## Preferensi User (masih berlaku)
- Bahasa komunikasi & teks UI: Indonesia.
- Untuk fitur bervisual: usulkan opsi desain dulu sebelum implementasi.
- Untuk bug: laporkan dulu contoh kasus + severity, baru eksekusi.
- Untuk fitur baru berisiko/besar: diskusikan cakupan dulu, eksekusi
  setelah instruksi eksplisit ("eksekusi semua"/konfirmasi serupa).
- Rencana yang didiskusikan tapi belum dieksekusi → masuk PLAN.md
  komprehensif, jangan cuma tersimpan di riwayat chat.
- Perubahan sensitif/berisiko (mis. aspek security) — tunda eksekusi
  sampai instruksi eksplisit terpisah, walau desainnya sudah disetujui
  penuh (lihat 25c).
