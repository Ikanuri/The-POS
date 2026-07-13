# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 13 Juli 2026 (lanjutan sesi Item 24/25/26 — payment
gate role Pegawai [sebagian], catatan per-produk katalog HTML, tata letak
kalkulator bayar)._

**schemaVersion tetap 14** (tidak ada migrasi baru sesi ini — Item 26
murni UI + extend format teks JSON/blob yang sudah ada, tanpa skema DB
baru). Full `flutter test`: **248 test hijau**, `flutter analyze` bersih.

## Status Item 24 (payment gate role Pegawai) — SEBAGIAN, lihat PLAN.md

- **SUDAH SELESAI & di-commit** (`4317c33`): rename KOSMETIK "Kasir"→
  "Pegawai" di semua layar UI (`deviceRole` internal TETAP `'kasir'`,
  TIDAK disentuh — lihat catatan audit di PLAN.md kalau lupa kenapa) +
  permission baru `terima_pembayaran` (default OFF, self-heal via
  `beforeOpen`, TANPA migrasi schema — pola sama seperti izin lain).
- **Mekanisme "kirim ke Owner/Asisten" — SUDAH DIPUTUSKAN desainnya**
  (bukan lagi opsi terbuka), TAPI **belum diimplementasi sama sekali**:
  QR code (bukan servis jaringan — opsi itu dibandingkan lalu ditolak),
  scan-nya **gabung ke scanner kasir yang sudah ada** (bukan scanner
  terpisah — otomatis dapat dukungan scanner eksternal HID gratis, sudah
  dikonfirmasi user scanner tokonya support QR), hasil scan **masuk
  antrian** `held_orders` bertanda `awaitingPayment` (BUKAN langsung ke
  keranjang aktif owner — supaya tidak bentrok kalau owner sedang
  melayani transaksi lain). Detail lengkap arsitektur & alur ada di
  PLAN.md Item 24 (24d) — baca itu dulu sebelum mulai implementasi,
  jangan re-diskusikan dari nol.
- **Sengaja TANPA notifikasi otomatis arah balik** (owner→pegawai
  "transaksi lunas") di versi ini — keputusan sadar, bukan lupa.
- **Checklist struk tersinkron (24b)** — belum dikerjakan, nyambung ke
  payload `held_orders` yang sama.

## Item 26 — 3 penyempurnaan kecil, SELESAI (`7fa7907`)

- **26a**: catatan per-produk di katalog HTML "Tempel Pesanan" — reuse
  penuh `CartItem.itemNote`/kolom `item_note` yang sudah ada end-to-end
  (tanpa field/kolom baru). Format kode mesin `#PSN:` diperluas dengan
  segmen opsional `:catatan` (encodeURIComponent di JS, `Uri.decodeComponent`
  di parser) — backward-compatible dengan baris lama tanpa catatan.
- **26b**: tombol "Uang Pas" pindah dari `Wrap` chip pecahan uang ke
  sebaris dengan "Bayar" di baris paling bawah kalkulator (`payment_screen.dart`
  `_CashKeypadSheet`).
- **26c**: tombol "00" ditukar posisi dengan "000" di `_Keypad._rows`
  supaya "00" berjajar dengan "0" (bukan lagi dengan 7/8/9) — TANPA
  tombol yang hilang, `_press()` generic per-string jadi aman ditukar.

## Gotcha teknis baru sesi ini

**`ButtonStyle.minimumSize: Size.fromHeight(h)` = `Size(double.infinity, h)`
— TIDAK aman ditaruh di dalam `Row` tanpa `Expanded`.** Dipakai berkali-kali
di app ini untuk tombol FULL-WIDTH (mis. tombol "Bayar" berdiri sendiri di
`Column`) — tapi begitu widget yang sama ditaruh sebagai SIBLING lain di
`Row` (Item 26b: "Uang Pas" di sebelah "Bayar"), constraint lebar infinity
itu nabrak `BoxConstraints` Row yang cuma kasih lebar terbatas ke child
non-`Expanded` → `BoxConstraints forces an infinite width` (assertion
error, ketahuan dari widget test, bukan cuma visual). **Parah lagi:**
`AppTheme`-nya sendiri set `outlinedButtonTheme` global dengan
`minimumSize: Size(double.infinity, 48)` — jadi walau instance style TIDAK
eksplisit set `Size.fromHeight`, `OutlinedButton` POLOS pun kena infinity
dari tema. Fix: override eksplisit `minimumSize: Size(0, h)` di style
instance kalau tombol itu perlu SEMPIT (bukan full-width) di dalam `Row`.

**Screenshot visual katalog HTML via Playwright — pola kerja yang
terbukti jalan:** `OrderPageService.generateHtml()` butuh binding Flutter
(depends on `dart:ui` transitively lewat `path_provider`), jadi TIDAK bisa
dijalankan lewat `dart run` polos — harus lewat `flutter test` (test
sekali-pakai yang nulis `result.html` ke file, lalu dihapus lagi). Baru
file HTML itu dibuka via `file://...` di Chromium (`/opt/pw-browsers/chromium`,
`NODE_PATH=/opt/node22/lib/node_modules`) — bisa klik tombol `+`
(`button[data-act="inc"]`), isi `.ci-note`, dan panggil fungsi JS `buildOrderText()`
langsung lewat `page.evaluate()` untuk lihat teks pesanan jadi (termasuk
kode mesin `#PSN:`) tanpa perlu simulasikan klik "Salin"/clipboard.

**Migrasi schemaVersion baru butuh audit SEMUA fixture test migrasi
lama** (dari sesi sebelumnya, masih berlaku) — lihat CLAUDE.md §Gotcha
kalau lupa detailnya.

## Lingkungan sesi ini
Flutter TIDAK terpasang default — dipasang manual ke `/tmp/flutter`
(versi 3.24.5 stable, samakan CI `build-apk.yml`). `/opt/flutter` yang
disebut CLAUDE.md TIDAK ADA di environment ini — selalu `which flutter`
dulu kalau command CLAUDE.md gagal. Jalankan sebagai non-root
menghasilkan warning "Woah!... trying to run as root" yang TIDAK
menggagalkan perintah (aman diabaikan).

## Menggantung / Kandidat Berikutnya
- **Item 24 sisa** (gate tombol "Bayar" jadi QR + antrian `held_orders` +
  checklist tersinkron) — desain SUDAH FINAL, tinggal implementasi. Item
  terbesar yang belum dikerjakan, baca PLAN.md Item 24 (24b/24d) dulu.
- **Item 21+17** (sync UI persisten lintas tab + persist antrian approval)
  — masih sengaja ditunda dari sesi-sesi sebelumnya. CATATAN: TIDAK lagi
  prasyarat keras untuk 24d (mekanisme QR yang dipilih tidak bergantung
  pada infrastruktur sync/LAN sama sekali).
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
- Untuk perubahan kecil yang jelas (tidak ambigu) — user eksplisit minta
  langsung eksekusi + merge ke main tanpa menunggu konfirmasi tambahan
  (lihat pola Item 26), TAPI kalau ada keputusan desain yang genuinely
  ambigu (banyak interpretasi valid), tetap ajukan dulu sebelum eksekusi.
