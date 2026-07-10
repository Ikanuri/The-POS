# PLAN.md

Daftar rencana kerja yang sudah didiskusikan tapi **belum dieksekusi**. Ini
BUKAN log — begitu satu item selesai dikerjakan & di-commit, **hapus item itu**
dari file ini (lihat aturan di [CLAUDE.md](CLAUDE.md) §Perencanaan). Riwayat
teknis pekerjaan yang SUDAH selesai ada di [CHANGELOG.md](CHANGELOG.md), bukan
di sini.

_Terakhir diperbarui: 10 Juli 2026._

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

## Item 3 — Konversi format `Products.csv` + fix mapping multi-satuan (RATIO HILANG — temuan besar)

**Prioritas:** Tinggi, harus selesai SEBELUM data produk diimpor ke database
live. Kalau data multi-satuan ini terlanjur masuk salah struktur, membenahi
belakangan (memisah ulang produk+satuan yang benar tanpa merusak transaksi
yang sudah tercatat) jauh lebih rumit daripada mencegahnya dari awal.

### 3a. Masalah format (delimiter & nama header)

`docs/reference/Products.csv` **tidak bisa langsung diimpor apa adanya**:
- **Delimiter:** file pakai titik-koma (`;`) sebagai pemisah kolom (umum
  untuk ekspor Excel locale Indonesia). Parser CSV di importer
  (`_parseCsv`) **cuma mengerti koma (`,`)**. Efeknya: satu baris utuh akan
  terbaca sebagai SATU kolom raksasa, bukan 9 kolom terpisah.
- **Nama header tidak cocok alias yang dikenali importer** (importer
  mencocokkan berdasar NAMA header, bukan posisi — jadi urutan kolom bebas,
  tapi namanya harus persis salah satu alias):

  | Header di `Products.csv` | Alias yang dikenali importer | Cocok? |
  |---|---|---|
  | `Produk` | `nama`, `name`, `product_name`, `nama_produk` | ❌ |
  | `Harga Pokok` | `harga_beli`, `cost`, `buy_price`, `cogs` | ❌ |
  | `Harga Jual` | `harga_jual`, `harga`, `sell_price`, `price` | ❌ (ada spasi, importer butuh underscore/kata utuh) |
  | `Stok` | `stok`, `stock`, `qty`, `quantity` | ✅ |
  | `Grup Produk` | `grup`, `group`, `kategori`, `category`, `group_name` | ❌ |
  | `Satuan` | `satuan`, `unit`, `uom`, `unit_type` | ✅ |
  | `Barcode` | `barcode`, `kode_barcode`, `ean`, `upc` | ✅ |
  | `Kode Produk` | `kode`, `kode_produk`, `code`, `sku` | ❌ (ada spasi) |
  | `Non Stok` | *(tidak ada kolom ini di importer sama sekali)* | ❌ — lihat 3c |

  Kalau diimpor apa adanya: hampir semua baris akan ditolak dengan pesan
  "nama produk kosong" (kolom "nama" tidak pernah ketemu).

- **Parsing harga cukup toleran** untuk format angka Indonesia (`_parseIntPrice`
  di `csv_import_service.dart`): bisa baca "15000" polos, "15.000" (titik
  ribuan), "15,000" (koma ribuan) — TAPI **gagal total kalau ada simbol mata
  uang di depan** seperti "Rp 15.000" (bukan angka polos). Ini titik rawan
  kalau data lain nanti diekspor dengan format itu.

**Solusi:** proses konversi (dilakukan Claude tiap user kirim data baru,
BUKAN pekerjaan sekali-jadi-selamanya karena Claude tidak berjalan otomatis
di background): ganti delimiter `;`→`,`, ganti nama header ke alias yang
dikenali (`Produk`→`nama`, `Harga Jual`→`harga_jual`, `Harga Pokok`→
`harga_beli`, `Grup Produk`→`grup`, `Kode Produk`→`kode_produk`), lalu user
import sendiri lewat menu yang sudah ada di app.

### 3b. Temuan besar: hubungan multi-satuan (rasio Slop/Pak/Biji/Dos) HILANG TOTAL saat import

Ini temuan paling signifikan dari audit ulang — kemungkinan besar penyebab
"kuantitas tidak pas" yang dilaporkan user.

**Fakta di data:** dari 1.794 nama produk unik di `Products.csv`, **564 nama
(31% dari katalog)** muncul di lebih dari satu baris — tiap baris mewakili
satuan kemasan berbeda dari produk YANG SAMA. Contoh nyata:
```
234 12  | satuan=Slop(9) | harga 193.000
234 12  | satuan=Pak(4)  | harga  19.400   ← rasio harga ~10:1, konsisten dgn 1 Slop = 10 Pak

76 12   | satuan=Pak(4)  | harga  15.600
76 12   | satuan=Slop(9) | harga 156.000  ← rasio sama, 1:10
```
Rasio harga antar-baris konsisten (kelipatan bulat) — ini jelas dimaksudkan
sebagai SATU produk dengan beberapa satuan kemasan (rasio konversi), bukan
produk yang berbeda-beda.

**Akar masalah teknis:** di `csv_import_service.dart`, daftar
`existingProducts` diambil **SEKALI di awal** proses import
(`final existingProducts = await db.searchProducts('');` sebelum loop
dimulai) dan **tidak diperbarui selama loop berjalan**. Jadi kalau baris
pertama ("234 12" satuan Slop) membuat produk baru di tengah proses import,
baris kedua ("234 12" satuan Pak) yang diproses SETELAHNYA di file yang SAMA
tidak akan pernah "melihat" produk yang baru saja dibuat — `_matchExistingUnit`
mengecek terhadap snapshot lama yang sudah basi. Akibatnya: **setiap baris
CSV yang tidak sudah ada di database SEBELUM proses import dimulai akan
SELALU dibuat sebagai produk baru & berdiri sendiri**, bukan ditambahkan
sebagai satuan tambahan dari produk yang baris sebelumnya baru dibuat di
proses yang sama.

**Dampak konkret:** 564 keluarga produk (31% katalog) akan menjadi
produk-produk terpisah TANPA hubungan rasio konversi sama sekali. Konversi
stok antar-satuan (jual 3 Pak → otomatis kurangi 0.3 Slop dari stok yang
sama) tidak akan berfungsi, karena aplikasi tidak tahu keduanya adalah
barang yang sama.

**Solusi yang perlu dibangun:** importer perlu MENGELOMPOKKAN baris-baris
CSV berdasarkan nama produk TERLEBIH DAHULU (sebelum proses insert dimulai),
supaya baris-baris dengan nama sama dari FILE YANG SAMA dikenali sebagai
satu produk dengan banyak satuan (dengan `ratioToBase` yang benar antar
satuan) — bukan mengandalkan pengecekan ke database yang snapshotnya basi.

**Ketergantungan ke item 5:** kalau ini tidak dibenahi dulu, Item 5 (import
riwayat transaksi) akan ikut rusak — baris `Rincian:Nama:Qty` di riwayat
transaksi tidak akan bisa membedakan "Sedap Goreng" per Dos vs per Biji
kalau struktur katalog dari awal sudah kacau/tidak punya rasio yang benar.

### 3c. Temuan kecil — kolom "Non Stok" tidak pernah dibaca importer

Kolom `Non Stok` di CSV (menandai barang/jasa yang tidak perlu dilacak
stoknya, mis. pulsa) **tidak ada penanganannya sama sekali** di
`csv_import_service.dart` — semua produk hasil import akan dianggap
"dilacak stoknya" secara default (`isNonStock: false`, hardcoded). Untuk
barang yang seharusnya non-stok, ini bisa memunculkan peringatan "stok
tidak cukup" yang seharusnya tidak relevan. Prioritas rendah, bisa
digabung sekalian saat mengerjakan 3a/3b kalau sedang menyentuh file yang
sama.

### 3d. Catatan — kolom "Stok" di file ini TIDAK bermasalah (sudah dicek silang)

Untuk menghindari kebingungan: kolom "Stok" di `Products.csv` nyaris
seluruhnya bernilai 0 (cuma 3 dari 2.812 baris punya stok tercatat: Intermie
Pedas, Sedap Goreng, Sedap Soto). Ini SUDAH dicek silang dengan
`Stok Produk.xlsx` di dataset yang sama, dan angkanya **cocok persis** —
jadi ini bukan bug mapping, memang begitu kondisi data aslinya di sistem
lama (toko kemungkinan tidak rutin mencatat stok per SKU di sistem lama).
Tidak perlu tindakan apa pun untuk poin ini.

**File yang terlibat:** `lib/core/services/csv_import_service.dart`.

---

## Item 4 — Importer pelanggan + poin loyalty (fitur baru, belum ada sama sekali)

**Prioritas:** Menunggu keputusan desain user — bisa disisipkan kapan saja
setelah itu karena independen dari item lain (tidak menyentuh
`csv_import_service.dart` yang sama).

**Masalah:** Importer CSV yang ada SEKARANG cuma untuk produk. Tidak ada
jalur import untuk tabel `customers` atau `loyalty_point_ledger` sama
sekali.

**Pertanyaan desain yang HARUS dijawab user sebelum implementasi dimulai:**
1. Update poin: **timpa total** ke nilai baru dari file, atau **tambah/
   kurang selisih** dari nilai yang sudah ada di app sekarang?
2. Pencocokan pelanggan lama (di file) vs pelanggan yang sudah ada di app
   pakai kunci apa? (nama? nomor HP? kolom ID khusus dari sistem lama?)
3. Bagaimana kalau ada dua pelanggan dengan nama sama tapi sebenarnya orang
   berbeda (collision)?

**File yang kemungkinan terlibat (belum pasti, tergantung desain akhir):**
kemungkinan besar file BARU `lib/core/services/customer_import_service.dart`
(terpisah dari `csv_import_service.dart` produk, mengikuti pola yang sama).

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

## Urutan eksekusi yang disarankan

1. **Item 3** (3a konversi format + 3b fix rasio multi-satuan, keduanya di
   file yang sama jadi wajar dikerjakan sekaligus) — mulai begitu user siap
   kirim/konfirmasi data produk final yang mau diimpor.
2. **Item 5** setelah Item 3 selesai (ketergantungan struktural, lihat
   penjelasan di atas) — dan setelah user konfirmasi cakupan tanggal file
   `Transaksi ...xlsx` yang tersedia.
3. **Item 4** independen, bisa disisipkan kapan saja setelah user menjawab
   3 pertanyaan desain di atas.
4. **Item 8** menunggu keputusan user soal trade-off (kompleksitas HTML vs
   manfaat, relevansi ke pelanggan vs kasir).
