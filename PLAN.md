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

## Item 54 — Laci Meja: ambil parsial + riwayat per-nota + log global (poin 1, 2, 5 dari 5 usulan user — DISETUJUI, BELUM dieksekusi)

User mengajukan 5 usulan sekaligus; **poin 3 (nama ikut nota) & 4 (redesain
kartu) SUDAH SELESAI & di-commit** (lihat CHANGELOG). Sisanya di bawah —
arah arsitekturnya sudah diputuskan user, tinggal dieksekusi.

**Keputusan arsitektur (sudah dipilih user, jangan didesain ulang):**

1. **Pencatatan pengambilan = TABEL LOG APPEND-ONLY**, BUKAN mengurangi
   kolom qty. Sisa dihitung `qty − Σ log`. **Alasan (penting)**: ketiga
   tabel Laci Meja adalah master-data yang disinkron *last-write-wins by
   `updated_at`* — read-modify-write pada kolom qty bikin dua pengambilan
   bersamaan (owner ambil 2, kasir ambil 1) SALING MENIMPA, salah satunya
   hilang diam-diam. Itu ledger barang fisik, jadi selisihnya nyata. Baris
   log tidak pernah bentrok. Pola acuan: `transaction_payments`.
2. **Sinkronisasi log TETAP lewat antrian persetujuan owner** — pilihan
   eksplisit user, BUKAN auto-merge ala `appendOnlyTables`. Tetap
   kompatibel dgn log append-only: barisnya tidak saling menimpa, hanya
   tampilan di HP owner yang baru berubah setelah approve.

**Poin 1 — ambil/penuhi parsial.** `markLeftBehindCollected` &
`fulfillPreorderEntry` sekarang semua-atau-tidak (set `collectedAt`/
`fulfilledAt`). Pinjaman SUDAH parsial (`returnBorrowedItemQty` akumulasi
`qtyReturned`) tapi tanpa jejak per-pengambilan. Butuh dialog qty (pola
sama dgn `_showReturnDialog` yang sudah ada) + flag "selesai" dihitung
ulang dari log (pola `_reconcileTransactionTotals`).

**Poin 2 — riwayat + timestamp per nota, ketiga kategori.** Kartu per-nota
utk titipan & pinjaman SUDAH ADA di `receipt_screen.dart`
(`_buildLeftBehindOtherCard` ~3002, `_buildBorrowedCard` ~2964) tapi TANPA
timestamp. **Pre-order belum punya kartu sama sekali** di nota — cuma
penanda inline "· Titip n" (~418-430). Format baris meniru
`_buildPaymentTimeline` (~3093).

**Poin 5 — log riwayat keseluruhan** di Laci Meja: satu layar/tab, ketiga
kategori bercampur urut waktu. Sumber data SAMA dgn poin 2 (satu tabel,
dua tampilan).

**Jebakan yang WAJIB dicek saat eksekusi (mudah terlewat):**
- `tutup_buku_service.dart` (~240-254) menghapus baris Laci Meja bersama
  notanya saat arsip — baris log baru WAJIB ikut dihapus di situ, kalau
  tidak jadi orphan permanen. Guard "blokir arsip kalau masih ada yang
  terbuka" (~150-164) juga perlu ditinjau ulang thd definisi "terbuka"
  yang baru (derived dari log).
- `dumpLaciMejaProposals` pakai `SELECT *`, dan
  `filterUnchangedLaciMejaProposals` membandingkan per-kolom — keduanya
  harus ikut disesuaikan utk tabel/kolom baru.
- Data pinjaman lama (`qtyReturned` sudah terisi) perlu di-backfill jadi 1
  baris log historis saat migrasi, kalau tidak riwayatnya tampak kosong
  padahal qty sudah berkurang.
- schemaVersion naik (sekarang 32) + migration test baru.

**Storage**: ~150 byte/baris log; 20 pengambilan/hari ≈ 1 MB/tahun — tidak
signifikan dibanding `transactions`.

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

> **Diverifikasi ulang ke kode 11 Agustus 2026.** Tiap poin di bawah
> dicek satu per satu ke file/baris sungguhan — yang sudah keburu
> selesai lewat pekerjaan sesi lain DIHAPUS dari daftar (C.2 & A.11,
> lihat catatan di bawah), sisanya dikonfirmasi MASIH ADA. **Angka &
> deskripsi ikut dikoreksi** di beberapa poin yang cakupannya sudah
> berubah sejak audit asli 18 Juli (file makin besar, callback statis
> bertambah, duplikasi validasi hex jadi 3 tempat). Jangan percaya
> daftar ini apa adanya lagi kalau sudah lewat beberapa sesi —
> verifikasi ulang dulu spt ini sebelum dieksekusi.
>
> **Sudah SELESAI lewat pekerjaan lain (dihapus dari daftar):**
> - **C.2 (upload klien→host selalu full-dump sejak epoch)** — tertutup
>   oleh Item 17 Fase 2 (`sync_upload_queue` persisten) + Item 58
>   (union antrian) + Item 61.1: watermark upload
>   (`_kUploadWatermarkKey` di `lan_sync_service.dart`) sekarang benar²
>   dimajukan, lengkap dgn pasangan `resetUploadWatermark`.
> - **A.11 (`mergeRows` menghitung "diterima N" dari return
>   `customInsert`)** — sekarang sudah `final inserted = await
>   customInsert(...)` + `if (inserted > 0) count++`, jadi baris yang
>   ter-skip `INSERT OR IGNORE` tidak lagi ikut terhitung.

### Sisa [P1]/[P2] — butuh keputusan/desain atau device fisik

1. **[P1] B.1 — rotasi/pencabutan storeKey.** Risiko QR pairing membawa
   storeKey master polos SUDAH didokumentasikan keras di
   `pairing_service.dart`, tapi MEKANISME mitigasi belum ada: fitur
   "rotasi kunci toko" (generate storeKey baru + rekey SQLCipher +
   re-pair semua device) dan/atau un-pair device (HP kasir hilang,
   pegawai keluar). Butuh desain UX + keputusan user — jangan dieksekusi
   sepihak. Sementara: kunci bocor = jalur "Alihkan Owner" ke identitas
   toko baru. _(Dikonfirmasi 11 Agt: masih belum ada — `pairing_service.
   dart` sendiri masih menulis "Belum ada mekanisme un-pair / rotasi".)_

_(C.2 dulu ada di sini — SUDAH SELESAI, lihat catatan verifikasi di
atas.)_

### Sisa [P3]

Semua poin di bawah **dikonfirmasi MASIH ADA** per 11 Agustus 2026
(dicek ke file:baris; nomor & deskripsi yang sudah bergeser sejak audit
asli ikut dikoreksi di tempat).

1. **A.8 redirect router tidak reaktif** — `ref.read` tanpa
   `refreshListenable`: perubahan state lisensi async tidak memicu
   redirect sampai navigasi berikutnya. Dokumentasikan atau pasang
   Listenable gabungan. _(`app_router.dart:71,76` — masih `ref.read`.)_
2. **A.9 `beforeOpen` unitTypes pakai `insertOrReplace`** padahal
   komentar bilang insertOrIgnore — bom waktu kalau kelak ada UI edit
   satuan; samakan dgn `_seedDefaults`. _(Masih beda: `unitTypes`
   `insertOrReplace`, `kasirPermissions` di bawahnya `insertOrIgnore`.)_
3. **A.10 master data tanpa tombstone** — **SEBAGIAN SUDAH TERJAWAB**:
   utk PRODUK, desain soft-delete tersinkron SUDAH ADA & SUDAH CUKUP
   (tidak perlu tabel tombstone) — masalahnya murni bug implementasi
   sempit (`deactivateProduct` lupa cap ulang `updated_at`), SUDAH
   diperbaiki (lihat CHANGELOG `7f20d38`). **Utk PELANGGAN: sudah
   diverifikasi 11 Agt — AMAN**, soft-delete `customers` sudah cap
   `updatedAt: Value(DateTime.now())` eksplisit. **Sisa yang belum
   diverifikasi: tier harga** (`price_tiers`/`alt_prices` disinkron
   full-dump TANPA `updated_at` sama sekali — pola beda dari
   products/customers, jadi pertanyaan tombstone-nya juga beda bentuk).
4. **A.12 tutup buku: crash di antara copy-arsip & delete-data**
   meninggalkan state nyangkut ("Arsip tahun X sudah ada" padahal data
   belum terhapus) tanpa jalur pemulihan. _(Masih: `execute()` copy file
   dulu, baru `transaction()` delete — dua langkah terpisah.)_
5. **B.7 `minifyEnabled=false`** — aktifkan R8 + keep rules (uji regresi
   penuh, terutama drift/sqlcipher/BT). _(`build.gradle.kts:59-60`,
   `minifyEnabled`+`shrinkResources` dua-duanya masih false.)_
6. **B.8 `HttpCloudflareApi` tanpa timeout** — tambah connectionTimeout +
   `.timeout()` seperti LAN sync. _(`cloudflare_publish_service.dart:75,
   109` — `HttpClient()` polos, tanpa timeout apa pun.)_
7. **C.3 `SystemChrome.setSystemUIOverlayStyle` & `ref.watch` di dalam
   `MaterialApp.builder`** — guard per perubahan brightness; pindahkan
   watch ke build. _(`main.dart:120-122` — masih di dalam `builder:`.)_
8. **C.4 `generateUniqueLocalId` memuat semua transaksi hari itu** —
   ganti `SELECT MAX(local_id)` + fallback bila mau rapi. _(Sekarang
   malah SELECT penuh dari DUA tabel: `transactions` +
   `reserved_order_numbers`, lihat `_usedLocalIdsWithPrefix`.)_
9. **D.2 gotcha cleartext HTTP** — sync LAN kebetulan lolos blokir
   cleartext Android karena dart:io; catat di CLAUDE.md (migrasi ke
   package `http`/cronet akan mendadak gagal tanpa NSC exception).
   _(Dicek 11 Agt: kata "cleartext" masih NOL di CLAUDE.md & docs/ —
   belum pernah dicatat.)_
10. **D.3 Java 8 tanpa core library desugaring** — potensi build gagal
    saat upgrade plugin. _(`build.gradle.kts:25-30` — masih
    `VERSION_1_8` tanpa `coreLibraryDesugaring`.)_
11. **D.5 terkunci di Flutter 3.24.5 (pin CI)** — di 3.44.6 stable gagal
    kompilasi: 1 error `CardTheme`→`CardThemeData` (`app_theme.dart:175`)
    + 53 deprecation (`withOpacity`, `DropdownButtonFormField.value`,
    `onReorder`). Rencanakan sesi upgrade SDK khusus (fix serentak +
    full test + uji APK device fisik). _(CI masih pin `3.24.5`. Angka
    error/deprecation di atas dari pengukuran 18 Juli — kemungkinan
    sudah BERTAMBAH sejak itu, ukur ulang sebelum eksekusi.)_
12. **E — clean code** (angka diperbarui 11 Agt, semua masih ada):
    - pecah bertahap file raksasa — **sudah tumbuh jauh** dari angka
      audit asli: `kasir_screen.dart` 3.7k→**4.2k**, `app_database.dart`
      3.4k→**6.2k**, `receipt_screen.dart` 2.7k→**3.6k**.
    - `LanSyncService` callback statis satu-slot — **sekarang 4, bukan
      2**: `onQueueChanged`, `onProposalsChanged`,
      `onLaciMejaProposalsChanged`, `onCustomerProposalsChanged`
      (masing² `static void Function()?`, listener kedua menimpa yang
      pertama).
    - loop mati `lastQtyIdx` di `discount_allocation.dart:47-50` —
      `lines` sudah difilter `eq > 0` di baris 42, jadi syarat
      `lines[i].eq > 0` SELALU true & `lastQtyIdx` selalu berakhir
      `lines.length - 1`. Bukan bug (hasilnya benar), murni loop
      redundan yang bisa dihapus.
    - `_change` clamp `double.maxFinite.toInt()` → `max(0, ...)`
      (`payment_screen.dart:362` & `:1500`).
    - duplikasi validasi hex key — **sekarang 3 tempat, bukan 2**:
      `app_database.dart:4554` (rekey), `app_database.dart:6123`
      (`_openConnection`), `archive_service.dart:50`.

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

