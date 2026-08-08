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
7. **Item 52 — bug sinkron harga antar toko: barcode sama, harga sudah
   sama, tapi sync tetap usulkan harga beda** (kasus konkret user: "Rinso
   cair 500", 5000 → diusulkan 4400). Analisis mendalam (`PriceMatchService`
   dkk) SUDAH dilakukan, **root cause paling mungkin SUDAH diidentifikasi
   tapi BELUM diverifikasi ke kasus nyata** (user belum sempat kirim detail
   log/DB utk "Rinso cair 500" spesifik — sesi terputus di titik ini).
   - **Root cause kandidat #1 (paling mungkin)**: asimetri dedup di
     `price_sync_service.dart` query ekspor katalog (~baris 177-198) —
     subquery barcode DI-dedup (`GROUP BY product_unit_id`), tapi JOIN
     `price_tiers WHERE min_qty = 1` TIDAK di-dedup. Kalau toko SUMBER
     (yang ekspor) punya 2 baris tier harga dgn `minQty=1` utk 1 unit yg
     sama (kelas bug lama yg sudah pernah kejadian — sudah ada guard
     `_upsertBaseTier` di `price_preview_screen.dart` tapi cuma mencegah
     ke depan, tidak membersihkan data lama), query ini menghasilkan 2
     baris katalog barcode SAMA dgn harga BEDA → `PriceMatchService.match`
     tidak dedup input katalog → 1 diusulkan "unchanged", 1 lagi
     "changed" utk unit lokal yg sama persis. Ini yg paling cocok dgn
     laporan user (barcode+harga lokal sudah sama, tapi tetap diusulkan
     beda).
   - Kandidat lain (lebih lemah, lihat riwayat percakapan sesi ini utk
     detail lengkap): duplikat tier serupa di sisi LOKAL (bukan sumber);
     Tier 3/4 (match nama, bukan barcode) ke-alias permanen ke satuan
     yang salah lewat fallback unit dasar; barcode "nyangkut" di produk
     nonaktif yang belum di-release (`_releaseBarcodesForProduct`) —
     ini TIDAK bikin harga ghost terpakai langsung (sudah dicek aman,
     `allProducts` filter aktif-saja), tapi BISA memblokir alias barcode
     ke Tier 1 selamanya via `_linkBarcode` "sudah terdaftar → dilewati".
   - **Langkah berikut**: minta user kirim salah satu — (a) bagian log
     sync utk "Rinso cair 500" khususnya baris `unit=...` & verdict
     harga (bukan cuma fase match), atau (b) buka Edit Produk "Rinso
     cair 500" di KEDUA toko, cek apakah ada 2 tier harga `min 1` di
     satuan yang sama (di toko manapun) atau ada produk lain/nonaktif
     dgn nama/barcode sama. Setelah kandidat #1 terverifikasi, fix-nya:
     tambah `GROUP BY`/subquery dedup pada JOIN `price_tiers` di
     `price_sync_service.dart`, plus one-time cleanup query utk baris
     tier duplikat `minQty=1` yang sudah terlanjur ada di data user.
   - **Terpisah, belum diputuskan user**: apakah search produk di input
     field kasir perlu ditambah kemampuan cari-by-barcode juga (sekarang
     hanya cari nama/`kode_produk`, lihat `watchProductsForKasir` di
     `app_database.dart` — barcode scan sepenuhnya jalur lain, kamera/HID,
     terpisah dari field pencarian). Ditawarkan, belum dikonfirmasi user.

8. **Item 53 — percepat alur input harga modal + stok dari nota supplier
   (PENDING, user eksplisit "pending dulu poin ini")**. Konteks: toko
   cabang belum pakai fitur ini secara penuh, tapi diperkirakan perlu ke
   depan — keluhan user: tidak selalu ada waktu hitung manual dari nota
   sampai input satu-satu di form Edit Produk. Insight yang sudah
   didiskusikan (belum ada keputusan/eksekusi):
   - **CSV import yang SUDAH ADA** (`csv_import_service.dart`) sudah
     mendukung kolom `harga_beli`/`cost` & `stok`/`qty`, dan sudah bisa
     UPDATE produk existing (cocok barcode → kode_produk → nama+satuan),
     bukan cuma bikin produk baru — opsi termurah, tinggal dibiasakan
     jadi alur kerja (isi template Excel sekali per nota, import),
     tanpa perlu kode baru sama sekali.
   - **Mode "restock" ala `StockOpnameScreen`** (scan barcode → sesuaikan)
     — pola UX serupa bisa dipakai utk terima barang: scan barcode tiap
     item nota → tampilkan harga modal terakhir sbg default (tinggal
     koreksi) → qty DITAMBAHKAN (bukan di-replace spt opname). Belum
     didesain detail, kandidat termurah kalau mau dibangun sbg fitur baru.
   - **OCR nota supplier** — dinilai ROI rendah utk kasus toko grosir
     (nota tulisan tangan/thermal print supplier tidak konsisten
     formatnya, OCR sering salah baca angka terutama kolom harga, tetap
     butuh verifikasi manual per baris). Rekomendasi: skip kecuali
     supplier kirim nota digital berformat tetap (PDF/Excel) — baru
     worth bikin parser CSV-import khusus format itu.
   - **Keputusan desain yang MENGGANTUNG** (perlu diputuskan SEBELUM
     bangun alur import manapun di atas, supaya tidak bongkar ulang):
     harga modal pakai "harga terakhir" (skema sekarang, `costPrice`
     1 angka) atau mulai hitung rata-rata tertimbang (lebih akurat kalau
     harga modal sering naik-turun antar pembelian, tapi perlu simpan
     riwayat per-batch pembelian, bukan cuma 1 kolom).

## Item 54 — QR Share (handoff antar-device) bawa keterangan item, bukan cuma kode (6 Agustus, BELUM dieksekusi)

**Permintaan user**: teks QR handoff (`OrderParserService.encodeHandoff`,
dipakai `_showHandoffQr`/tombol "Bagikan" `Share.share(qrText)` di
`cart_sheet.dart:918`) sekarang cuma berisi baris kode mesin `#PSN:...`
+ baris meta (`Pegawai:`/`Nama:`/`PelangganId:`/`Nota:`) — TANPA daftar
item yang manusia bisa baca. Minta ditambah keterangan item (nama
produk, satuan, qty — mungkin juga Total), **format SAMA PERSIS** dgn
`buildOrderText()` di katalog HTML (`order_page_service.dart:1066-1109`)
yang SUDAH begini:
```
PESANAN — <toko>
━━━━━━━━━━━━━━━
Ayam Potong Kg × 2
Galon Aqua Galon × 1
━━━━━━━━━━━━━━━
Total: Rp ...

Nama: ...
HP: ...
Catatan: ...

#PSN:U1=2;U2=1
```
— daftar item + Total tampil DULU (manusia baca sekilas isi pesanan di
WhatsApp/preview sebelum scan), baris meta & kode mesin tetap di bawah.

**Kompatibilitas parser** — user minta dicek: kalau "Tempel Pesanan" (di
cart utama MAUPUN di state "Tambah Belanjaan" pasca-checkout) tidak
kompatibel dgn format baru ini, sesuaikan supaya BISA terima ATAU
sengaja abaikan baris tambahan itu (cukup baca baris kode `#PSN:` saja)
— **teknis sama persis dgn cara parser sudah menangani teks dari
katalog HTML pelanggan** (yang sudah lebih dulu berformat begini).

**Sudah dicek (belum dieksekusi)**: `PasteOrderSheet` dipakai generik
lewat `cartId` di KEDUA konteks (cart utama `cart_sheet.dart:332`, DAN
scan/tempel di `kasir_screen.dart:1368,1823` — termasuk alur "Tambah
Belanjaan", cukup beda `cartId` yg dioper) — SATU pemanggilan
`OrderParserService.parse()` (`paste_order_sheet.dart:59`) menangani
keduanya, jadi cukup satu titik verifikasi/perbaikan, bukan dua.
`_machineLine`/baris meta di `parse()` sudah regex per-baris (`^Nama:`
dst, `#PSN:(.+)$` multiline) — SUDAH mentolerir baris tambahan
apa pun di sekitarnya (persis kenapa teks katalog HTML yang jauh lebih
panjang dari itu sudah bisa di-parse sekarang), jadi kemungkinan besar
TIDAK perlu ubah `parse()` sama sekali — cukup ubah `encodeHandoff()`
utk menyisipkan baris item+Total, lalu **WAJIB tes ulang** seluruh test
`encodeHandoff`/`parse` roundtrip (`order_parser_service_test.dart`,
`kasir_handoff_qr_test.dart`) utk pastikan tidak ada tabrakan (mis. nama
produk yang kebetulan diawali kata kunci baris meta seperti "Nama:").

## Item 55 — Bug "Tempel Pesanan" pegawai (non terima_pembayaran) tidak dapat produk dari QR/teks owner — BUTUH LOGGING DIAGNOSTIK, teori kode SUDAH MENTOK (6 Agustus, siap eksekusi)

**Konteks lengkap** (ringkas dari investigasi panjang sesi ini — jangan
ulangi dari nol): owner input beberapa produk baru → share via QR atau
"Salin Teks Pesanan" → di-tempel pegawai (kasir role, TANPA izin
`terima_pembayaran`) via "Tempel Pesanan" → **TIDAK ADA produk masuk
keranjang**, error "Kode pesanan tidak valid / tidak ada barang
dikenali" (`kasir_screen.dart:1279`, dari `!parsed.hasMachineCode ||
parsed.items.isEmpty`). **Detail penentu**: QR/teks yang PERSIS SAMA,
kalau diterima ASISTEN (yang punya izin bayar), **BERHASIL**.

**Tiga hipotesis SUDAH DISINGKIRKAN via pembacaan kode** (bukan dugaan
kasar — sudah dibaca file:line-nya langsung):
- ID salah/berubah di sisi owner sendiri (RUANG LINGKUP: `produk_form_
  screen.dart`, `saveProduct`) — RUNTUH karena asisten yg terima data
  SAMA PERSIS berhasil; kalau ID-nya salah dari sumbernya, asisten juga
  harusnya gagal.
- Bug encode multi-item di `encodeHandoff`/split `;` — dicek baris per
  baris, tidak ada celah.
- Percabangan kode berdasar role di jalur scan/paste/parse — dicek
  berulang kali, TIDAK ADA percabangan role di `kasir_screen.dart`/
  `paste_order_sheet.dart`/`order_parser_service.dart` sama sekali.
- **Hipotesis watermark download (`products` delta-sync + `product_
  units` full-dump + FK silent-drop) SEMPAT jadi kandidat kuat** — tapi
  **user sudah verifikasi produk itu ADA & ketemu di pencarian Produk
  pegawai**, jadi baris `products`-nya TIDAK hilang. Ini melemahkan
  (mungkin menyingkirkan) teori itu juga — TAPI belum 100% pasti,
  karena "ketemu di pencarian" belum tentu berarti `product_units`-nya
  (satuan spesifik yang dirujuk kode `#PSN:`) juga utuh & `id`-nya
  PERSIS sama dgn yang dirujuk di kode — belum diverifikasi granular
  sampai level itu.

**Keputusan user: STOP menebak dari pembacaan kode statis — pasang LOG
DIAGNOSTIK supaya reproduksi berikutnya kasih bukti runtime langsung,
bukan teori lagi.**

**Revisi user (JANGAN tulis ke Downloads)**: logging TIDAK boleh nulis
ke file publik `Downloads/`. Sebagai gantinya, bikin **halaman debug
dedicated di dalam app** — layar sementara yang gampang dibuang lagi
setelah bug ini kelar, cukup dilihat langsung di layar HP (tidak perlu
ambil file/USB debug sama sekali).

**Rencana implementasi**:
1. **Penyimpanan diagnostik** — kelas statis sementara baru, mis.
   `OrderParseDiagnostics` (bisa taruh di file baru
   `lib/core/services/order_parse_diagnostics.dart`, atau cukup
   top-level di `order_parser_service.dart` sendiri) — `static final
   List<String> entries = []` (in-memory saja, cukup utk satu sesi
   reproduksi; TIDAK perlu persist ke DB/SharedPreferences, sengaja
   simpel krn throwaway). Batasi mis. 200 entry terakhir (buang yg
   paling lama) biar tidak membengkak kalau lupa dicabut.
2. **Titik logging** — di `OrderParserService.parse()`
   (`order_parser_service.dart` sekitar baris 108-167, loop per-pasangan
   item):
   - Di AWAL (setelah cek `hasMachineCode`): catat teks MENTAH yang
     diterima (raw `text` parameter) — supaya kelihatan PERSIS apa yang
     benar-benar ter-scan/ter-paste (verifikasi tidak ada korupsi/
     potongan karakter dari scanner/clipboard).
   - Untuk SETIAP pasangan `unitId=qty...`: `unitId` mentah, hasil
     `SELECT * FROM product_units WHERE id = ?` (ADA/TIDAK + `product_
     id` kalau ada), hasil `SELECT * FROM products WHERE id = ?` pakai
     `unit.productId` (ADA/TIDAK + `is_active` kalau ada), dan
     kesimpulan baris ini (masuk `items` atau `notFound`, alasan
     spesifik yang mana dari 2 kondisi gagal).
   - Tiap baris hasil `.add()` ke `OrderParseDiagnostics.entries`
     (bukan `print()`/`debugPrint` — supaya tetap kebaca di build
     release, bukan cuma pas `flutter run` USB-tethered).
3. **Halaman debug** — widget baru sederhana, mis.
   `ParseDiagnosticsScreen` (`StatelessWidget`, `ListView` isi
   `SelectableText`/`Text` per entry terbaru dulu, + tombol "Salin
   Semua" ke clipboard biar gampang dikirim balik ke sesi ini via chat
   — TANPA nulis/baca file apa pun). Entry point-nya SEMENTARA saja,
   paling praktis: tombol/ikon kecil TAMBAHAN di `PasteOrderSheet`
   (`paste_order_sheet.dart`, dekat tombol proses) yang cuma tampil
   selama fitur ini masih aktif dipakai investigasi — push route ke
   `ParseDiagnosticsScreen` biasa (`Navigator.push`, tidak perlu
   didaftarkan ke GoRouter permanen).
4. **WAJIB dicabut setelah kelar**: seluruh 3 bagian di atas
   (`OrderParseDiagnostics`, titik `.add()` di `parse()`, halaman +
   tombol akses) SEMENTARA murni utk investigasi — begitu root cause
   ketemu & fix-nya dieksekusi, hapus total (bukan cuma dimatikan via
   flag), supaya tidak nyangkut selamanya di produksi.

**Langkah setelah logging terpasang**: minta user build APK debug,
reproduksi bug persis skenario di atas (owner buat produk baru → share
→ pegawai tempel, GAGAL lagi), buka halaman debug baru itu di device
pegawai, salin isinya, kirim balik ke sesi ini. Dari situ akan langsung
ketahuan PERSIS di titik mana rantai `unitId → unit → product` putus
(unit tidak ketemu / product tidak ketemu / product tidak aktif) —
baru eksekusi fix yang benar-benar menyasar akar masalahnya, bukan
tebakan lagi.

## Item 61 — Temuan sync lain (menengah, dampak lebih sempit — 6 Agustus, siap eksekusi kalau ada waktu)

Lima temuan tambahan dari audit sync sesi ini, dampak lebih sempit dari
Item 58-60 tapi tetap nyata:

1. **Selisih jam device (clock skew) bikin data host hilang dari
   window download, diam-diam & permanen.** Watermark download
   (`downloadSyncStartedAt`, `lan_sync_service.dart:1157`) pakai jam
   KLIEN, dipakai memfilter baris berdasar jam HOST — toleransi skew
   cuma 5 menit (`:815-822`) tanpa validasi/klem apa pun. TIDAK ADA
   `resetDownloadWatermark` di mana pun (beda dari upload yg punya
   "Sync Ulang Penuh") — sekali watermark klien "lebih maju" dari jam
   host, macet PERMANEN tanpa cara reset dari UI sama sekali.
   **Metode perbaikan**: (a) tambah `resetDownloadWatermark` +
   tombol/opsi di Sync screen (bisa disatukan dgn "Sync Ulang Penuh"
   supaya reset KEDUA watermark sekaligus, lebih aman drpd biarkan user
   pilih salah satu tanpa paham bedanya); (b) pertimbangkan jangka
   panjang: watermark idealnya berbasis timestamp SERVER (host kirim
   balik "jam sekarang menurut saya" di response, klien simpan itu
   sbg watermark next round) bukan jam klien sendiri — pola ini
   menghilangkan skew SAMA SEKALI drpd cuma menoleransi sampai 5 menit.
2. **`_reconcileTransactionTotals` tanpa guard item kosong**
   (`app_database.dart:2452` `newTotal` vs `:2463` `newPaid` — cuma
   `newPaid` yg ada guard `allPayRows.isEmpty ? tx.paid : sumPay`).
   Trigger nyata: item transaksi yg parent header-nya sempat DITOLAK
   PERMANEN (`rejectSync`) di antrian lama, baru dapat item susulan
   belakangan → FK gagal (parent tidak ada), baris di-skip selamanya
   (`app_database.dart:5063-5075`, error di-swallow ke CrashLog),
   `newTotal` jadi 0 tanpa item yg genuinely hilang. **Metode
   perbaikan**: tambah guard sama spt `newPaid` — `final newTotal =
   itemRows.isEmpty ? tx.total : itemRows.fold(...)`, supaya baris
   TANPA item (bukan genuinely 0) tidak menimpa total lama jadi 0.
3. **Tie-break urutan `stock_after` beda antara pembaca & penulis
   ulang** — `_rawBaseStock` order `created_at DESC, rowid DESC`
   (`:568-578`), `rebuildStockAfterForUnits` order `created_at ASC, id
   ASC` (UUID acak, bukan `rowid`) — utk baris di detik yg SAMA, host
   & klien bisa pilih baris "terakhir" yg BEDA stlh sync, bikin saldo
   stok berbeda permanen antar device. **Metode perbaikan**: samakan
   tie-break KEDUANYA — opsi termudah: `rebuildStockAfterForUnits`
   ikut pakai `rowid` sbg tie-break kedua (bukan `id`/UUID), identik
   dgn `_rawBaseStock`, supaya urutan interpretasi SELALU konsisten dgn
   cara baca stok yg sudah ada.
4. **Approval per-kategori bisa memisah penjualan dari pergerakan
   stoknya.** Owner approve "Transaksi" tanpa "Stok" (checkbox
   terpisah per kategori, `sync_screen.dart` dialog approve) →
   transaksi tercatat tapi stok tidak pernah berkurang, PERMANEN (baris
   `stock_ledger` yg di-skip tidak pernah dikirim ulang scr delta).
   **Metode perbaikan**: PALING AMAN — kalau kategori "Transaksi"
   dipilih, kategori "Stok" WAJIB ikut ter-approve otomatis (tidak bisa
   dipisah lewat UI sama sekali, disable checkbox-nya atau digabung jadi
   1 kategori) — penjualan & pergerakan stok SECARA BISNIS tidak boleh
   pernah terpisah.
5. **Penghapusan `expenses` tidak pernah propagate ke device lain.**
   `deleteExpense` (`app_database.dart:3521-3522`) hard DELETE, padahal
   `expenses` sync-nya append-only (cuma kirim baris BARU, tidak pernah
   kirim "baris ini dihapus") — expense yg dihapus di 1 device TETAP
   ada di device lain yg sudah menerimanya, laba bersih antar-device
   beda permanen. **Metode perbaikan**: expense butuh soft-delete (kolom
   `deleted_at`/`is_active` spt pola tabel lain), filter query TOTAL
   pengeluaran (`getNetProfitExpenseTotal` dkk) exclude yg soft-deleted
   — dijadikan UPDATE (append-only-compatible, bukan DELETE) supaya
   status "dihapus" ikut ter-sync sbg baris baru yg diupdate, konsisten
   dgn pola tabel lain di app ini (produk/pelanggan pakai `is_active`,
   bukan hard delete).
