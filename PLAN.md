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
B.1/C.2/P3 masih menggantung. **Item 42/43/44 BARU (18 Juli) — SEMUA
BELUM dieksekusi, disimpan atas permintaan user**: Item 42 = investigasi
"total pengeluaran tidak sinkron" (root cause SUDAH ketemu, tunggu
konfirmasi user) + filter periode tab Pengeluaran; Item 43 = stepper
angka qty berpindah sisi +/- selagi aktif; Item 44 = tampilkan qty di
kiri item keranjang._

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

## Item 42 — Total pengeluaran "tidak sinkron" antara tab Pengeluaran & Laporan + filter periode (18 Juli, BELUM dieksekusi — user bilang "skip dulu")

**Laporan user**: total pengeluaran di tab Pengeluaran (Pengaturan →
Pengeluaran) tidak cocok/sinkron angkanya. Diminta juga: total pengeluaran
bisa difilter harian/mingguan/bulanan/custom (bandingkan dgn tab Laporan
yang sudah punya date-range picker).

**Root cause SUDAH ditemukan (investigasi selesai, BELUM dikonfirmasi user
krn AskUserQuestion sempat error saat sesi berjalan)**: ada 4 jenis
pengeluaran (`daily_expense`/operasional, `owner_withdrawal`/ambil pribadi
owner, `supplier_payment`/bayar supplier, `change_given`/uang keluar laci
tanpa transaksi):
- `expenses_screen.dart` ("Total bulan ini"): jumlah **SEMUA 4 jenis**,
  rentang **selalu bulan berjalan** (`_thisMonth()`, hardcode, tidak bisa
  diubah/difilter sama sekali).
- `app_database.dart` `getNetProfitExpenseTotal()` (dipakai KPI
  "Pengeluaran" di tab Laporan → Ringkasan, `AppDatabase.
  netProfitExpenseTypes`): cuma **2 dari 4 jenis** (`daily_expense` +
  `change_given`) — `owner_withdrawal`/`supplier_payment` SENGAJA
  dikecualikan (komentar existing: `owner_withdrawal` bukan biaya
  operasional, `supplier_payment` sudah terhitung via `cost_at_sale` di
  HPP — kalau ikut dijumlah di sini akan dobel-hitung pengurang Laba
  Bersih).

Jadi KEDUA angka itu **memang berbeda by design** kapan pun toko pernah
punya transaksi "Ambil Pribadi (Owner)" atau "Bayar Supplier" di periode
yang sama — bukan bug sinkronisasi data/LAN sync, murni beda definisi
"pengeluaran" antara dua layar (satu = seluruh kas keluar, satu = khusus
pengurang Laba Bersih). Tidak ada indikasi duplikasi data dari sync (tabel
`expenses` punya `localId` unique, primary key `id`, `INSERT OR REPLACE`
by id — aman idempotent).

**Rencana (BELUM disetujui detail UI-nya, keputusan cepat diambil sesi ini
tanpa konfirmasi eksplisit user karena tool tanya sempat gagal)**:
tambahkan filter periode (Harian/Mingguan/Bulanan/Custom, pola serupa
`dateRangeProvider`+`showDateRangePicker` di `laporan_screen.dart`) ke
`expenses_screen.dart` — TIDAK mengubah `getNetProfitExpenseTotal`/definisi
Laba Bersih di Laporan (itu logic yang benar & sengaja begitu). Pertanyaan
terbuka yang masih perlu dikonfirmasi user sebelum eksekusi:
1. Filter ditaruh di tab Pengeluaran saja, atau juga perlu cara
   membandingkan/menyelaraskan definisi dengan KPI Laporan?
2. Apakah user setuju root cause di atas (beda definisi 4-jenis vs
   2-jenis) memang penyebabnya, atau ada gejala lain yg belum tertangkap
   (mis. angka beda antar-device setelah sync LAN, bukan cuma beda
   antar-layar)?

**Status: SKIP dulu atas permintaan user — jangan eksekusi sampai user
minta lanjut & jawab 2 pertanyaan di atas.**

## Item 43 — Stepper: angka qty "berpindah" antara tombol +/- (18 Juli, BELUM dieksekusi — "simpan dalam task dulu")

User klarifikasi maksud lanjutan dari fitur "pijakan jempol" (`AddControl.
activeStepper`, `98ab0df`) yang barusan selesai: SELAGI stepper dalam
kondisi "aktif" (membesar & tetap besar), angka qty **berpindah tempat**
tergantung tombol mana yang BARU SAJA ditekan:
- Tap **+** (kanan/main circle) → tombol **+** balik jadi ikon "+" polos;
  **angka qty pindah ke tombol minus (kiri)**.
- Tap **-** (kiri) → tombol **-** balik jadi ikon "-" polos; **angka qty
  pindah ke tombol plus (kanan)**.
- Alasan (dikonfirmasi user, "sepemahaman"): tombol yang BARU ditekan
  biasanya ketutupan jempol sendiri — angka ditampilkan di sisi yang
  TIDAK ketutupan supaya tetap kebaca tanpa mindahin jempol.
- Begitu stepper tidak lagi "aktif" (tap area lain/scroll, via
  `StepperActiveScope` yg sudah ada) → kembali ke tampilan NORMAL: angka
  selalu di tombol **+** (kanan), persis perilaku default saat ini
  (`_AddControlState.build()` — main circle selalu tampilkan qty saat
  `inCart`, minus selalu cuma ikon).

**File terdampak (belum disentuh)**: `lib/features/kasir/widgets/
add_control.dart` — perlu state baru (mis. `_numberOnMinusSide` bool,
di-reset via listener `AddControl.activeStepper` yg sudah ada: begitu
`activeStepper.value != this` → reset ke `false`/normal). Perlu tes
widget baru (tap +/- berurutan, verifikasi lokasi Text qty vs Icon +/-
di kedua circle, plus verifikasi reset ke normal saat `AddControl.
clearActive()`/tap-lain/scroll dipanggil).

**Status: BELUM dieksekusi, disimpan sbg rencana atas permintaan user.**

## Item 44 — Tampilkan qty di kiri item keranjang (18 Juli, BELUM dieksekusi — "simpan dalam task dulu")

User minta: baris item di keranjang (`_CartItemTile`,
`cart_sheet.dart`) tampilkan angka qty JUGA di kiri item (leading),
bukan cuma di stepper kanan. Saat ini `leading` cuma `Checkbox`
verifikasi (`item.checked`) — belum ada indikator qty sama sekali di
sisi kiri.

**File terdampak (belum disentuh)**: `lib/features/kasir/widgets/
cart_sheet.dart` `_CartItemTile` (baris ~291-301, `leading: Checkbox(...)`)
— perlu desain kecil: badge/teks qty ditaruh di mana persis relatif
terhadap Checkbox (di samping? menggantikan sebagian ruang leading yg
sekarang cuma checkbox tunggal — `ListTile.leading` biasanya 1 widget,
perlu dibungkus `Row`/`Column` kalau mau checkbox+badge qty sekaligus).
Perlu tes widget baru (qty tampil benar di kiri utk item qty>1 & qty
desimal spt 0.25 — ingat gotcha `formatRupiah`/tampilan desimal yg
sudah beberapa kali jadi sumber bug di app ini).

**Status: BELUM dieksekusi, disimpan sbg rencana atas permintaan user.**

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

### Sisa [P3]

1. **A.8 redirect router tidak reaktif** — `ref.read` tanpa
   `refreshListenable`: perubahan state lisensi async tidak memicu
   redirect sampai navigasi berikutnya. Dokumentasikan atau pasang
   Listenable gabungan.
2. **A.9 `beforeOpen` unitTypes pakai `insertOrReplace`** padahal
   komentar bilang insertOrIgnore — bom waktu kalau kelak ada UI edit
   satuan; samakan dgn `_seedDefaults`.
3. **A.10 master data tanpa tombstone** — penghapusan produk/tier/
   pelanggan di owner tidak pernah menghapus di klien (data hantu).
   Butuh keputusan desain: soft-delete tersinkron vs tabel tombstone.
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
6. **Item 41** (audit kode 18 Juli) — mayoritas P1/P2 SUDAH dieksekusi
   di sesi yang sama (lihat CHANGELOG). Sisa: B.1 rotasi storeKey (butuh
   keputusan desain user), C.2 (gabung Item 17+21), uji printer device
   fisik Android ≤11, dan daftar P3 — detail di Item 41 di atas.
