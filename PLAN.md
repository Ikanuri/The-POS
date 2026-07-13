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
bayar) — SELESAI & di-commit. **25c (gerbang lisensi offline) SELESAI &
di-commit** — lihat CHANGELOG & `docs/HANDOFF.md` untuk detail (public
key developer & nomor WA "Kirim via WhatsApp" masih placeholder, gerbang
otomatis nonaktif total sampai keduanya diisi — lihat HANDOFF utk langkah
lanjutannya).
Sisa menggantung: Item 3c, 5, 8, 23 — lihat masing-masing untuk detail._

---

## Konteks — kenapa semua item di bawah ini muncul

User punya dataset toko lama (`docs/reference/Contoh_Dataset.rar`,
`docs/reference/Products.csv`) yang ingin dipindahkan ke The POS: katalog
produk, data pelanggan + poin loyalty, dan riwayat transaksi. Diskusi dimulai
dari 3 pertanyaan (mekanisme update data berkala, dropdown pelanggan tidak
scrollable, bug pencarian nama pelanggan) yang ternyata saling terkait dan
mengarah ke beberapa temuan bug nyata di importer CSV yang sudah ada.

**Prinsip yang disepakati:** Claude TIDAK punya akses berkelanjutan ke
database toko (offline-first, terenkripsi SQLCipher, HP user adalah satu-
satunya sumber kebenaran). Jadi update data dari dataset selalu berbentuk:
user kirim data mentah → Claude olah/format jadi bentuk yang bisa diimpor →
user jalankan import sendiri di app lewat fitur yang sudah ada (atau yang
akan dibangun). Bukan Claude yang menulis langsung ke database terenkripsi.

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
  service.dart` (2×, struk cetak ESC/POS asli — beda dari `_ReceiptPaper`
  di receipt_screen.dart yang SUDAH diperbaiki), `transaksi_tab.dart` (2×,
  tab Laporan → Transaksi), `tx_history_sheet.dart` (3×, riwayat transaksi
  di kasir), `merged_receipt_screen.dart` (nota gabungan).

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

## Item 3 — SEBAGIAN SELESAI (superseded oleh fitur "Import dari Griyo POS")

3a (delimiter `;`, alias header "Produk"/"Kode Produk"/"Grup Produk"/
"Harga Jual"/"Harga Pokok", ID satuan/grup legacy mentah) **SUDAH
DIPERBAIKI** — lihat CHANGELOG `63d0f2d`. 3b (auto-gabung baris nama-sama-
satuan-beda jadi 1 produk multi-satuan) **DITOLAK user** — keputusan final:
import tetap FLAT, counter `sameNameDifferentUnit` menandai kandidat gabung
manual (rasio konversi antar satuan memang tidak ada di CSV Griyo, jadi
auto-gabung berisiko rasio salah/tersembunyi).

**Sisa terbuka (prioritas rendah):** 3c — kolom "Non Stok" dari export
Griyo masih belum dibaca sama sekali oleh `csv_import_service.dart` (semua
produk hasil import selalu `isNonStock: false`). Belum ada laporan dampak
nyata dari user; kerjakan kalau ada keluhan konkret.

---

## Item 4 — Import pelanggan dari Griyo POS (fitur eksperimental, ANALISIS SELESAI — implementasi BELUM dimulai)

**Prioritas:** Siap dikerjakan — sumber data & keputusan besar sudah ada,
tinggal 1-2 keputusan kecil sebelum coding (lihat di bawah).

**Sumber data dianalisis:** `Pelanggan.xlsx` (Griyo POS), 493 baris, 1 sheet.
Kolom: `Pelanggan, Alamat, Telepon, Barcode, Keterangan, Poin, Piutang`.
Semua kolom tersimpan sebagai TEXT di file (termasuk Poin & Piutang yang
seharusnya angka) — parser perlu `double.tryParse`, BUKAN `int.tryParse`,
karena minimal 1 baris Piutang dalam notasi ilmiah (`"1.23745e+06"`) yang
akan gagal-diam-diam-jadi-0 kalau dipakai `int.tryParse`.

**Kecocokan skema `Customers`:** `Pelanggan`→`name`, `Alamat`→`address`,
`Telepon`→`phone`, `Poin`→`loyaltyPoints`, `Keterangan`→`notes` (kosong
semua di file ini). `Barcode` (kartu member) **tidak ada field setara**
di skema `Customers` sekarang — The POS belum punya fitur kartu
member/barcode pelanggan sama sekali; datanya toh nyaris kosong (1/493
baris) jadi kemungkinan besar cukup diabaikan.

**Keputusan yang SUDAH DIJAWAB user:**
1. **Piutang lama dari Griyo (327 pelanggan berpiutang) — TIDAK dibawa.**
   Import nama/alamat/telepon/poin saja, piutang mulai dari nol bersih di
   The POS. (Alasan yang dipertimbangkan: `customers.outstandingDebt` cuma
   cache lama — tab Buku Hutang menghitung fresh dari transaksi asli, jadi
   kalau field itu diisi langsung dari Griyo akan muncul di badge pelanggan
   TAPI TIDAK di Buku Hutang, dua tempat beda angka. User pilih untuk tidak
   membawa data ini sama sekali daripada membuat transaksi tempo pembuka
   sintetis.)
2. **Baris bernama "-" dengan Piutang ~Rp1,2 juta (bucket pelanggan
   umum/tanpa nama Griyo) — DILEWATI**, tidak diimport sebagai pelanggan.

**Sisa keputusan kecil (belum ditanyakan/dijawab eksplisit, ambil default
masuk akal saat implementasi kecuali user koreksi):**
- **17 nama duplikat** (mis. "Bu Ika" 2x) — sudah dicek manual pakai kolom
  Alamat: mayoritas memang orang BEDA (panggilan sama, lazim di kampung).
  Beberapa ambigu (alamat sama-sama kosong/nyaris identik: "Mbak Dwi",
  "Suhar", "Tantowi"). Default: import apa adanya sebagai entri terpisah
  (tidak bisa dibedakan otomatis dari data yang tersedia) — user gabung
  manual via UI kalau ternyata orang yang sama.
- **23 nama dengan whitespace nyasar** (mis. `"Bu Abi "`) — trim saat
  import supaya tidak dianggap beda dari pencarian nama tanpa spasi.
- **Piutang blank (bukan "0")** untuk 166 baris — treat sebagai 0 (tidak
  relevan lagi karena Piutang keputusan #1 di atas: tidak dibawa sama
  sekali).

**File yang kemungkinan terlibat:** file BARU, kemungkinan
`lib/core/services/customer_import_service.dart` (pola sama seperti
`csv_import_service.dart`, tapi untuk `.xlsx` bukan `.csv` — perlu cek
package excel yang sudah dipakai project, lihat §Stack di CLAUDE.md).
UI: entry baru di Pengaturan → Eksperimental (pola sama seperti "Import
dari Griyo POS" produk).

**Gotcha wajib diwariskan dari bug import produk (Item terbaru, `e4baa92`):**
`ProductUnitsCompanion` yang dibuat importer HARUS eksplisit set field yang
constraint lain di app diam-diam mengasumsikan ada nilainya (kasus produk:
`isBaseUnit`) — kalau ada pola serupa di `Customers`/relasi terkait
(mis. field yang beberapa layar UI baca dengan fallback tapi ada SATU layar
yang tidak), cek dulu SEMUA titik baca sebelum importer selesai, jangan
cuma tes "tab pelanggan muncul" lalu anggap beres.

---

## Item 5 — Import riwayat transaksi dari dataset lama (fitur baru + jadi data stress-test nyata)

**Prioritas:** Setelah Item 3 selesai (lihat alasan ketergantungan di
3b — bug dedup importer di Item 2 sudah selesai dikerjakan, lihat
CHANGELOG). User sudah konfirmasi punya beberapa file rentang tanggal (bukan cuma
satu hari), tapi **belum diketahui apakah cakupannya mendekati riwayat penuh
toko (Maret 2024–sekarang, sesuai rekap bulanan di file `Penjualan`) atau
cuma beberapa sampel** — perlu dikonfirmasi user sebelum estimasi skala
pekerjaan pencocokan produk final dibuat.

**Konteks penemuan:** User awalnya bertanya kenapa hasil ekstraksi riwayat
transaksi dulu membuat struk kosong (cuma nominal, tanpa rincian item).

**Root cause struk kosong (dikonfirmasi):** File `docs/reference/.../
Penjualan <rentang>.xlsx` yang tersedia adalah **rekap agregat BULANAN**
(kolom: Bulan, Penjualan, Transaksi, Item, Diskon, Biaya admin, Laba) — satu
baris = satu bulan, TIDAK ADA nama produk atau rincian item sama sekali di
file ini. Kalau file inilah yang dulu dipakai sebagai sumber import
transaksi, struk pasti kosong rinciannya karena informasinya sendiri sudah
tidak ada di sumbernya (bukan bug proses import).

**Kabar baik — ditemukan file lain yang jauh lebih detail:** file
`Transaksi <rentang-tanggal>.xlsx` (contoh yang sudah dicek:
`Transaksi 2026-06-10_2026-06-11 2026-06-10.xlsx`) punya struktur PER
TRANSAKSI dengan kolom:
```
Tanggal | ID | Pelanggan | Subtotal | Diskon | Total | Pembayaran |
Biaya admin | Laba | Poin | Pegawai | Catatan Internal | Catatan Struk | Rincian
```
Kolom **"Rincian"** berisi rincian item sebagai teks bebas, format
`NamaProduk:Qty` dipisah baris baru (`\n`) di dalam satu sel, contoh:
```
Minyak Filma:1
Intermie:5
Power F:1
Golda:4
...
```
(Nota #13164 milik "Mbak Ima" — nama yang sama dengan kasus pencarian di
Item 1, ditemukan langsung sebagai bukti nyata di dataset ini.)

**Kenapa item ini bernilai ganda:**
1. Mengembalikan rincian struk yang hilang (tujuan awal).
2. Karena ini data transaksi ASLI (bukan dummy/buatan), begitu masuk
   database ini otomatis jadi uji beban NYATA untuk seluruh aplikasi:
   pencarian riwayat transaksi, laporan, kartu poin pelanggan, performa
   daftar (grid/list) — semuanya teruji dengan volume & pola yang benar-
   benar terjadi di toko user, bukan skenario buatan yang bisa saja meleset
   dari kondisi sesungguhnya.

**Ketergantungan (urutan tidak boleh dibalik):** HARUS dikerjakan setelah
Item 3 terutama 3b (fix rasio multi-satuan) selesai. Alasan: pencocokan
nama produk di kolom "Rincian" bergantung penuh pada katalog yang sudah
lengkap & berstruktur benar. Kalau strukturnya kacau (Item 3b — "Sedap
Goreng" jadi banyak entitas tak berhubungan), baris rincian transaksi yang
menyebut produk itu otomatis ikut gagal/salah cocok juga — bug akan menumpuk
kalau urutan pengerjaan dibalik.

**Risiko/keputusan yang perlu diantisipasi saat implementasi (belum
diputuskan):**
- Nama produk di "Rincian" bisa ambigu kalau produk itu ternyata punya
  beberapa satuan/varian dengan nama sama (persis kasus "Sedap Goreng" per
  dus vs per biji). Perlu aturan: default ke satuan dasar? Tandai untuk
  direview manual kalau ambigu?
- Baris item yang nama produknya sama sekali tidak ketemu di katalog
  (produk sudah dihapus/berganti nama sejak transaksi itu terjadi asli) —
  dilewati dengan catatan, atau dibuat "produk tak dikenal" sebagai
  placeholder?
- Kolom "Poin" di file — direkonstruksi ke ledger poin pelanggan juga, atau
  cukup catatan transaksinya saja tanpa menyentuh poin (untuk menghindari
  dobel-hitung kalau poin di app sekarang sudah berbeda dari saat itu)?
- Ini akan jadi jalur "import transaksi" PERTAMA di aplikasi — pekerjaan
  baru dari nol, bukan modifikasi importer yang sudah ada.

**File yang kemungkinan terlibat (belum pasti):** file BARU, kemungkinan
`lib/core/services/transaction_import_service.dart`. Perlu menulis ke
`transactions`, `transaction_items`, kemungkinan `loyalty_point_ledger`.

---

## Item 8 — Bawa UI/UX "pilih harga" modal ItemEntrySheet ke halaman HTML (didiskusikan, BELUM diputuskan)

**Status:** Masih tahap diskusi kelayakan — user bertanya "bisakah", belum
ada keputusan scope final. Dicatat supaya tidak hilang dari radar.

**Ide:** modal `ItemEntrySheet` di tab Kasir (tap badan produk) sudah punya
UI pilih harga yang cukup kaya: chip horizontal untuk satuan + tier grosir +
harga alternatif (`_PriceChip`), qty stepper, dst. User bertanya apakah UI/UX
serupa ini bisa juga ditambahkan ke halaman HTML Katalog Pesanan (yang saat
ini pemilihan varian di HTML masih pakai `<details>` dropdown sederhana +
stepper polos, tanpa konsep "harga lain"/tier grosir sama sekali).

**Trade-off yang perlu dipertimbangkan sebelum lanjut (belum final,
menunggu keputusan user):**
- **Kompleksitas vs manfaat:** HTML katalog ini sengaja dibuat SEDERHANA
  (statis, tanpa framework, tanpa build step) supaya tetap ringan & mudah
  dirawat sebagai satu file. Menambahkan sistem "harga lain"/tier grosir ke
  sana berarti duplikasi LOGIKA price-resolving (`PriceService`) ke JS
  murni — dua tempat yang harus dijaga tetap sinkron kalau logika harga
  berubah di masa depan.
  - **Kaitan dengan optimasi performa HTML yang sudah dikerjakan** (debounce
    cari, update per-baris, dll — lihat CHANGELOG): semakin banyak
    UI/interaktivitas ditambahkan ke HTML ini, semakin besar risiko masalah
    performa serupa muncul lagi di tempat baru — perlu diperhatikan bareng,
    bukan ditambah dulu baru dioptimasi belakangan.
- **Relevansi ke pelanggan vs ke kasir:** tier grosir/harga alternatif itu
  fitur yang biasanya dipakai KASIR/OWNER untuk situasi tawar-menawar
  khusus, bukan sesuatu yang biasanya perlu dipilih PELANGGAN sendiri saat
  memesan dari HP-nya. Perlu dipikirkan: apakah relevan pelanggan melihat/
  memilih opsi harga alternatif sendiri, atau ini cuma perlu tetap jadi
  keputusan kasir saat pesanan diproses di tab Kasir (lewat "Tempel
  Pesanan")?
- **Menunggu keputusan user** sebelum ada rencana teknis lebih rinci.

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

## Status ringkas & urutan sisa pekerjaan

**Item 9-22 (backlog audit besar 10-11 Juli) — SELESAI 12/13**, lihat
CHANGELOG untuk hash tiap item. Sisa satu: **Item 17+21 (sync)** — lihat
detail lengkap di atas, sengaja ditunda ke sesi fokus (risiko data-loss di
"majukan watermark upload" butuh test round-trip HTTP asli).

**Item lain yang masih terbuka:**
1. **Item 4** (import pelanggan Griyo) — analisis + keputusan besar SELESAI,
   siap diimplementasikan (lihat detail di atas).
2. **Item 3c** (kolom "Non Stok" diabaikan importer produk) — prioritas
   rendah, tunggu keluhan konkret.
3. **Item 5** (import riwayat transaksi dari dataset lama) — perlu
   konfirmasi user soal cakupan tanggal file `Transaksi ...xlsx` sebelum
   mulai; dependensi ke Item 3b (rasio multi-satuan) sekarang longgar
   karena user sudah memilih flat-import tanpa auto-gabung.
4. **Item 8** (bawa UI pilih-harga ke katalog HTML) — masih tahap diskusi
   kelayakan, menunggu keputusan user soal trade-off kompleksitas.
