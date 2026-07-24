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

## Item 38 — Tie-break `_rawBaseStock` tidak kronologis kalau 2 perubahan stok jatuh di detik yang sama (ditemukan tak sengaja, belum ada laporan dampak nyata)

**Prioritas:** Rendah — ditemukan lewat test Item 36 (stock opname), BUKAN
laporan bug user. Belum ada bukti ini pernah kejadian di device asli.

**Detail:** `AppDatabase._rawBaseStock()` (dipakai `currentStock`/
`adjustStock`/`commitOpname`) mengambil baris `stock_ledger` terbaru via
`ORDER BY created_at DESC, id DESC LIMIT 1`. Kolom `created_at` disimpan
dgn presisi DETIK (bukan milidetik), dan `id` adalah UUID v4 ACAK — kalau
dua perubahan stok (mis. "Atur Stok" manual lalu langsung "Stock Opname",
atau dua penyesuaian cepat berurutan) jatuh di detik yang SAMA PERSIS, tie-
break `id DESC` bisa memilih baris yang SALAH (UUID acak tidak berkorelasi
dgn urutan insert), sehingga stok yang terbaca bisa jadi versi yang lebih
lama, bukan yang paling akhir ditulis. Baru KETAHUAN karena test otomatis
Item 36 (`test/stock_opname_test.dart`) menjalankan 2 penulisan stok tanpa
jeda & hasilnya salah — di device asli kemungkinan sangat jarang kejadian
(perubahan stok manual biasanya berjarak lebih dari 1 detik antar aksi).

**Kemungkinan fix (belum dikerjakan):** tambah kolom sequence/`rowid`
auto-increment murni sbg tie-break kedua (SQLite `rowid` built-in bisa
dipakai via `ORDER BY created_at DESC, rowid DESC` tanpa migrasi kolom
baru), ATAU naikkan presisi `created_at` ke milidetik. Perlu diverifikasi
mana yang lebih murah sebelum dieksekusi.

---

## Item 32 — Barcode scanner eksternal kurang responsif (kode SUDAH di-fix, tunggu konfirmasi user)

Debounce anti-echo scanner eksternal diturunkan 300ms→150ms (`839a29c`,
lihat CHANGELOG). **TIDAK BISA diverifikasi otomatis** (perilaku echo
hardware scanner sungguhan tidak bisa disimulasikan widget test) — WAJIB
user coba langsung di device asli dgn scanner fisiknya: (a) scan dobel
cepat yg disengaja sekarang berhasil dobel, (b) tidak muncul balik gejala
echo lama. Kalau (b) muncul, 150ms masih kurang tinggi utk scanner user —
perlu naik sedikit, bukan bukti keputusan salah arah. **Belum ada
konfirmasi hasil tes user** — tanyakan kalau sesi depan lanjut.

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
3. **[P2] D.1 sisa — uji printer Bluetooth di device fisik Android
   10/11.** Manifest sudah dirapikan (maxSdkVersion=30 utk izin legacy;
   ACCESS_FINE_LOCATION sengaja TIDAK diminta karena app hanya membaca
   bonded list, bukan discovery scan). Verifikasi di HP Android ≤11
   sungguhan bahwa daftar printer tetap muncul.
4. **[P2] `sync_upload_queue` (antrian sync transaksi/dll, BEDA dari
   antrian usulan produk yang sudah diperbaiki 24 Juli) masih dikunci
   per-IP mentah** (`enqueueSyncUpload`/`AppDatabase.dart`) — bug yang
   SAMA (device beda kebetulan IP sama dari hotspot HP kecil bisa saling
   menimpa antrian) berpotensi terjadi di sini juga, belum diverifikasi/
   diperbaiki krn butuh migrasi skema (`sync_upload_queue` tabel
   persisten, beda dari `_pendingProposals` yang murni in-memory) di
   sandbox yang codegen Drift-nya rusak (lihat gotcha `app_database.g.dart`
   di CLAUDE.md). Fix-nya sama: tambah kolom `device_code`, kunci slot
   preferensi itu drpd `from_ip` (pola sama persis spt
   `PendingProductProposal.slotKey`).

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
12. **D.4 CLAUDE.md basi** — tertulis `schemaVersion = 9`, kode 16.
13. **D.5 terkunci di Flutter 3.24.5 (pin CI)** — di 3.44.6 stable gagal
    kompilasi: 1 error `CardTheme`→`CardThemeData` (`app_theme.dart:175`)
    + 53 deprecation (`withOpacity`, `DropdownButtonFormField.value`,
    `onReorder`). Rencanakan sesi upgrade SDK khusus (fix serentak +
    full test + uji APK device fisik).
14. **E — clean code**: pecah bertahap file raksasa (`kasir_screen.dart`
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
5. **Item 38** (tie-break `_rawBaseStock` tidak kronologis kalau 2
   perubahan stok jatuh di detik yang sama) — prioritas rendah, ditemukan
   tak sengaja lewat test, belum ada laporan dampak nyata di device asli.
6. **Item 32** (debounce scanner eksternal) — tunggu konfirmasi user tes
   device fisik.
7. **Item 41** (audit kode 18 Juli) — mayoritas P1/P2 SUDAH dieksekusi
   di sesi yang sama (lihat CHANGELOG). Sisa: B.1 rotasi storeKey (butuh
   keputusan desain user), C.2 (gabung Item 17+21), uji printer device
   fisik Android ≤11, dan daftar P3 — detail di Item 41 di atas.
8. **Item 51** (usulan section "Disiplin Rilis Profesional" di CLAUDE.md)
   — nunggu keputusan final user (tambah apa adanya / pangkas / pisah ke
   file terpisah). Detail opini di Item 51 di atas.
