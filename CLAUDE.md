# CLAUDE.md

Panduan proyek untuk Claude Code. Dibaca otomatis di setiap sesi — **jaga tetap
ringkas** (hemat token). Riwayat kronologis ada di file lain (lihat §Dokumentasi
Wajib), jangan ditumpuk di sini.

## Ringkasan Proyek

**The POS** — aplikasi kasir _offline-first_ (Flutter) untuk toko grosir & retail
di Indonesia. Data lokal terenkripsi (SQLCipher), mendukung multi-perangkat dalam
satu toko (owner + kasir) via sinkronisasi LAN/WiFi & QR, terintegrasi printer
thermal Bluetooth dan barcode scanner. Tanpa backend cloud.

## Stack & Dependency Kunci

- **Flutter/Dart**, Material 3.
- **State:** Riverpod v2.5 — banyak dipakai `StateNotifierProvider.family`.
- **Routing:** GoRouter v14 — `ShellRoute` untuk shell bottom-nav utama.
- **DB:** Drift ORM + SQLCipher (`sqlcipher_flutter_libs`). Schema saat ini
  `schemaVersion = 9` di `lib/core/database/app_database.dart`.
- **Ekspor:** `pdf` + `excel`, dikirim lewat `file_picker` (`saveFile`).
- **Chart:** `fl_chart`. **Scanner:** `mobile_scanner` (kamera) + HID keyboard
  (scanner eksternal). **Printer:** `print_bluetooth_thermal` + native Kotlin RFCOMM.

## Struktur

```
lib/
  core/       database (+tables/), models, providers, router, services,
              theme, utils, widgets
  features/   kasir (+widgets/), laporan (+tabs/), pelanggan, pengaturan,
              produk (+catalog/), ringkasan, setup, shell
```

## Pola Arsitektur (ikuti — jangan dilanggar)

- **Cart provider = family keyed `String cartId`.** Jangan buat provider keranjang
  global baru. Key yang dipakai: `kMainCartId` ('main'), `kCatalogCartId`
  ('catalog', mode katalog — terpisah dari kasir), atau `txId` (mode tambah
  belanjaan). Meta keranjang (pelanggan/pegawai) juga family per `cartId`.
- **Widget → gambar:** `RepaintBoundary.toImage()`. Untuk widget yang belum
  di layar (chart ekspor), render off-screen via `Overlay.insert` di posisi
  `left: -99999`, tunggu `endOfFrame` + delay, lalu capture. Chart untuk capture
  harus `swapAnimationDuration: Duration.zero`.
- **Ekspor file:** pakai `FilePicker.saveFile`, **bukan** `Printing.sharePdf`
  (merasterisasi semua halaman → OOM di rentang besar & gagal-diam di rentang
  kecil). Batasi baris query ekspor (mis. transaksi PDF 2000 / XLSX 10000).
- **Query DB:** agregat/JOIN, hindari N+1 (mis. `getReportTotals`,
  `getTopProductsByRevenue`, `getCategoryNamesForProducts`).
- **Katalog tersimpan** disimpan sebagai blob JSON di tabel settings
  (key `saved_catalogs`) — tanpa migrasi DB.

## Konvensi Kode

- **Teks UI & komentar → Bahasa Indonesia.** Nama class/variabel/fungsi → Inggris.
- Ikuti gaya file sekitarnya (kepadatan komentar, penamaan, idiom).
- Warna semantik & tema di `lib/core/theme/app_theme.dart` — accent terracotta
  `#C96442`, font Hanken Grotesk (UI) + Newsreader (angka/nominal, via
  `AppTheme.numStyle`).

## Gotcha (sudah pernah kejadian — jangan terulang)

- **HID scanner menelan input keyboard:** `useRootNavigator: true` bikin handler
  HID menelan semua event → field tak bisa diketik. Cek
  `ModalRoute.of(context)?.isCurrent` + flag sheet yang kita buka sendiri.
- **`TextDirection` bentrok** antara package `material` dan `pdf`. Di builder
  overlay ekspor pakai `ui.TextDirection.ltr` eksplisit.
- **Teks putih tak terbaca di PDF:** `onPrimary`/`onSecondary`/`onTertiary` ikut
  warna tema app (bisa dark-mode = putih). Untuk capture chart PDF, bungkus
  `Material` **di dalam** `Theme(data: AppTheme.light())` agar ink light dipakai.
- **Font PDF default** tidak mendukung en-dash `–` / non-ASCII. Pakai ASCII
  (`-`, `s/d`). Printer ESC/POS juga: sanitasi ke ASCII.
- **Field harga IME desync** akibat pemisah ribuan — hati-hati saat mengubah
  formatting input angka.

## Perintah

- Analisa: `/opt/flutter/bin/flutter analyze` (binary di `/opt/flutter/bin`;
  jalankan tanpa root bila memungkinkan — peringatan root tidak menggagalkan).
- Wajib `flutter analyze` bersih (0 issue) sebelum commit.
- Build APK via GitHub Actions (`.github/`), single arm64-v8a.

## Metode Test Sebelum Rilis — WAJIB dipakai untuk fitur/fix baru

Jenjang test dari yang paling murah/cepat ke paling mahal — pilih level
sesuai apa yang disentuh, jangan lompat ke widget test kalau cukup test DB:

1. **Logic/DB murni** → test langsung terhadap `AppDatabase(NativeDatabase.memory())`
   sungguhan (bukan mock/reimplementasi ulang logika di test). Test integrasi
   Drift nyata bisa membuktikan hal yang tak bisa dibuktikan cara lain, mis.
   migrasi schema (buat DB versi lama via raw sqlite3, buka via `AppDatabase`
   untuk memicu `onUpgrade` sungguhan) atau `EXPLAIN QUERY PLAN` untuk indeks.

2. **UI/widget** → pakai harness `test/helpers/pump_app.dart`
   (`pumpWithFakeApp(tester, db:, child:, device:)`) yang override
   `databaseProvider`/`deviceProvider` dengan versi palsu — merender screen
   sungguhan tanpa device/SQLCipher asli. Harness ini sudah beberapa kali
   menemukan bug NYATA yang tak mungkin ketahuan dari test DB saja (overflow
   layout, provider yang tidak refresh). `surfaceSize` harus generus (default
   430×2400) karena `ListView(children:)` lazy-build di luar viewport.

3. **Networking asli (LAN sync)** → jangan mock protokolnya. `flutter_test`
   mem-fake SEMUA `HttpClient` jadi selalu balas 400 — override balik pakai
   `HttpOverrides.runZoned` (perlu escape ganda: `Zone.root.run` + nonaktifkan
   `HttpOverrides.global` sementara, kalau tidak akan stack-overflow karena
   `createHttpClient` memanggil dirinya sendiri). Sambungkan host+klien
   sungguhan lewat `127.0.0.1`, bukan simulasi payload manual.

4. **WAJIB untuk setiap test regresi/bugfix**: sebelum dianggap selesai,
   **revert sementara** fix-nya ke kode lama, jalankan test barunya, dan
   **buktikan test itu GAGAL** dengan pesan yang masuk akal (bukan error lain
   yang tak relevan) — baru kembalikan fix-nya dan pastikan hijau lagi. Tanpa
   langkah ini, test yang "lolos" bisa saja lolos karena kebetulan (assert
   salah, query tidak benar-benar dites, dll), bukan karena benar-benar
   mendeteksi bug-nya.

5. Setelah semua test baru hijau: jalankan **seluruh** `flutter test` (bukan
   cuma file baru) untuk pastikan tidak ada regresi di tempat lain, plus
   `flutter analyze` bersih — baru commit.

## Perencanaan — [PLAN.md](PLAN.md)

- **Setiap ada rencana kerja** (fitur/fix yang didiskusikan tapi belum
  dieksekusi — termasuk hasil sesi analisis/diskusi "jangan coding dulu"),
  **masukkan ke `PLAN.md`** di root, komprehensif (detail teknis: file,
  akar masalah, bukti; maupun non-teknis: prioritas, ketergantungan,
  pertanyaan desain yang menggantung).
- **Setiap satu item di `PLAN.md` selesai dieksekusi** (sudah dikerjakan &
  di-commit), **hapus item itu dari `PLAN.md`** — jangan dibiarkan
  menumpuk. `PLAN.md` isinya HANYA rencana yang masih menggantung, bukan
  log riwayat (riwayat teknis ada di [CHANGELOG.md](CHANGELOG.md)).

## Git

- Branch fitur khusus ditentukan per-task; jangan push ke branch lain tanpa izin.
- Jangan buat PR kecuali diminta eksplisit.
- **Jangan** cantumkan model identifier di commit message / artefak repo.

## Dokumentasi Wajib — perbarui SETIAP menyelesaikan pekerjaan

Tiga file di bawah harus dijaga tetap sinkron. Perbarui **sebelum commit terakhir**
sebuah sesi/tugas:

1. **[CHANGELOG.md](CHANGELOG.md)** — teknis, **persis 1:1 dengan commit**. Setiap
   commit baru → satu baris `` `hash` — subjek `` di bawah tanggalnya (terbaru di
   atas). Boleh diregenerasi dari `git log` bila perlu.

2. **[PATCHNOTES.md](PATCHNOTES.md)** — ramah pengguna awam (Bahasa Indonesia),
   **hanya perubahan yang dirasakan pengguna**. Kriteria:
   - **Sertakan** fitur baru & perubahan yang terlihat pengguna.
   - **Sertakan** bugfix **hanya bila pengguna pernah merasakan** masalahnya (mis.
     ekspor gagal, teks tak terbaca).
   - **Jangan sertakan** perbaikan internal/teknis yang tak kasat mata (refactor,
     optimasi query, bug yang diperbaiki sebelum sempat dirilis).
   - Dikelompokkan per rilis/tanggal, bahasa sederhana, fokus manfaat.

3. **[docs/HANDOFF.md](docs/HANDOFF.md)** — "context card" untuk kesinambungan
   antar-sesi. Ini **snapshot bergulir**, bukan log: **timpa/rewrite** isinya agar
   selalu mencerminkan keadaan TERKINI (keputusan penting yang masih berlaku,
   pekerjaan yang menggantung, preferензi user, item yang menunggu). Tujuannya
   hemat token — histori panjang biar di CHANGELOG, di sini cukup "di mana kita
   sekarang & apa berikutnya". Update setiap akhir sesi.
