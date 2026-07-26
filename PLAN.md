# PLAN.md

Daftar rencana kerja yang sudah didiskusikan tapi **belum dieksekusi**. Ini
BUKAN log — begitu satu item selesai dikerjakan & di-commit, **hapus item itu**
dari file ini (lihat aturan di [CLAUDE.md](CLAUDE.md) §Perencanaan). Riwayat
teknis pekerjaan yang SUDAH selesai ada di [CHANGELOG.md](CHANGELOG.md), bukan
di sini.

_Terakhir diperbarui: 13 Juli 2026. Item 9-22 SELESAI 12/13 (Item 17+21
sengaja ditunda). Item 3a/3b SELESAI/terjawab lewat fitur baru "Import dari
Griyo POS". Item 4 (import pelanggan Griyo) analisis+keputusan besar
selesai, siap diimplementasi. **Item 23** (bug "Sisa Tagihan" understated
saat kembalian dipakai ulang — scope Buku Hutang/Tutup Kasir/tempat lain
masih menggantung). **Item 24 SELESAI SEPENUHNYA & di-commit** (24a/24b/
24c/24d/24e/24f): payment gate role Pegawai lewat QR + antrian
`held_orders` + sheet "Verifikasi Pesanan" (owner centang sambil pegawai
bacakan barang, 1 device saja tanpa sync) — sengaja TANPA notifikasi
otomatis arah balik (keputusan final). **Item 25**: 25a/25b SELESAI &
di-commit. **Item 26** (3 penyempurnaan kecil: catatan per-produk di
katalog HTML, posisi tombol Uang Pas & keypad "00"/"0" di kalkulator
bayar) — SELESAI & di-commit. **25c (gerbang lisensi offline) SELESAI,
di-commit, DAN SEKARANG AKTIF** — public key developer sudah ditanam
(`0d1efe2`, 14 Juli), plus sakelar darurat `lockAll` di Lapis 3 & durasi
kustom menit di generator (`3591396`). Nomor WA developer: KEPUTUSAN
FINAL tetap `Share.share()` generik, tidak perlu deep-link `wa.me`.
Sisa menggantung: Item 3c, 5, 23 (sebagian, lihat detail — nota gabungan
sudah diperbaiki sesi 13 Juli). **Redesign header struk (watermark stempel
Lunas/Tempo) SELESAI & di-commit** (16 Juli) — lihat CHANGELOG untuk hash.
**Item 27 ("Alihkan Owner") SELESAI SEPENUHNYA, diverifikasi di device
asli, & di-commit** (16 Juli, lihat CHANGELOG `99de7ea`/`1d09200`) — desain
final beda dari catatan lama (bukan QR+LAN live, tapi file terenkripsi
BPOT1 + rekey SQLCipher; entry point Pengaturan "Alihkan Owner" & welcome
screen "Pulihkan dari File"). Item 28 (lanjutkan pesanan lintas device)
masih sebatas konsep, belum didesain detail. **Item 29/30(a/b/c)/31/32/33
SELESAI SEMUA & di-commit** (17 Juli): katalog auto-habis stok riil,
kontrol stok (kartu Ringkasan + layar "Cek Stok" + tab analitik Laporan),
Tutup Buku tanggal custom, debounce scanner, warna aksen toolbar. **Item
35 (fix sinkron harga SKU non-unik + mode barcode-saja) SELESAI SEPENUHNYA
& di-commit** (17 Juli). **Item 4/5 (migrasi data) DIPENDING** — user
bilang migrasi sebenarnya cakup lebih dari transaksi+pelanggan (termasuk
produk dll., scope belum dirinci) — ditahan, tunggu user re-konfirmasi
scope lengkap & minta lanjut. **Item 36 (Stock Opname) & Item 37 (publish
katalog ke Cloudflare Pages) SELESAI SEMUA & di-commit** (17 Juli,
`5c9de7f`) — lihat CHANGELOG untuk detail teknis. **Item 41 (audit kode)
P1/P2 SELESAI & di-commit** (18 Juli, lihat CHANGELOG `d2b4c4d`), sisa
B.1/C.2/P3 masih menggantung. **Item 42/43/44/45/46 SELESAI & di-commit**
(18 Juli, batch "kerjakan 42-46"): filter periode tab Pengeluaran (42),
stepper angka qty berpindah sisi +/- (43), qty di kiri item keranjang
(44), fix 2 satuan dasar aktif sekaligus (45), banner stok menipis di
kasir pasca-checkout (46) — semua dgn test + revert-verify, lihat
CHANGELOG. **Item 47/48 BELUM dieksekusi** (user bilang "sisanya
biarkan"): Item 47 = pengeluaran tidak ikut ekspor PDF/Excel Laporan
(root cause + fix jelas); Item 48 = warna avatar produk kasir jadi
soft/pastel (root cause + fix jelas). **Item 3c/4/5 (migrasi data Griyo)
DICORET user** (18 Juli, "coret: 4, 3c, 5") — dihapus dari plan._

---

## Item 47 — Pengeluaran tidak ikut ke ekspor laporan PDF/Excel (18 Juli, BELUM dieksekusi — user setuju, siap eksekusi)

**Root cause dikonfirmasi**: `report_export.dart` (ekspor PDF/Excel tab
Ringkasan Laporan) TIDAK PERNAH memanggil `getNetProfitExpenseTotal()` —
`_fetchRingkasan()` (~baris 526-553) cuma pakai `getDailySummaries()`
(revenue/cogs/txCount/metode bayar/harian), `d.profit` di situ murni
**Laba Kotor** (revenue−cogs). Grid KPI PDF (~baris 102-107) & baris
Excel (~baris 304) cuma berisi Omzet/Transaksi/HPP/Laba Kotor — TIDAK
ADA "Pengeluaran" maupun "Laba Bersih" sama sekali. Bandingkan dgn
`ringkasan_tab.dart` (tampilan ON-SCREEN Laporan → Ringkasan) yang
SUDAH benar: baris 16 manggil `getNetProfitExpenseTotal()`, baris 94
render kartu "Pengeluaran". Jadi yang tampil di layar vs yang keluar di
file ekspor **tidak konsisten** — bukan placeholder kosong, memang belum
pernah diprogram di file exportnya sama sekali.

**Fix (disetujui, siap eksekusi)**: tambahkan pemanggilan
`db.getNetProfitExpenseTotal(range.start, range.end)` di
`_fetchRingkasan()` (`report_export.dart`), alirkan field `expenses`
(dan hitung `netProfit = profit - expenses` bila mau tambahkan "Laba
Bersih" jg, konsisten dgn on-screen yg py keduanya) lewat
`_RingkasanData`, tambahkan baris "Pengeluaran" (+ "Laba Bersih" bila
disepakati) ke grid KPI PDF (~baris 102-107) dan baris Excel (~baris
304). Test: bandingkan output `_fetchRingkasan()` vs data on-screen
`ringkasan_tab.dart` utk skenario yg sama (ada expense `daily_expense`+
`change_given`) — pastikan angka Pengeluaran identik antara keduanya.

## Item 48 — Kotak warna avatar produk di kasir dibuat soft/pastel (18 Juli, BELUM dieksekusi — user setuju, siap eksekusi)

**Konteks**: BUKAN aksen fungsional bermakna (beda dari kerjaan Item
"aksen warna Ringkasan/Laporan/Pengaturan" sebelumnya) — ini avatar-
huruf (inisial nama produk) di kartu/baris produk kasir, warnanya
dipilih dari hash huruf pertama nama produk (`_gradFor()`,
`kasir_screen.dart` ~baris 707-715, palet `_kAvatarGradients` — 6 pasang
gradient 2-warna cukup vivid/saturated), dipakai di `_ProductCard` (mode
grid, ~baris 2441+2467-2490) & `_ProductListTileState` (mode list,
~baris 2609+2636-2659) — teks huruf-nya putih di atas gradient.

**Fix (disetujui, siap eksekusi)**: ganti `_kAvatarGradients` (gradient
vivid) jadi palet solid pastel/soft — ikuti bahasa desain `AppTheme`
yang sudah ada (pasangan bg-lembut + fg-redup, theme-aware light/dark,
pola sama spt `scanFg/scanBg`, `antrianFg/antrianBg` dll di
`app_theme.dart`). Huruf avatar ikut ganti dari putih ke warna gelap
redup (fg pasangannya) — putih di atas background pastel terang akan
sulit terbaca. Perlu palet baru dgn variasi cukup (minimal sama seperti
jumlah gradient lama, 6 warna) supaya beda produk masih cukup
terbedakan visual — BUKAN cuma reuse 5 pasang fg/bg yang sudah dipakai
utk kartu Ringkasan/Laporan/Pengaturan (supaya avatar produk tidak
tertukar makna dgn aksen fungsional itu). Test: widget test verifikasi
warna avatar BUKAN dari `_kAvatarGradients` lama (atau verifikasi warna
baru match palet pastel baru) di kedua mode (grid & list).

---

## Item 23 — Sisa lokasi lain yang masih pakai `paid` mentah (double-count kembalian reuse)

**Konteks:** user laporkan "Sisa Tagihan" di struk salah hitung (understated)
saat kembalian yang sudah pernah diberikan dipakai ulang sebagai pembayaran
item tambahan — akar masalah: `paid` (Σ semua pembayaran) menghitung uang
yang sama 2× (masuk sbg pembayaran baru, tanpa pernah dikurangi saat keluar
sbg kembalian sebelumnya). **Sudah diperbaiki** (`19e679d` + susulan
`87cdaf0`, 12 Juli) untuk: status `kurang_bayar`/`lunas`
(`_reconcileTransactionTotals`, `addPaymentToTransaction`) + tampilan "Sisa
Tagihan"/"Sisa hutang" DAN "Dibayar" di `receipt_screen.dart` (Ringkasan,
prefill dialog Tambah Bayar, struk cetak/gambar untuk Sisa saja) via helper
`netRemainingOwed()`/`netPaidDisplay()`. **Pelajaran dari `87cdaf0`**: kalau
nanti perbaiki tempat lain di bawah, cek SEMUA baris nominal terkait di
layar/struk yang sama (bukan cuma "Sisa"-nya) — "Dibayar" sempat kelewat
diperbaiki sekalian padahal satu card yang sama dengan "Sisa Tagihan",
ketahuan user karena Total != Dibayar+Sisa jadi tidak nyambung.

**Scope yang SENGAJA belum disentuh** (dipilih user lewat poll — fokus dulu
ke laporan spesifik, bukan sapu bersih semua turunan `total-paid`):
- **Buku Hutang** (`getDebtBook`, `getUnpaidTxDetails` di app_database.dart)
  — angka hutang pelanggan bisa understated dengan pola bug yang SAMA
  (belum diverifikasi/diperbaiki).
- **`settleMergedDebt`** (engine pelunasan hutang gabungan Buku Hutang) —
  variabel `sisa` di dalamnya pakai `tx.total - tx.paid` mentah juga.
- **Tutup Kasir** (`getTodayCashRecap`, dipakai `tutup_kasir_screen.dart`)
  — TEMUAN LEBIH LUAS: "kas sistem" dihitung dari `SUM(paid)` mentah tanpa
  dikurangi kembalian SAMA SEKALI, bahkan di transaksi normal TANPA reuse
  kembalian — dugaan kuat "kas sistem" selalu overstated sebesar total
  kembalian harian. Ini BEDA kategori dari bug reuse (lebih fundamental,
  berpotensi bikin Tutup Kasir selalu "selisih" di toko manapun yang kasih
  kembalian) — belum dikonfirmasi user apakah ini disengaja atau bug,
  belum ada fix.
- Tempat lain yang masih pakai pola `tx.total - tx.paid` mentah: `printer_
  service.dart` (`printReceipt`/struk cetak ESC/POS tunggal — beda dari
  `_ReceiptPaper` di receipt_screen.dart yang SUDAH diperbaiki),
  `transaksi_tab.dart` (2×, tab Laporan → Transaksi), `tx_history_sheet.dart`
  (3×, riwayat transaksi di kasir).
  - **`merged_receipt_screen.dart` (nota gabungan) + `printer_service.dart`
    `_buildMergedBytes` (cetak ESC/POS nota gabungan) SUDAH diperbaiki**
    (sesi 13 Juli, laporan user "SISA Rp -31.400" di struk gabungan) —
    keduanya sekarang pakai `netRemainingOwed()`/`netPaidDisplay()` via
    `paymentsByTx`, sama seperti `receipt_screen.dart`.

**Kalau ada laporan bug lanjutan dari salah satu tempat di atas**, akar
masalahnya kemungkinan besar SAMA (pola `total-paid` mentah) — cek dulu
apakah cukup diterapkan pola `netRemainingOwed()`-style (paid dikurangi Σ
changeGiven) sebelum investigasi dari nol. **PENTING kalau nanti fix
Tutup Kasir:** jangan asal kurangi `SUM(paid)` dengan Σ changeGiven murni —
perlu pikirkan ulang apakah "kas sistem" harus juga netral terhadap
`changeTaken` (kembalian yang belum diambil vs sudah), karena itu
memengaruhi apakah uangnya SUNGGUHAN sudah keluar dari laci fisik atau
belum.

---

## Item 17 — Persist antrian approval sync + majukan watermark upload (revisi dari catatan "ACK" lama)

**Prioritas:** Sedang. **Disetujui arah oleh user** (usul: simpan state
seperti pesanan tertahan). Menggantikan catatan lama di HANDOFF yang keliru
membingkai ini sebagai "sync satu arah tanpa ACK".

**Kondisi riil (dikoreksi setelah baca ulang `lan_sync_service.dart`):** sync
SUDAH dua arah, host SUDAH punya hak review (antrian approval manual, bukan
auto-merge), arah host→klien SUDAH pakai watermark (`last_sync_download_at`).
Yang jadi akar masalah SEMPIT: `_pendingQueue` (baris ~79) adalah
`static final [...]` — **cuma di memori host**. Kalau host restart sebelum
owner approve, antrian hilang. KARENA itu arah klien→host sengaja tetap
**full-dump** selamanya (komentar eksplisit baris ~486-498) sebagai pengaman —
bukan karena bidirectionality belum ada.

**Solusi:** persist `_pendingQueue` ke tabel DB baru (pola sama seperti
`held_orders` yang selamat dari app-kill). Urutan KRITIS yang harus dijaga:
simpan ke DB **sebelum** host membalas "diterima" ke klien (di handler baris
~421-447). Begitu itu dijamin, watermark upload klien boleh dimajukan →
klien berhenti kirim-ulang seluruh riwayat tiap sync.

**Klarifikasi timeout WiFi (dari pertanyaan user):** BUKAN masalah — koneksi
HTTP klien ditutup langsung setelah host membalas `pending_approval` (baris
431-447), approval terjadi async tanpa koneksi terbuka. Jadi tidak ada
sambungan yang digantung menunggu owner.

**File:** `lib/core/services/lan_sync_service.dart`, tabel baru + migrasi
`app_database.dart` (schemaVersion naik).

---

## Item 21 — Sync UI persisten lintas tab + status progres (global state)

**Prioritas:** Sedang. **Proposal user, DISETUJUI PENUH** — status progres
(Menyambung → Mengirim → Menunggu persetujuan) dikonfirmasi user persis
gambaran yang diinginkan. Refactor menengah.

**Temuan tambahan (lebih dalam dari keluhan user):** `sync_screen.dart`
`dispose()` (baris 42-43) memanggil `LanSyncService.stopHost()` → meninggalkan
layar Sync mematikan server host TOTAL, bukan cuma UI-nya hilang. State sync
(`_syncing`, `_queue`) juga lokal ke layar.

**Solusi:** angkat state sync ke **provider global Riverpod**, lepaskan
lifecycle host dari `SyncScreen`, render **banner inline persisten di level
shell** (`main_shell.dart`) yang bertahan di tab/halaman manapun sampai proses
selesai/dibatalkan (baik sisi host maupun klien).

**Soal "tidak realtime" (antrian muncul sekaligus) — batasan protokol:**
klien kirim SEMUA tabel dalam SATU request HTTP, jadi di host memang datang
sekaligus. "Realtime per-baris" TIDAK mungkin tanpa merombak protokol.
Yang bisa & sebaiknya diperbaiki: status progres sisi KLIEN (Menyambung →
Mengirim → Menunggu persetujuan) + animasi halus saat item baru masuk antrian
host. Jangan overpromise "per baris".

**File:** provider baru (mis. `lib/core/providers/sync_state_provider.dart`),
`lib/core/services/lan_sync_service.dart`, `lib/features/shell/main_shell.dart`,
`lib/features/pengaturan/sync_screen.dart` (baca dari provider global).

---

## Catatan lintas-item — perbaikan UX permission (murah, opsional)

Dari audit flow permission (bonus request user): perubahan izin owner **tidak
instan** ke HP kasir — baru berlaku setelah sync manual berikutnya (izin
mengalir sebagai master-data owner→kasir). UX-nya membingungkan ("sudah saya
matikan kok kasir masih bisa?"). Perbaikan murah: tambah teks info
"Perubahan berlaku setelah HP kasir sync berikutnya" di `kasir_permissions_screen.dart`
& `asisten_permissions_screen.dart`.

---

## Item 28 — Pegawai lanjutkan pesanan yang sudah diproses (lunas/tempo) owner di device lain

**Konteks:** kasus nyata yang sering terjadi: pegawai input barang di HP-nya
→ scan/kirim ke owner → owner proses jadi lunas/tempo → pelanggan masih mau
tambah barang lagi. Sekarang tidak ada alur untuk pegawai "buka kembali"
pesanan yang sudah closed di device owner itu untuk ditambahi.

**Belum didesain sama sekali** — baru sebatas concern yang divalidasi,
dimasukkan ke plan dulu sesuai permintaan user ("oke yang ini masukkan plan
tersendiri dulu"), implementasi ditunda.

**Pertimbangan awal (belum keputusan final):**
- Beda dengan "Tambah Belanjaan" yang sudah ada sekarang (`_isAddMode`,
  keyed `tx.id`) — itu untuk transaksi yang MASIH di device yang sama.
  Kasus ini pesanan sudah pindah tangan device (pegawai → owner) DAN sudah
  closed (lunas/tempo), jadi butuh mekanisme "buka kembali & sinkronkan
  balik" lintas device, bukan cuma lintas state lokal.
- Kemungkinan pendekatan: perpanjangan dari alur QR handoff antrian
  (`held_orders`, Item 24) — pegawai kirim "tambahan" baru sebagai request
  terpisah yang owner approve manual (konsisten dgn keputusan "TANPA
  notifikasi otomatis" di Item 24), owner-side gabungkan ke transaksi asli
  (butuh logic gabung item + reconcile total/pembayaran kalau statusnya
  sudah lunas).
- Perlu keputusan desain: apakah transaksi asli di-void lalu dibuat ulang
  gabungan, atau item ditambahkan langsung ke transaksi asli yang sudah
  closed (implikasi ke `pointsEarned`, cetak struk ulang, dll perlu
  dipikirkan).

---

## Item 41 — Audit kode menyeluruh (18 Juli 2026) — SISA yang belum dieksekusi

Audit baca-kode penuh + verifikasi nyata (Flutter 3.24.5 pin CI: analyze
0 issue, full test hijau; SDK 3.44.6 terbaru: gagal kompilasi — lihat
D.5). **Sebagian besar temuan P1/P2 SUDAH DIEKSEKUSI & di-commit di sesi
yang sama** (rekonsiliasi stok pasca-sync, UTC watermark, satu slot
antrian/IP, hemat memori sync, HMAC respons, allowlist klien + guard
identifier, layar pemulihan kunci, BackupException konsisten, parseValue
anti-overflow, potong crash log, password ekspor min 8, prune lockout,
turunkan cache/mmap SQLCipher, rapikan izin Bluetooth legacy) — detail di
CHANGELOG 2026-07-18; test regresi: `test/lan_sync_item41_test.dart` +
`test/audit_item41_unit_test.dart`, semua dgn bukti revert-merah.
Di bawah ini HANYA yang masih menggantung.

### Sisa [P1]/[P2] — butuh keputusan/desain atau device fisik

1. **[P1] B.1 — rotasi/pencabutan storeKey.** Risiko QR pairing membawa
   storeKey master polos SUDAH didokumentasikan keras di
   `pairing_service.dart`, tapi MEKANISME mitigasi belum ada: fitur
   "rotasi kunci toko" (generate storeKey baru + rekey SQLCipher +
   re-pair semua device) dan/atau un-pair device (HP kasir hilang,
   pegawai keluar). Butuh desain UX + keputusan user — jangan dieksekusi
   sepihak. Sementara: kunci bocor = jalur "Alihkan Owner" ke identitas
   toko baru.
2. **[P2] C.2 — upload klien→host selalu full-dump sejak epoch.** Fix
   minimal (satu slot antrian per IP) sudah menutup risiko OOM, tapi
   biaya CPU/transfer tetap tumbuh seiring umur toko. Solusi struktural
   SATU PAKET dgn Item 17+21: persist antrian approval host ke DB →
   watermark upload aman dimajukan. Sesi fokus tersendiri (risiko
   data-loss, wajib test round-trip HTTP asli).
### Sisa [P3]

1. **A.8 redirect router tidak reaktif** — `ref.read` tanpa
   `refreshListenable`: perubahan state lisensi async tidak memicu
   redirect sampai navigasi berikutnya. Dokumentasikan atau pasang
   Listenable gabungan.
2. **A.9 `beforeOpen` unitTypes pakai `insertOrReplace`** padahal
   komentar bilang insertOrIgnore — bom waktu kalau kelak ada UI edit
   satuan; samakan dgn `_seedDefaults`.
3. **A.10 master data tanpa tombstone** — **SEBAGIAN SUDAH TERJAWAB (22
   Juli)**: utk PRODUK, desain soft-delete tersinkron SUDAH ADA & SUDAH
   CUKUP (tidak perlu tabel tombstone) — masalahnya murni bug implementasi
   sempit (`deactivateProduct` lupa cap ulang `updated_at`), SUDAH
   diperbaiki (lihat CHANGELOG `7f20d38`). **Belum diverifikasi**: apakah
   pola bug yang SAMA (lupa cap `updated_at` saat soft-delete) juga ada di
   `customers`/tier harga — cek dulu fungsi soft-delete pelanggan di
   `app_database.dart` sebelum investigasi dari nol kalau ada laporan
   "pelanggan yang dihapus owner masih muncul di klien".
4. **A.11 `mergeRows` menghitung "diterima N" dari return `customInsert`**
   — INSERT OR IGNORE yang ter-skip bisa tetap terhitung (kosmetik,
   menyesatkan saat debug sync).
5. **A.12 tutup buku: crash di antara copy-arsip & delete-data**
   meninggalkan state nyangkut ("Arsip tahun X sudah ada" padahal data
   belum terhapus) tanpa jalur pemulihan.
6. **B.7 `minifyEnabled=false`** — aktifkan R8 + keep rules (uji regresi
   penuh, terutama drift/sqlcipher/BT).
7. **B.8 `HttpCloudflareApi` tanpa timeout** — tambah connectionTimeout +
   `.timeout()` seperti LAN sync.
8. **C.3 `SystemChrome.setSystemUIOverlayStyle` & `ref.watch` di dalam
   `MaterialApp.builder`** — guard per perubahan brightness; pindahkan
   watch ke build.
9. **C.4 `generateUniqueLocalId` memuat semua transaksi hari itu** —
   ganti `SELECT MAX(local_id)` + fallback bila mau rapi.
10. **D.2 gotcha cleartext HTTP** — sync LAN kebetulan lolos blokir
    cleartext Android karena dart:io; catat di CLAUDE.md (migrasi ke
    package `http`/cronet akan mendadak gagal tanpa NSC exception).
11. **D.3 Java 8 tanpa core library desugaring** — potensi build gagal
    saat upgrade plugin.
12. **D.5 terkunci di Flutter 3.24.5 (pin CI)** — di 3.44.6 stable gagal
    kompilasi: 1 error `CardTheme`→`CardThemeData` (`app_theme.dart:175`)
    + 53 deprecation (`withOpacity`, `DropdownButtonFormField.value`,
    `onReorder`). Rencanakan sesi upgrade SDK khusus (fix serentak +
    full test + uji APK device fisik).
13. **E — clean code**: pecah bertahap file raksasa (`kasir_screen.dart`
    3.7k, `app_database.dart` 3.4k, `receipt_screen.dart` 2.7k);
    `LanSyncService` full-static callback tunggal (2 listener saling
    timpa); loop mati `lastQtyIdx` di `discount_allocation.dart`;
    `_change` clamp `double.maxFinite.toInt()` → `max(0, ...)`;
    duplikasi validasi hex key (`rekey` vs `_openConnection`).

---

## Status ringkas & urutan sisa pekerjaan

**Item 9-22 (backlog audit besar 10-11 Juli) — SELESAI 12/13**, lihat
CHANGELOG untuk hash tiap item. Sisa satu: **Item 17+21 (sync)** — lihat
detail lengkap di atas, sengaja ditunda ke sesi fokus (risiko data-loss di
"majukan watermark upload" butuh test round-trip HTTP asli).

**Item migrasi data Griyo (Item 3c/4/5) DICORET user** (18 Juli) — dihapus
dari plan. Kalau nanti user mau lanjut migrasi data lama, mulai analisis
dari nol (riwayat teknis lama sudah dibuang dari plan ini).

**Item 50 (opsional, DEFERRED — jangan dikerjakan kecuali diminta lagi):
ekspor katalog harga "hanya yang berubah sejak ekspor terakhir"**, untuk
fitur ekspor file harga induk→cabang (format `.berkahpos` baru, magic
`BPRC1`, dibahas & disepakati sesi 21 Juli — lihat task manager utk status
eksekusi). `PriceSyncService._buildCatalog()` saat ini SELALU full-dump
tanpa filter `updated_at` sama sekali. Dihitung: full-dump ~2.775 produk
≈ 68 KB setelah gzip+enkripsi (JSON mentah 625 KB → gzip 50 KB → +35%
overhead AES/base64) — **kecil & TIDAK membengkak seiring waktu** (beda
dari riwayat transaksi yg jadi alasan Item 17/21 mendesak), jadi
watermark incremental **TIDAK diperlukan sekarang**. Waktu proses yang
selama ini terasa berat sebenarnya dari O(n²) fuzzy-matching (~7,3 juta
perbandingan Levenshtein utk 2.775×2.775 produk), BUKAN dari ukuran
transfer — sudah otomatis hilang begitu mesin fuzzy diganti pencocokan
barcode terindeks (Item 50 induk, sinkron harga tanpa fuzzy).

Kalau nanti katalog membesar signifikan (mis. 10.000+ produk) atau owner
minta hemat kuota lebih jauh: pola yang SAMA PERSIS dengan "Sync Ulang
Penuh" (Item 17 Fase 2, `LanSyncService.resetUploadWatermark`) bisa
dipakai di sini — simpan watermark "kapan terakhir ekspor katalog
harga berhasil" di `app_settings`, `_buildCatalog` filter
`updated_at >= since`, tombol "Ekspor Ulang Penuh" sbg escape hatch
manual (jaga-jaga kalau file ekspor sebelumnya hilang/tidak sempat
dipakai cabang, sebelum data berubah lagi). TIDAK dikerjakan sekarang —
catat di sini murni supaya tidak perlu didesain ulang dari nol kalau
suatu saat dibutuhkan.

## Item 51 — Usulan section baru CLAUDE.md: "Disiplin Rilis Profesional" (22 Juli, BELUM diputuskan — nunggu keputusan final user soal isi & pemangkasan)

**Konteks:** user usul menambahkan section checklist baru ke `CLAUDE.md`,
ditaruh SETELAH "Metode Test Sebelum Rilis" dan SEBELUM "Perencanaan —
PLAN.md", isinya 9 poin disiplin rilis (klasifikasi risiko A/B/C,
test skenario negatif, cari pola serupa lintas `lib/`, estimasi dampak
performa, acceptance check sudut pandang toko, dokumentasi risiko
tertunda, review mandiri skeptis utk perubahan finansial/keamanan,
commit kecil per sub-item yang bisa di-bisect, pertimbangan device lama
saat migrasi schema). Diminta opini dulu SEBELUM eksekusi (belum
ditulis ke CLAUDE.md).

**Opini yang sudah diberikan (ringkasan, detail lengkap ada di riwayat
percakapan sesi ini):**
- **Paling kuat/berbasis-bukti nyata proyek ini** (rekomendasi: pertahankan
  apa adanya): poin migrasi schema device lama (cocok dgn insiden nyata
  "migration test ripple" tiap `schemaVersion` naik, lihat HANDOFF.md),
  estimasi dampak performa utk operasi yang tumbuh (persis pola yang
  dipakai Item 50 di atas), cari pola serupa lintas file (cocok dgn
  duplikasi 4 renderer struk in-app/share/print/merged yang berulang
  kali jadi sumber bug parsial-fix), wajib test skenario negatif (sudah
  jadi praktik nyata sesi-sesi terakhir, tinggal diformalkan), review
  mandiri skeptis utk perubahan Kategori A/B (melengkapi revert-verify,
  bukan menduplikasi — menangkap hal yang test coverage sendiri bisa
  lewatkan spt try/catch kosong/default `??` tanpa alasan).
- **Berguna tapi lebih lunak/rawan jadi formalitas kosong** (rekomendasi:
  pertahankan tapi persingkat drastis): klasifikasi risiko A/B/C sebelum
  coding, acceptance check "sudut pandang pemilik toko".
- **Redundan, sebaiknya DIHAPUS/dipersingkat jadi 1 baris silang-rujuk**:
  poin "dokumentasi risiko yang sengaja ditunda" — isinya sudah persis
  sama dengan konvensi PLAN.md yang sudah dijelaskan di section
  "Perencanaan — PLAN.md" beberapa baris setelahnya di CLAUDE.md.
- **Paling rawan tidak realistis dalam praktik** (perlu kesadaran aktif
  tiap sesi, bukan cuma tertulis, biar benar-benar ditegakkan): poin
  commit kecil per sub-item yang bisa di-bisect — sesi ini SENDIRI belum
  konsisten menjalankannya (redesain price-match Item 50/Task #10 masuk
  1 commit besar, bukan dipecah per sub-item: engine matching, UI
  preview, fitur ekspor file, test — padahal masing² relatif independen).

**Kekhawatiran token/kepadatan file**: `CLAUDE.md` dibaca otomatis SETIAP
sesi dan filenya sendiri eksplisit minta tetap ringkas. Draft usulan user
~90 baris/9 subsection dgn banyak elaborasi & contoh — kalau ditambahkan
utuh, menambah kira² 35-40% ke ukuran file yang sekarang. Saran yang
sudah disampaikan: persingkat jadi checklist padat (judul poin + 1 baris
alasan, tanpa elaborasi panjang), ATAU ikuti pola proyek ini sendiri
(CHANGELOG/PATCHNOTES/HANDOFF/PLAN sudah terpisah per keperluan) — taruh
versi lengkap di file terpisah (mis. `docs/RELEASE_CHECKLIST.md`) dan
cukup 2-3 baris pointer di CLAUDE.md.

**Belum ada keputusan final dari user** soal: (1) tetap tambahkan section
penuh apa adanya, (2) pangkas sesuai saran di atas, atau (3) pisah ke
file terpisah dgn pointer singkat. **Jangan eksekusi/tulis ke CLAUDE.md
sampai user memutuskan salah satu opsi ini secara eksplisit.**

---

## Item 52 — "Laci Meja": Titip/Ketinggalan, Pinjaman Barang, Pre-order (26 Juli, rancangan FINAL, siap eksekusi — sempat dicoba, TERHENTI di migrasi skema krn bug alat sandbox, lihat docs/HANDOFF.md)

**Konteks**: usulan user bertahap lewat diskusi panjang (bukan spek awal
sekali jadi) — 3 fitur "catatan operasional harian" toko, digabung jadi
satu payung nama **"Laci Meja"** (sengaja nama umum, sisa ruang utk fitur
serupa nanti). Rancangan di bawah ini FINAL & sudah dikonfirmasi user
kata per kata — jangan didesain ulang, langsung eksekusi.

### Cakupan: 3 kategori

1. **Titip/Ketinggalan** — gabungan 2 sub-jenis (dibedakan field `jenis`):
   - `ketinggalan` — pembeli lupa bawa barang stlh transaksi (tak
     direncanakan).
   - `titip` — pembeli SENGAJA menyimpan barang yg sudah dibayar utk
     diambil belakangan.
2. **Pinjaman Barang** — wadah/deposit (galon, tabung gas) yg harus balik
   scr FISIK ke toko (BUKAN soal uang). Bisa kembali sebagian (pinjam 3,
   kembali 2 dulu — field `qty` vs `qtyReturned`).
3. **Pre-order** — backorder umum utk produk stok 0 (istilah retail:
   *backorder*), BUKAN "Antrian Stok" — nama itu SENGAJA dihindari krn
   kata "Antrian" sudah dipakai tombol lain di Kasir (`_TbBtn` "Antrian" =
   held/tertahan orders, warna kuning `AppTheme.antrianFg/antrianBg`) —
   pakai ulang bakal membingungkan walau konsepnya beda total.

### Aturan bisnis — Pre-order (PENTING, jangan disederhanakan keliru)

Kasus nyata dari user: LPG habis, pembeli menitipkan **tabung KOSONG**
sbg jaminan antrian (bukan cuma nomor urut kosong). Ada yg bayar duluan,
ada yg cuma titip tabung tanpa bayar — **keduanya dapat privilege
"first-in-first-serve" yg SAMA**, krn syaratnya adalah TABUNG DITITIP,
bukan uang.

- Per-satuan (`ProductUnits`) ada saklar opsional `requiresDeposit`
  ("Butuh Jaminan Fisik saat Antri?") — default false. ON utk produk
  model tukar-wadah (LPG, galon, dst), OFF = backorder biasa tanpa
  syarat fisik apa pun.
- Kalau `requiresDeposit` true: field **jumlah wadah dijaminkan WAJIB
  diisi, min 1** — validasi di layer aplikasi (BUKAN CHECK constraint
  DB), tidak bisa disimpan tanpa itu. Ini yg menutup kasus "bayar duluan
  tanpa titip tabung = TIDAK tercatat sama sekali (ignored)" — dipaksa
  lewat validasi form, bukan SOP lisan ke staff.
- **Urutan FIFO murni berdasar `createdAt` (kapan barang dititipkan)**,
  status `paid` HANYA informatif, TIDAK PERNAH ikut menentukan urutan
  antrian — jangan taruh `paid`/nominal DP di query pengurutan mana pun.
- Kalau `requiresDeposit` false (backorder biasa): form lebih simpel,
  tanpa field jaminan, FIFO murni dari tanggal daftar.

### Keterkaitan ke Struk — JANGAN buat nota terpisah (keputusan terakhir user)

> "Usahakan jangan buat struk baru, karena biasanya semua keperluan laci
> ini berbarengan dengan transaksi lain. Jadi jika nota terpisah, akan
> repot trackingnya."

- **Titip/Ketinggalan & Pinjaman**: entry point-nya SELALU dari layar
  Struk (tombol gabungan **"+ Catat"** — satu tombol, pilihan jenis di
  dalamnya, BUKAN dua ikon terpisah di app bar Struk yg sudah padat) —
  krn itu berarti SELALU ada transaksi terbuka saat itu. Kedua tabel
  py kolom `transactionId` **NOT NULL** (FK ke `Transactions`) — jadi
  baris tambahan yg menumpang nota yg sedang berjalan, BUKAN bikin baris
  `transactions` baru.
  - Pinjaman **sengaja BUKAN** numpang field "Catatan Internal" yg sudah
    ada di Struk (teks bebas, tidak bisa dihitung/difilter/ditandai
    status) — perlu tabel terstruktur sendiri.
- **Pre-order**: `transactionId` **NULLABLE** — umumnya juga menumpang
  transaksi yg sedang berjalan kalau ada, TAPI pengecualian SATU-SATUNYA
  yg boleh null: pembeli cuma nitip tabung tanpa beli apa pun (tidak ada
  transaksi lain sama sekali saat itu).
- **Scope YANG SUDAH DIPERSEMPIT** (keputusan eksplisit, jangan
  diperluas lagi tanpa user minta): entri-entri ini TIDAK perlu muncul
  sbg baris tercetak/tampil di struk fisik/gambar (tidak perlu produk
  placeholder sistem / baris `transaction_items` tambahan) — cukup kolom
  `transactionId` sbg penaut utk keperluan TRACKING/ketertelusuran.
  Modifikasi apa pun ke `receipt_screen.dart`/`printer_service.dart`
  (struk in-app/cetak/share) TIDAK termasuk scope Item 52.

### Dashboard "Laci Meja"

3 kartu ringkasan yg TAPPABLE sekaligus jadi filter (bukan TabBar biasa):
```
[ Titip/Ketinggalan: 5 ]  [ Pinjaman: 2 ]  [ Pre-order: 3 ]
```
- List di bawah kartu aktif, diurut PALING LAMA MENUNGGU dulu (pola sama
  persis `HutangTab`/`getDebtBook`: hijau <7hr → kuning 7-29 → merah
  >=30, tapi ambang hari utk Titip/Pinjaman/Pre-order kemungkinan beda
  krn barang fisik "mencurigakan" lebih cepat drpd hutang uang — user
  BELUM tentukan ambang pasti, tanya saat implementasi kalau perlu).
- Warna ikon/kartu Laci Meja: **dusty rose** — `#9C4F63` (fg terang) /
  `#E3A8B7` (fg gelap), bg `#F5E3E8`/`#3D2A2F` — warna BARU, belum ada di
  `app_theme.dart`, tambahkan sbg `laciFg(bool isDark)`/`laciBg(bool
  isDark)` sejajar `antrianFg`/`riwayatFg`/`tempelFg` yg sudah ada.
- Ikon: bentuk **laci** (kotak + garis tengah horizontal + pegangan kecil
  di tengah bawah garis) — BUKAN inbox/kotak generik, supaya beda dari
  ikon lain yg sudah dipakai.

### Navigasi ke Dashboard — tekan-tahan tab "Kasir" (ala Telegram)

**JANGAN** taruh sbg tombol ke-6 di baris ikon Kasir (`_KasirTopbar`,
sudah dicoba di mockup & TERBUKTI kejepit kotak carinya sampai batas
minimum di layar 360dp — HP kelas bawah target app ini). **JANGAN** juga
taruh sbg badge/FAB mengambang di atas konten Kasir (ganggu stepper qty
& tombol lain).

Keputusan final: **tekan & tahan tab "Kasir" di bottom nav**
(`main_shell.dart`, `NavigationBar` Material 3 — perlu widget kustom yg
menangani long-press per-destination, `NavigationBar` bawaan tidak
support ini native) → muncul menu kecil di atas ikon: "Buka Kasir" /
"Buka Laci Meja" (dgn badge count di opsi kedua). Detail perilaku:
- Badge angka total (gabungan 3 kategori) SELALU terlihat di ikon Kasir
  TANPA perlu ditahan dulu (persis pola badge notifikasi biasa).
- Tap SINGKAT tetap berfungsi normal (pindah ke tab Kasir) — tahan
  adalah perilaku TAMBAHAN, bukan pengganti.
- Menu tertutup kalau **tap ATAU SCROLL** di luar area menu (bukan cuma
  tap — user koreksi eksplisit poin ini), atau begitu salah satu opsi
  ditekan.
- Krn bottom nav adalah chrome GLOBAL, ini bisa diakses dari tab MANA
  PUN, tidak harus sedang di Kasir dulu.
- Catatan UX yg sudah diberi tahu ke user: gestur tahan ini agak
  tersembunyi/tidak ada affordance visual — butuh hint sekali di sesi
  pertama pengguna baru (blm didetailkan bentuknya, putuskan saat
  implementasi).

### Sinkronisasi (keputusan terakhir user, POLA SAMA PERSIS spt data master lain)

- **Host → Client: auto-merge**, ikut pola `dumpSince`/`mergeRows` yg
  sudah ada utk tabel master lain (full-dump per tabel, krn 3 tabel baru
  ini TIDAK akan punya alasan kuat pakai `updated_at` delta murni —
  ikuti pola `products`/`customers`: delta by `updated_at` KARENA
  memang ada kolom itu di rancangan skema Item 52).
- **Client → Host: lewat persetujuan owner**, PERSIS pola "usulan
  produk" Item 40 (`Products.locallyModified` → `dumpLocalProposals` →
  review manual owner via `sync_upload_queue`/`product_proposal_review_
  screen.dart`). Entri yg dibuat device non-owner set `locallyModified
  =true`; device owner TIDAK PERNAH set itu true (sumber kebenaran).
  Baris dari host SELALU bawa `locally_modified=false` (konsisten
  `mergeRows` yg sudah ada).
- Konsekuensi implementasi: 3 tabel baru masuk daftar `masterData` di
  `dumpSince`, masuk `clientMergeableTables` di `lan_sync_service.dart`,
  DAN perlu perluasan mekanisme `dumpLocalProposals`/proposal-review (yg
  SEKARANG spesifik ke produk) supaya generik menangani 3 tabel Laci
  Meja juga — atau bikin fungsi paralel serupa kalau memperluas yg
  sudah ada terlalu invasif. **Keputusan detail teknis ini BELUM
  final** — putuskan saat implementasi mana yg lebih aman (perluas vs
  paralel), prioritaskan TIDAK menyentuh alur usulan produk yg sudah
  matang & banyak bug-fix nyata di baliknya.

### Rancangan skema (sempat ditulis, DIBATALKAN krn bug codegen — lihat HANDOFF.md, tulis ulang persis ini saat lanjut)

```dart
// lib/core/database/tables/laci_meja_tables.dart
class LeftBehindItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(Transactions, #id)(); // NOT NULL
  TextColumn get itemName => text()(); // freeform
  TextColumn get jenis => text()(); // 'ketinggalan' | 'titip'
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get customerNameText => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get locallyModified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get collectedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class BorrowedItems extends Table {
  TextColumn get id => text()();
  TextColumn get transactionId => text().references(Transactions, #id)(); // NOT NULL
  TextColumn get itemName => text()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  TextColumn get customerNameText => text().nullable()();
  RealColumn get qty => real()();
  RealColumn get qtyReturned => real().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  BoolColumn get locallyModified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get fullyReturnedAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class PreorderEntries extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get productUnitId => text()();
  TextColumn get transactionId => text().nullable().references(Transactions, #id)(); // NULLABLE
  TextColumn get customerName => text()();
  TextColumn get phone => text().nullable()();
  RealColumn get qtyOrdered => real()();
  RealColumn get depositQty => real().withDefault(const Constant(0))(); // wajib >0 jika requiresDeposit
  BoolColumn get paid => boolean().withDefault(const Constant(false))(); // informatif, TIDAK pengaruh urutan
  TextColumn get note => text().nullable()();
  BoolColumn get locallyModified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get fulfilledAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}
```
Plus kolom baru `ProductUnits.requiresDeposit` (`BoolColumn`, default
false) di `product_tables.dart`. Migrasi: `schemaVersion` 21→22,
`m.createTable()` x3 + `m.addColumn(productUnits, productUnits.
requiresDeposit)` di blok `if (from < 22)`.

### Urutan eksekusi disarankan (per fase, masing² diverifikasi sblm lanjut — disiplin sesi ini)

1. Skema + migrasi (di atas) → **jalankan `dart run build_runner build
   --delete-conflicting-outputs` DULU, pastikan berhasil, sebelum tulis
   kode lain apa pun** (lihat HANDOFF.md soal bug sandbox yg sempat
   menghentikan ini).
2. DB layer: CRUD dasar 3 tabel (create/list/tandai-selesai) + test DB
   murni.
3. Sync: masuk `dumpSince`/`clientMergeableTables`, + jalur usulan
   client→host (perluas atau paralel — putuskan saat itu).
4. UI: layar Laci Meja (3 kartu + list difilter).
5. UI: tombol "+ Catat" di Struk (Titip/Ketinggalan + Pinjaman).
6. UI: entry Pre-order dari pencarian Kasir (tombol inline saat stok 0)
   + halaman Produk (jalur kedua) — TANPA tombol "+" di dashboard utk
   kategori ini (cuma pantau/tindak-lanjuti dari sana).
7. UI: toggle `requiresDeposit` ("Butuh Jaminan Fisik") di form produk.
8. UI: gesture tekan-tahan tab Kasir di `main_shell.dart`.
9. Test lengkap (revert-verify tiap bagian) + `flutter analyze` 0 issue.
10. Docs (CHANGELOG/PATCHNOTES/HANDOFF) + commit + push — **hapus item
    ini dari PLAN.md setelah selesai**, sesuai konvensi CLAUDE.md.

---

**Item lain yang masih terbuka:**
1. **Item 47** (pengeluaran tidak ikut ekspor PDF/Excel Laporan) & **Item
   48** (avatar produk kasir jadi soft/pastel) — user setuju, siap
   eksekusi, ditahan atas permintaan ("sisanya biarkan"). Detail di atas.
2. **Item 23 sisa** (`printer_service.dart` `printReceipt` tunggal,
   `transaksi_tab.dart`, `tx_history_sheet.dart`, `settleMergedDebt`, Buku
   Hutang, Tutup Kasir "kas sistem" overstated) — belum disentuh, lihat
   detail Item 23 di atas.
3. **Item 17+21 (sync)** — ditunda ke sesi fokus (risiko data-loss).
4. **Item 28** (pegawai lanjutkan pesanan owner lintas device) — konsep,
   belum didesain.
5. **Item 41** (audit kode 18 Juli) — mayoritas P1/P2 SUDAH dieksekusi
   di sesi yang sama (lihat CHANGELOG). Sisa: B.1 rotasi storeKey (butuh
   keputusan desain user), C.2 (gabung Item 17+21), dan daftar P3 —
   detail di Item 41 di atas.
6. **Item 51** (usulan section "Disiplin Rilis Profesional" di CLAUDE.md)
   — nunggu keputusan final user (tambah apa adanya / pangkas / pisah ke
   file terpisah). Detail opini di Item 51 di atas.
7. **Item 52** ("Laci Meja" — Titip/Ketinggalan, Pinjaman, Pre-order) —
   rancangan FINAL siap eksekusi, SEMPAT dicoba tapi terhenti di langkah
   migrasi skema krn bug alat codegen Drift di sandbox sesi itu (BUKAN
   bug kode/rancangan — lihat docs/HANDOFF.md utk bukti lengkap & cara
   cek cepat di sesi baru). Semua perubahan source sudah dibatalkan
   bersih. Detail rancangan lengkap (skema, alur, business rules,
   urutan eksekusi per fase) di Item 52 di atas — jangan didesain ulang,
   langsung eksekusi dari fase 1.
