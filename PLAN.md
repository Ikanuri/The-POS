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
`5c9de7f`) — lihat CHANGELOG untuk detail teknis._

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

**STATUS: DIPENDING sementara** bareng Item 5 — lihat catatan status di
Item 5 (migrasi user ternyata cakup lebih dari transaksi+pelanggan,
termasuk produk dll., scope penuh belum dirinci). Analisis di bawah ini
tetap valid & siap dipakai begitu user re-konfirmasi & minta lanjut.

**Prioritas (kalau nanti dilanjutkan):** Siap dikerjakan — sumber data &
keputusan besar sudah ada, tinggal 1-2 keputusan kecil sebelum coding
(lihat di bawah).

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

**STATUS: DIPENDING sementara** (keputusan user) — migrasi data user
ternyata BUKAN cuma transaksi + pelanggan (Item 4/5), tapi juga mencakup
aspek lain (mis. produk, dll — belum dirinci detailnya). Daripada
implementasi Item 4/5 dulu sebagian lalu ternyata perlu dirombak begitu
scope penuh migrasi diketahui, **seluruh inisiatif migrasi data
(Item 3c, 4, 5, dan kemungkinan item baru terkait produk) ditahan
dulu** — user minta prioritaskan eksekusi item lain yang sudah matang
(29/30/31/32/33) duluan. Jangan mulai Item 4/5 sebelum user re-konfirmasi
scope migrasi lengkap & bilang siap lanjut.

**Prioritas (kalau nanti dilanjutkan):** Setelah Item 3 selesai (lihat
alasan ketergantungan di 3b — bug dedup importer di Item 2 sudah selesai
dikerjakan, lihat CHANGELOG).

**DIKONFIRMASI user (menjawab pertanyaan cakupan yang sebelumnya
menggantung):** user punya **riwayat transaksi PENUH dari tahun lalu**,
format `.xlsx`, **dibagi per bulan** (sengaja dipecah gitu oleh user krn
khawatir file besar bikin crash saat diproses) — jadi bukan cuma
beberapa sampel, tapi mendekati cakupan riwayat penuh yang diperkirakan
sebelumnya. Siap diestimasi skala pekerjaannya & mulai diimplementasi
kapan saja — tidak ada lagi pertanyaan menggantung soal cakupan data.
(Konsekuensi teknis: importer harus bisa proses BANYAK file bulanan
berurutan sbg satu batch/sesi import, bukan cuma 1 file sekali jalan —
perlu dipikirkan UI multi-file upload atau proses berurutan.)

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

## Item 41 — Audit kode menyeluruh (18 Juli 2026) — temuan menunggu keputusan/eksekusi

Sesi audit baca-kode penuh (tanpa perubahan kode): clean code, bug/silent
bug, keamanan, kompatibilitas, performa/daya. Prioritas ditandai **[P1]**
(berisiko data/uang), **[P2]** (patut segera), **[P3]** (nice-to-have).
Catatan: Flutter SDK tidak tersedia di environment sesi ini, jadi
`flutter analyze`/`flutter test` TIDAK dijalankan — semua temuan dari
pembacaan kode.

### A. Bug & silent bug

1. **[P1] Stok multi-device korup diam-diam setelah sync.** `stock_ledger`
   memakai rantai `stock_after` (saldo = baris terakhir), tapi merge sync
   (`approveSync`/`mergeRows` INSERT OR IGNORE) menyisipkan baris ledger
   device lain yang `stock_after`-nya dihitung dari saldo LOKAL device itu
   — tidak pernah direkonsiliasi ulang (beda dari transaksi yang punya
   `reconcileTransactionsByIds`). Contoh: host stok 10, klien (yang tahu
   stok 5) jual 2 → baris klien `stock_after=3`; setelah merge, baris
   klien jadi "terbaru" → host membaca stok 3, bukan 8. Perlu langkah
   rebuild saldo (recompute `stock_after` kronologis per unit, atau ganti
   sumber kebenaran ke `SUM(qty_change)`) setiap selesai merge kategori
   Stok. Terkait tapi BEDA dari Item 38 (tie-break detik yang sama).
2. **[P1] Zona waktu watermark sync.** `syncToHost` mengirim
   `since` = `DateTime.toIso8601String()` **waktu lokal tanpa offset**;
   host mem-parse dengan `DateTime.parse` → ditafsirkan pada zona waktu
   HOST. Kalau dua HP beda zona (WIB/WITA/WIT nyata di Indonesia, atau
   salah setel zona), `dumpSince` host bisa **melewatkan data hingga
   selisih jamnya** (klien WITA + host WIB → 1 jam data host tidak pernah
   terkirim) atau dump berlebih. Fix: selalu `toUtc().toIso8601String()`
   di kedua arah + parse `DateTime.parse(...).toLocal()` konsisten
   (perhatikan juga watermark tersimpan `last_sync_download_at`).
3. **[P2] Antrian approval host tak berbatas di RAM.**
   `_pendingQueue`/`_pendingProposals` menampung SELURUH payload
   (full-dump riwayat, hingga 50 MB per item) di memori; klien yang
   nge-sync berulang sebelum owner sempat approve menumpuk banyak salinan
   → OOM realistis di HP RAM 1–2 GB. Minimal: tolak/timpa item pending
   dari IP+device yang sama (satu slot per klien), atau persist antrian ke
   DB (sekalian membuka jalan Item 17+21 watermark upload).
4. **[P2] Puncak memori sync boros ~4× payload.** HMAC dihitung atas
   `base64Encode(bodyBytes)` (string 1,33×) lalu `utf8.encode` lagi, plus
   `request.read().expand().toList()` membangun `List<int>` per-byte.
   Payload 50 MB → puncak >180 MB. Hitung HMAC langsung atas bytes mentah
   (ubah kedua sisi serentak — ini breaking change protokol antar versi
   app!) atau minimal atas bytes tanpa base64, dan pakai `BytesBuilder`.
5. **[P2] `DbExportService.decrypt`: password salah bisa melempar error
   mentah.** Hanya `decryptBytes` yang dibungkus try/catch; padding CBC
   kebetulan valid (~1/256 percobaan) membuat `GZipCodec().decode` /
   `utf8.decode` / `jsonDecode` melempar `FormatException` polos ke UI,
   bukan `BackupException('Password salah atau file rusak')`. Perluas
   try/catch sampai `jsonDecode`.
6. **[P2] Recovery identitas: keystore gagal SETELAH migrasi = data
   "hilang".** `DeviceNotifier.load`: fallback ke SharedPreferences hanya
   menolong bila salinan legacy masih ada, padahal `_persist` menghapus
   salinan itu. Device yang keystore-nya mendadak error (kasus nyata
   Transsion/Infinix) akan tampak belum setup → user bisa "Setup Toko
   Baru" → storeKey baru → DB lama permanen tak terbuka. Simpan flag
   non-rahasia `was_configured` di prefs; kalau flag ada tapi storeKey
   gagal dibaca, tampilkan layar error/retry, JANGAN jatuh ke /setup.
7. **[P3] `ThousandsSeparatorFormatter.parseValue` pakai `int.parse`** —
   input >19 digit (field tanpa `maxLength`, mis. dialog Ubah Total)
   melempar `FormatException` tak tertangani. Ganti `int.tryParse` +
   clamp.
8. **[P3] Redirect router tidak reaktif.** `routerProvider` memakai
   `ref.read` tanpa `refreshListenable`/`ref.watch` — perubahan state
   lisensi (mis. hasil `_checkRevocation` async) atau device TIDAK
   memicu redirect sampai user kebetulan navigasi. Kalau perilaku "kunci
   baru berlaku saat navigasi" memang disengaja, dokumentasikan; kalau
   tidak, pakai `refreshListenable` (Listenable dari kedua provider).
9. **[P3] `beforeOpen` menyisipkan `unitTypes` dengan `insertOrReplace`**
   padahal komentarnya bilang insertOrIgnore — menimpa nama unit type
   setiap app dibuka. Hari ini tak ada UI edit unit type jadi tak
   terasa; jadi bom waktu begitu fitur edit satuan muncul. Samakan dengan
   `_seedDefaults` (insertOrIgnore) atau perbaiki komentar + sadari
   konsekuensinya.
10. **[P3] Master data tanpa tombstone.** Penghapusan produk / tier /
    barcode / pelanggan di owner tidak pernah menghapus baris di klien
    (merge = INSERT OR REPLACE saja) → data hantu menumpuk di device
    kasir/asisten selamanya (tier lama bisa ikut kepakai lagi lewat
    dedup (unit,min_qty) — sebagian tertolong, sisanya tidak). Butuh
    keputusan desain: soft-delete (`is_active`/`deleted_at` yang ikut
    tersinkron) vs tabel tombstone.
11. **[P3] `mergeRows` menghitung "diterima N" dari nilai balik
    `customInsert`** — untuk INSERT OR IGNORE yang ter-skip, nilai balik
    (rowid terakhir) tetap bisa >0 → angka "diterima" di UI bisa
    overcount. Kosmetik, tapi menyesatkan saat debugging sync.
12. **[P3] Tutup buku: crash di antara copy-arsip dan delete-data**
    meninggalkan state nyangkut — file `archive_YYYY.db` sudah ada
    (percobaan ulang ditolak "Arsip tahun X sudah ada") padahal data
    belum dihapus dari DB utama. Sediakan jalur pemulihan (deteksi arsip
    tanpa manifest → tawarkan hapus/lanjutkan).

### B. Keamanan

1. **[P1] QR pairing memuat `store_key` master polos.** Siapa pun yang
   memotret layar QR pairing mendapat storeKey permanen = bisa menurunkan
   kunci SQLCipher DB & kunci sync selamanya. Expiry 5 menit hanya dicek
   di sisi klien (payload tidak ditandatangani), dan TIDAK ada mekanisme
   un-pair/rotasi storeKey untuk mencabut device (mis. HP kasir hilang /
   pegawai keluar). Minimal: dokumentasikan risiko + rencana fitur
   "rotasi kunci toko" (rekey DB + re-pair semua device).
2. **[P2] Respons host sync terenkripsi tapi TIDAK di-HMAC** (arah
   request sudah encrypt-then-MAC, arah response belum) — active MITM di
   LAN bisa men-tamper/replay respons. Dikombinasikan dengan (3) di bawah
   jadi rantai yang patut ditutup: tambahkan header HMAC yang sama di
   respons + verifikasi di klien (kompatibilitas mundur: klien lama
   abaikan header baru).
3. **[P2] Klien menerima nama tabel APA PUN dari respons host.**
   `syncToHost` → `db.mergeRows(entry.key, ...)` tanpa allowlist (host
   punya guard `appendOnlyTables`, klien tidak), dan nama tabel/kolom
   disisipkan ke SQL sebagai identifier `"$name"` tanpa sanitasi kutip.
   Praktis butuh kunci enkripsi utk dieksploitasi, tapi ini
   defense-in-depth murah: allowlist tabel di sisi klien + tolak
   identifier ber-karakter di luar `[a-z0-9_]`.
4. **[P2] Crash log ditulis ke folder Downloads PUBLIK** (`CrashLogWriter`
   via MediaStore) — pesan exception bisa memuat data sensitif (IP, isi
   SQL/data saat error). Bisa dibaca siapa pun yang pegang HP & app lain
   ber-izin storage. Pertimbangkan: redaksi/potong pesan, atau tetap di
   folder privat + tombol "Bagikan log" eksplisit dari dalam app.
5. **[P3] Backup `.berkahpos` AES-CBC tanpa MAC** (integritas tak
   terjamin, hanya "gagal gzip"), BPOSP legacy salt statis (baca-saja,
   sudah oke), dan TIDAK ada aturan panjang/kekuatan password — padahal
   BPOT1 memuat storeKey, kekuatannya = kekuatan password user (210k
   PBKDF2 membantu tapi password 4 digit tetap tembus). Minimal wajibkan
   panjang ≥8 di UI ekspor.
6. **[P3] Peta lockout brute-force tidak pernah dibersihkan** —
   `_lockoutUntil[ip]` entri kadaluarsa menetap sampai `stopHost`; bocor
   memori kecil di sesi host panjang. Sekalian: role kasir/asisten adalah
   batas UI, BUKAN batas keamanan (semua device pegang storeKey + full
   DB) — patut ditulis eksplisit di dokumentasi ancaman.
7. **[P3] `minifyEnabled=false`** — APK gampang di-decompile/patch
   (termasuk mem-bypass gerbang lisensi client-side dengan repack;
   inheren tak bisa dicegah total, minify+obfuscation cuma menaikkan
   biaya). Ukuran APK juga membengkak. Coba aktifkan R8 + aturan keep
   utk plugin (perlu uji regresi penuh, terutama drift/sqlcipher/BT).
8. **[P3] `HttpCloudflareApi` tanpa timeout** (connect/response) — beda
   dari LAN sync yang sudah rapi timeout-nya; jaringan buruk = UI publish
   menggantung lama. Tambah `connectionTimeout` + `.timeout()`.

### C. Performa & konsumsi daya

Kabar baik: TIDAK ditemukan sumber "hunger power" klasik — tidak ada
`Timer.periodic`/polling liar, tidak ada wakelock, font sudah bundel
lokal, satu-satunya network background = cek revoked 3 detik saat
startup. Konsumsi daya nyata datang dari pemakaian normal (kamera
scanner, Bluetooth print, layar). Yang patut dibenahi:

1. **[P2] `PRAGMA cache_size = -65536` (64 MB) + `mmap_size` 256 MB per
   koneksi** — agresif utk HP target (RAM 1–2 GB, banyak 32-bit).
   Cache 64 MB itu heap SQLCipher murni; di device sempit malah memicu
   LMK/OOM-kill (app "tiba-tiba tertutup"). Pertimbangkan 8–16 MB cache
   + mmap 64–128 MB; benchmark di device lambat sebelum/sesudah.
2. **[P2] Upload klien→host selalu full-dump sejak epoch** (sengaja,
   karena antrian host in-memory — lihat A.3). Biaya CPU (PBKDF2 2×,
   AES, HMAC, base64) + RAM + waktu transfer tumbuh tanpa batas seiring
   umur toko. Solusi struktural satu paket dengan Item 17+21: persist
   antrian approval → watermark upload aman dimajukan.
3. **[P3] `SystemChrome.setSystemUIOverlayStyle` dipanggil di
   `MaterialApp.builder`** (tiap rebuild) — murah tapi gratis dihindari
   (panggil hanya saat brightness berubah). Sekalian: `ref.watch`
   di dalam closure `builder` (fontScaleProvider) adalah anti-pattern
   riverpod — pindahkan watch ke method `build` ThePosApp.
4. **[P3] `generateUniqueLocalId` memuat semua transaksi hari ini** tiap
   penjualan (SELECT semua baris LIKE prefix) — aman utk skala toko
   sekarang; kalau mau rapi, `SELECT MAX(local_id)` + fallback.

### D. Kompatibilitas

1. **[P2] Izin Bluetooth legacy:** `BLUETOOTH`/`BLUETOOTH_ADMIN` tanpa
   `android:maxSdkVersion="30"`, dan TIDAK ada `ACCESS_FINE_LOCATION` —
   di Android 10–11 discovery/scan Bluetooth butuh izin lokasi. Kalau
   `print_bluetooth_thermal` hanya menampilkan bonded devices, aman;
   kalau ternyata ada jalur scan, di HP Android ≤11 daftar printer bisa
   kosong DIAM-DIAM. Uji di device Android 10/11 fisik.
2. **[P3] Sync LAN memakai HTTP cleartext via `dart:io` HttpClient** —
   kebetulan TIDAK terkena blokir cleartext Android 9+ (network security
   config hanya mengikat stack Java). Kalau suatu saat migrasi ke package
   `http`/cronet, sync akan mendadak gagal tanpa `usesCleartextTraffic`.
   Catat di CLAUDE.md sebagai gotcha.
3. **[P3] Java 8 tanpa core library desugaring** — beberapa plugin versi
   baru mensyaratkan desugaring; potensi build mendadak gagal saat
   upgrade dependency.
4. **[P3] CLAUDE.md basi:** tertulis `schemaVersion = 9`, kode sudah 16.
   (Perbaiki saat menyentuh CLAUDE.md berikutnya.)

### E. Clean code

1. File raksasa: `kasir_screen.dart` 3.739 baris, `app_database.dart`
   3.420, `receipt_screen.dart` 2.694 — pecah bertahap (mis. mixin/bagian
   query DB per domain) saat menyentuh area itu, jangan big-bang.
2. `LanSyncService` full-static + callback tunggal (`onQueueChanged`,
   `onProposalsChanged`) — kalau nanti ada 2 listener (mis. badge +
   layar), yang satu menimpa yang lain diam-diam. Pertimbangkan
   `ChangeNotifier`/stream.
3. `discount_allocation.dart`: loop pencari `lastQtyIdx` mati — `lines`
   sudah difilter `eq > 0`, jadi selalu = index terakhir; sederhanakan.
4. `payment_screen.dart` `_change`: `clamp(0, double.maxFinite.toInt())`
   → cukup `max(0, _paid - _total)`.
5. Duplikasi validasi hex key (`rekey` vs `_openConnection`) → satu
   helper.

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
4. **Item 23 sisa** (`printer_service.dart` `printReceipt` tunggal,
   `transaksi_tab.dart`, `tx_history_sheet.dart`, `settleMergedDebt`, Buku
   Hutang, Tutup Kasir "kas sistem" overstated) — belum disentuh, lihat
   detail Item 23 di atas.
5. **Item 38** (tie-break `_rawBaseStock` tidak kronologis kalau 2
   perubahan stok jatuh di detik yang sama) — prioritas rendah, ditemukan
   tak sengaja lewat test, belum ada laporan dampak nyata di device asli.
6. **Item 41** (audit kode menyeluruh 18 Juli — daftar temuan A–E di
   atas) — BELUM ada yang dieksekusi; mulai dari yang bertanda [P1]
   (stok korup pasca-sync, zona waktu watermark, storeKey di QR pairing).
