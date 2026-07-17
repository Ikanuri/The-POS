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
masih sebatas konsep, belum didesain detail. **Item 29/30/31 BARU** (16
Juli, dari sesi diskusi stok minus & tutup buku): semua sudah didesain
lengkap & siap dikerjakan (30(b) mockup di-approve, 30(c) chart+tabel,
31 sekali/tahun tanggal custom). **Item 32 SELESAI** (debounce scanner
150ms, `839a29c` — tinggal user uji manual di device asli). **Item 33
SELESAI & di-commit** (warna aksen toolbar kasir, Varian C dipilih user).
**Item 4/5 (migrasi data) DIPENDING** — user bilang migrasi sebenarnya
cakup lebih dari transaksi+pelanggan (termasuk produk dll., scope belum
dirinci) — ditahan dulu, prioritaskan item lain yang sudah matang duluan.
**Item 35 (fix sinkron harga SKU non-unik) SELESAI & di-commit** (17 Juli)
— sisa cuma opsi "barcode saja" yang opsional._

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

## Item 29 — Katalog HTML: auto-tandai "habis" dari stok riil (bukan cuma flag manual)

**Konteks:** `order_page_service.dart` (`_buildCatalogJson`) sekarang HANYA
pakai `markedOutOfStock` — flag manual "tandai stok habis" yang kasir set
sendiri, TIDAK PERNAH baca stok riil dari `stock_ledger` sama sekali. Kalau
kasir lupa tandai manual, katalog bisa menampilkan produk tersedia padahal
stok sistem sudah 0/minus.

**Usulan user (disetujui, siap dikerjakan):** kalau setting **"Izinkan
Stok Minus" OFF** (`allow_negative_stock` di app_settings), katalog
TAMBAHAN mengecek stok riil per produk — otomatis tandai "habis" kalau
stok base unit ≤ 0, di luar flag manual. Kondisi habis jadi: `markedOutOfStock
== true` ATAU `(!allowNegativeStock && stokRiil <= 0)`. Kalau toggle ON
(toko sengaja jual walau minus/pre-order), auto-check ini DILEWATI — konsisten
dgn kasir yang juga boleh jual minus saat toggle ON.

**Perlu diperhatikan saat implementasi:** query stok riil per produk belum
ada di `order_page_service.dart` — perlu tambah, dan untuk katalog besar
(ratusan produk) harus agregat/JOIN sekali jalan, JANGAN N+1 query per
produk (lihat §Pola Arsitektur CLAUDE.md).

---

## Item 30 — Kontrol stok untuk owner: cek cepat (Ringkasan) + koreksi (Produk) + laporan analitik/audit (Laporan)

**Konteks:** muncul dari diskusi Item 29 — owner butuh cara melihat &
mengontrol stok riil semua produk. **Dikonfirmasi user: TIGA bagian
sekaligus, di TIGA lokasi berbeda** (bukan satu halaman tunggal):

### (a) Cek cepat — kartu ringkas di **Ringkasan Harian**
- Kartu baru (mis. "N produk stok menipis, M habis"), **bisa difilter per
  kategori produk**, isinya **summary semua stok diurut dari yang
  TERTIPIS dulu** (pola sort sama seperti `_lowStockSql`:
  `ORDER BY (stock - min_stock) ASC`, atau stok absolut terkecil kalau
  `min_stock` tidak diisi).
- Bukan full-list di kartu ini — tombol "Lihat semua" sebaiknya
  navigasi/aktifkan filter di (b), BUKAN duplikat UI daftar produk di 2
  tempat.

### (b) Koreksi — dipanggil dari tab **Produk**, tapi layar TERSENDIRI ("Cek Stok")

**Temuan penting (bug UX, bukan salah user):** filter "Stok Menipis" yang
SUDAH ADA (`produk_list_screen.dart`) sekarang **tersembunyi total** kalau
(1) tidak ada produk dgn `min_stock` terisi & di bawah ambang
(`lowStockCount == 0`), DAN/ATAU (2) toko belum punya kategori produk
bernama sama sekali (`if (named.isEmpty) return SizedBox.shrink();` —
seluruh baris chip filter, TERMASUK "Stok Menipis", ikut tidak dirender).
Ini alasan user "belum pernah coba fitur filter stok". Jangan warisi pola
"sembunyi kalau kosong" ini ke fitur baru — kontrol stok harus SELALU
terlihat & bisa diakses terlepas dari kondisi data.

**Revisi arah setelah diskusi (KEPUTUSAN FINAL, bukan lagi checklist manual
ala referensi HTML):** user awalnya minta ditiru dari modul "Stok Kosong"
di `index.html` referensinya (starter kit personal audit keuangan + "stock
opname kecil-kecilan" — istilah user sendiri), TAPI setelah ditelusuri,
modul itu ternyata **checklist manual murni tanpa koneksi stok riil sama
sekali** (karyawan ketik ulang "qty satuan nama" krn tool itu berdiri
sendiri, tanpa database stok sungguhan). User dgn tepat mengoreksi: The POS
**sudah punya stok riil** — jadi TIDAK BOLEH jadi checklist ketik-ulang
manual (poin user: "untuk apa ada stok kalau akhirnya dicek manual juga").

**Desain final yang disepakati:**
1. **Layar baru terpisah** ("Cek Stok" atau serupa) — BUKAN nambah
   checkbox/textarea ke `ProdukListScreen` yang sudah ada. Alasan: list
   Produk sekarang fokus manajemen (cari nama, tap→edit form, kelola
   kategori) — mode "pilih kategori→lihat semua diurut tertipis→
   centang→teks" itu mental model beda (fokus triase), akan saling ganggu
   kalau dicampur ke list yang sama.
2. **Entry point SELALU terlihat di tab Produk** (bukan chip kondisional
   spt sekarang) — mis. ikon AppBar "Cek Stok" atau kartu ringkas
   permanen di atas list ("N produk perlu dicek stoknya").
3. **Di layar baru**: chip kategori (gaya visual sama spt Produk, state
   terpisah) → list produk kategori itu, SELALU urut stok riil tertipis
   dulu (tidak perlu opsi sort lain) → tiap baris tampilkan **angka stok
   riil besar/jelas** (bukan cuma badge kecil) + checkbox.
4. **Centang = 2 hal sekaligus, BUKAN cuma catatan teks**:
   - Langsung `UPDATE markedOutOfStock = true` produk itu di DB (state
     SUNGGUHAN, tersinkron ke device lain, langsung dibaca katalog Item
     29) — visual baris berubah (redup/strip, mirip `.item-card.checked`
     di referensi).
   - SEKALIGUS baris itu ditambahkan ke kotak teks di bawah ("Order
     Restock" — panel sticky/collapsible di bawah list, biar tidak perlu
     scroll jauh) — tombol Salin + share (reuse pola share yg sudah ada
     di app, spt katalog/struk).
   - Uncentang = kebalikannya (flag balik `false`, hilang dari teks).
5. **Tujuan kotak teks DIALIHKAN** dari referensi: di HTML aslinya teks
   itu "lapor ke bos" (perlu krn tool 1-device tanpa server bersama). The
   POS sudah py sync/DB bersama (`markedOutOfStock` toggle sudah ada &
   dipakai dari `item_entry_sheet.dart` di kasir screen — owner OTOMATIS
   lihat perubahan tanpa perlu pesan manual). Jadi kotak teks di sini
   fungsinya **teks order restock ke SUPPLIER** (pihak di LUAR sistem,
   satu-satunya yang genuinely butuh pesan manual) — bukan lagi "lapor ke
   bos" yang sudah redundan.
6. **Reuse untuk Item 30(a)**: tombol "Lihat semua" di kartu ringkas
   Ringkasan (poin a) mengarah ke layar YANG SAMA ini (filter kategori
   dari Ringkasan bisa jadi parameter awal) — satu implementasi, dua
   entry point (Ringkasan & Produk), JANGAN bikin UI daftar stok 2 kali.
7. **Mode Bos (PIN) dari referensi TIDAK PERLU ditiru** — itu solusi
   darurat khusus tool 1-device-tanpa-role. The POS sudah py role asli
   (owner/kasir/asisten via identitas device) — cukup gating pakai itu.
8. `adjustStock` (koreksi ANGKA stok, beda konsep dari flag "habis") TETAP
   dipertahankan sbg fitur terpisah yang sudah ada di `produk_form_screen.dart`
   — tidak berubah, tidak digabung ke layar "Cek Stok" ini.

**Layout SUDAH DI-APPROVE user (sementara)** — mockup dirender via
Playwright (`cek_stok_mockup.html`/`.jpg` di scratchpad sesi ini, tidak
di-commit ke repo), dikirim sbg screenshot & disetujui: chip kategori di
atas, list diurut tertipis dgn badge stok besar berwarna (merah=kritis/
negatif, kuning=menipis, hijau=aman), baris tercentang berubah visual
(border+strip aksen, nama dicoret), panel "Teks Order Restock" sticky di
bawah dgn textarea auto-terisi + tombol Salin & Kirim ke Supplier. Kalau
mockup-nya sudah hilang dari scratchpad (beda sesi), regenerasi dari
deskripsi ini sudah cukup, tidak wajib lihat gambar lama lagi.

### (c) Laporan analitik/audit — tab baru di **Laporan**
- User konfirmasi: dibutuhkan **utk audit**, meski belum ada use case
  real sekarang — tetap dikerjakan.
- **Isi yang diusulkan**:
  1. **Nilai inventori** — Σ(stok riil × harga pokok) per produk, per
     kategori, & grand total. Angka paling actionable utk audit ("modal
     tertahan di rak sekarang").
  2. **Deteksi data tidak lengkap** — hitung & tampilkan berapa produk yg
     harga pokoknya kosong/0 (nilainya jadi TIDAK terhitung di (1) —
     harus ditandai eksplisit spy owner tahu angkanya understated, bukan
     dikira final akurat).
  3. **Daftar stok NEGATIF saat ini** — terhubung ke temuan sesi
     sebelumnya (owner selalu bisa bypass "Izinkan Stok Minus", tidak ada
     pengaman/pencatatan khusus saat itu terjadi) — laporan ini tempat yg
     pas menyorot produk yg stoknya minus SEKARANG sbg sinyal "perlu
     direview" (entah salah input, entah oversell yg disengaja).
  4. **(Opsional, iterasi berikutnya)** — nilai stok per periode Tutup
     Buku (Item 31), begitu Item 31 selesai: catat "nilai stok akhir"
     tiap kali tutup buku, jadi ada jejak historis dari waktu ke waktu.
     BUKAN syarat wajib versi pertama.
- **PENTING (jawaban ke pertanyaan user)**: fitur ini MELENGKAPI stock
  opname fisik, TIDAK MENGGANTIKANNYA. Rajin input stok masuk (kulakan)
  tidak pernah menangkap susut/rusak/hilang/kesalahan hitung/dikasih
  gratis — cuma hitung fisik berkala yang bisa memverifikasi angka
  sistem = kenyataan. Jangan sampai fitur (c) ini dipromosikan sbg
  "pengganti opname" ke user — framing UI-nya harus jujur soal ini kalau
  nanti dibangun (mis. teks kecil pengingat).

**KEPUTUSAN FINAL (c) — dua-duanya**: chart (donut, pola sama spt
breakdown Pengeluaran/Prive di referensi PNL user) UNTUK proporsi
sekilas, PLUS tabel detail di bawahnya utk angka presisi per kategori.
Bukan salah satu saja.

**Belum didesain detail (pertanyaan sebelum coding)**:
- (a): filter kategori di kartu Ringkasan — state terpisah dari filter di
  layar "Cek Stok" (b), atau reuse begitu (b) dibuat?
- Semua bagian: sumber angka stok riil per produk — agregat dari
  `stock_ledger`, pola query sama seperti `_rawBaseStock`/
  `getLowStockProductIds` (`_lowStockSql`) — WAJIB agregat/JOIN sekali
  jalan, JANGAN N+1 per produk (§Pola Arsitektur CLAUDE.md), terutama
  utk (c) yang mencakup SEMUA produk bukan cuma yang menipis.

---

## Item 31 — Tutup Buku: tanggal custom (bukan selalu 1 Januari)

**Konteks:** `TutupBukuService.execute(year)` sekarang HARDCODE periode
kalender Jan 1–Des 31 (`tutup_buku_service.dart:62-63`), UI cuma tampilkan
"Tahun $currentYear" tanpa input tanggal sama sekali.

**Kasus riil user:** tutup buku dilakukan pas **Hari Raya**, yang
tanggalnya BERUBAH tiap tahun (ikut kalender Hijriah, bukan tanggal tetap).
Jadi ini BUKAN sekadar ganti offset "tahun fiskal" tetap (mis. April–Maret
konsisten tiap tahun) — tiap kali mau tutup buku, user pilih tanggal MANUAL
saat itu juga.

**Dikonfirmasi user: tutup buku tetap SEKALI PER TAHUN** — cuma
tanggalnya geser ikut Hari Raya, bukan jadi bebas kapan saja/berkali-kali
setahun. (Belum diputuskan: apakah perlu validasi keras "minimal ~11
bulan dari tutup terakhir", atau cukup dibiarkan tanggung jawab user
tanpa validasi — prioritas rendah, bisa diputuskan pas coding.)

**Saran teknis (setelah baca `tutup_buku_service.dart` — fakta penting:
proses SEKARANG copy SELURUH file `the_pos.db` jadi arsip, lalu HAPUS
data transaksional yg jatuh di rentang tahun itu dari main.db, sisakan
data master, bawa saldo stok terakhir spy tidak ke-reset 0):**

1. **Ganti parameter `year` (int) → periode eksplisit `periodStart`–
   `periodEnd`** (dua `DateTime`). `periodEnd` = tanggal yg dipilih
   manual tiap kali tutup buku (Hari Raya tahun itu). `periodStart` =
   otomatis dari tanggal tutup buku TERAKHIR (setting baru, ganti
   `last_archive_year` jadi `last_archive_date`) — supaya periode
   berikutnya SELALU nyambung pas, tidak ada celah/tumpang tindih.
2. **Tutup buku PERTAMA kali** (belum ada histori) — `periodStart` =
   tanggal transaksi PALING LAMA di database (bukan 1 Januari, bukan
   tanggal setup toko — hindari rentang kosong tak berguna di awal).
3. **Skema penamaan arsip**: `archive_$year.db` (skema sekarang) tidak
   cocok lagi kalau bukan tahun kalender penuh — ganti berbasis tanggal
   `periodEnd` (mis. `archive_20260330.db`).
4. **Perlu "manifest" kecil** (baris di `app_settings` sbg JSON, atau
   tabel baru) yg catat per arsip: tanggal mulai, tanggal akhir, jumlah
   transaksi — supaya daftar arsip di UI tampil jelas ("Arsip: 12 Apr 2025
   – 30 Mar 2026, 1.240 transaksi"), bukan cuma angka tahun polos spt
   sekarang.
5. **UI**: ganti tampilan statis "Tahun $currentYear" jadi info dinamis
   ("Sejak [periodStart], X transaksi belum diarsip") + tombol buka
   date-picker utk pilih `periodEnd` & eksekusi — validasi: tanggal harus
   SETELAH `periodStart`, tidak boleh di masa depan.
6. **Arsip lama** (format `archive_$year.db`, terikat tahun kalender)
   HARUS tetap bisa dibaca/ditampilkan bareng arsip format baru di UI
   daftar arsip — jangan sampai migrasi bikin arsip lama "hilang" dari
   tampilan (`listArchivedYears()` perlu diperluas baca 2 format
   sekaligus, bukan diganti total).

---

## Item 32 — Barcode scanner eksternal kurang responsif saat scan cepat berturut

**Konteks:** user lapor: kadang 2x scan cepat (barcode sama, mis. sengaja
scan dobel utk qty 2) cuma menghasilkan 1 output.

**Akar masalah ditemukan** (`kasir_screen.dart:1126-1135`, `_handleBarcode`):
debounce anti-duplikat utk scanner eksternal (HID) di-set **300ms**
(`debounceMs = fromExternal ? 300 : 1500`) — barcode yang SAMA dalam
rentang 300ms dianggap "echo" hardware & diabaikan begitu saja
(`if (barcode == _lastScan && nowMs - _lastScanMs < debounceMs) return;`).
Kalau scanner user ternyata cukup cepat utk menyelesaikan 2 scan
sungguhan dalam window itu, scan kedua yang genuinely disengaja ikut
ke-drop — sama persis gejala yang dilaporkan.

**Riwayat ditelusuri** (user tidak ingat detail persis, cuma ingat "dulu
kurang responsif, lalu di-fix jadi seperti sekarang"): commit `051357b`
("Kasir: debounce scanner eksternal 300ms + auto-scroll keranjang ke
bawah", 27 Juni) adalah asal-usul angka 300ms ini — deskripsi commit
mengindikasikan 300ms ini DITAMBAHKAN sbg fix anti-duplikat (bukan
diturunkan dari angka lebih tinggi sebelumnya). Jadi memori user "dulu
kurang responsif → di-fix" kemungkinan besar soal pengalaman scan LAIN
(haptik, redesign kapsul, animasi pulse — semua di rentang commit yang
sama), BUKAN soal window 300ms ini spesifik — tidak ada bukti histori
"300ms" pernah diturunkan dari nilai lebih tinggi.

**Keputusan user**: coba turunkan nilainya, krn "butuh kecepatan hampir
real time".

**Rencana**: turunkan `debounceMs` (fromExternal) dari 300ms → **150ms**
(bukan dihapus total — tetap ada anti-echo, cuma window-nya separuh;
150ms juga angka yang sudah dipakai sbg konvensi debounce anti-misclick
lain di app ini, mis. `AddControl`). **TIDAK BISA diverifikasi otomatis**
di lingkungan ini (perilaku echo hardware scanner sungguhan tidak bisa
disimulasikan di widget test) — WAJIB user coba langsung di device asli
dgn scanner fisiknya setelah perubahan, pastikan (a) scan dobel cepat yg
disengaja sekarang berhasil dobel, DAN (b) tidak muncul balik gejala lama
(barcode kepencet dobel sendiri tanpa disengaja/echo hardware). Kalau
(b) muncul, berarti 150ms masih kurang tinggi utk scanner user — perlu
naik sedikit, bukan bukti keputusan ini salah arah.

---

## Item 35 — Sinkron harga antar-toko: opsi "barcode saja" (OPSIONAL, belum dikerjakan)

Bug utama sinkron harga (SKU non-unik salah cocok) **SUDAH DIPERBAIKI &
di-commit** (17 Juli — lihat CHANGELOG/HANDOFF). Sisa yang belum: opsi
"sinkron via barcode saja" untuk toko besar (item tanpa barcode-cocok
langsung dianggap "Baru/lewati", tidak coba SKU/fuzzy). Dibahas tapi
belum diminta dikerjakan — kerjakan kalau user re-konfirmasi butuh.

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
