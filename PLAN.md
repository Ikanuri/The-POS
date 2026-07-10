# PLAN.md

Daftar rencana kerja yang sudah didiskusikan tapi **belum dieksekusi**. Ini
BUKAN log — begitu satu item selesai dikerjakan & di-commit, **hapus item itu**
dari file ini (lihat aturan di [CLAUDE.md](CLAUDE.md) §Perencanaan). Riwayat
teknis pekerjaan yang SUDAH selesai ada di [CHANGELOG.md](CHANGELOG.md), bukan
di sini.

_Terakhir diperbarui: 8 Juli 2026._

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

## Item 1 — Fix dropdown pelanggan: hapus `.take(N)`, ganti fixed-height + scroll sungguhan

**Prioritas:** Tinggi. Kecil, jelas, tidak berisiko ke alur lain. Bisa
dikerjakan kapan saja, independen dari item lain.

**Masalah saat ini:**
- `lib/features/kasir/payment_screen.dart` — dropdown saran pelanggan di
  field "Cari pelanggan atau ketik nama…" adalah `Container` biasa (BUKAN
  scrollable) berisi `Column` dari `_custSuggestions.take(5)`.
- `lib/features/kasir/widgets/cart_meta_pickers.dart` (`_CustomerPickerSheet`,
  dipakai dari cart bar) — sudah pakai `ListView` di dalam
  `ConstrainedBox(maxHeight: ...)`, TAPI tetap `.take(8)` diterapkan ke
  `_results` SEBELUM masuk ke `ListView`. Jadi walau widget-nya scrollable,
  data di baliknya sudah kepotong duluan — scroll tidak menolong apa pun
  kalau hasil aslinya lebih dari 8.
- Di kedua tempat, `db.searchCustomers(q)` (query DB) **TIDAK ada batasan** —
  pembatasan cuma terjadi di layer tampilan (UI), bukan di query.

**Bug turunan yang ikut kesolusi otomatis:** pelanggan "Mbak Ima" tidak
ditemukan saat mengetik "ima" (baru muncul kalau ketik "mbak i"). Root cause:
query "ima" itu substring generik, bisa cocok ke BANYAK nama pelanggan lain
yang kebetulan mengandung "ima" di mana saja (Fatima, Karima, Halima, dst),
diurutkan alfabetis, lalu dipotong ke 5/8 teratas — kalau "Mbak Ima" jatuh di
urutan alfabetis setelah itu, dia tersingkir. Query "mbak i" jauh lebih
spesifik → hasil match jauh lebih sedikit → muat di 5/8 besar.

**Solusi yang disepakati:** Tinggi kontainer dikunci (~5 baris kelihatan),
tapi isinya SEMUA hasil match dari `searchCustomers()` (tanpa `.take()`),
benar-benar scrollable untuk sisanya.

**Dampak performa (sudah dianalisis, TIDAK jadi penghalang):** Nyaris nol.
Loop pengambilan hutang per-pelanggan (`getCustomerOutstandingDebt`) SUDAH
dijalankan untuk SELURUH hasil pencarian sebelum `.take()` diterapkan — jadi
kerja berat itu sudah terjadi hari ini juga, terlepas dari berapa yang
ditampilkan. Menghapus `.take()` murni perubahan lapisan tampilan.
Rekomendasi teknis tambahan: pakai `ListView.builder` (lazy-render) bukan
`ListView(children: [...])` (eager) untuk berjaga-jaga kalau toko punya
sangat banyak pelanggan + query sangat umum (1-2 huruf) — mencegah ratusan
widget dibangun sekaligus di memori.

**File yang terlibat:**
- `lib/features/kasir/payment_screen.dart` (dropdown pelanggan di layar Bayar)
- `lib/features/kasir/widgets/cart_meta_pickers.dart` (`_CustomerPickerSheet`,
  picker dari cart bar)

---

## Item 2 — Fix bug dedup importer produk (silent data loss)

**Prioritas:** Tinggi. Bug ini sudah nyata terjadi (bukan hipotesis) dan
menyebabkan kehilangan data tanpa pemberitahuan apa pun ke user.

**Masalah:** Di `lib/core/services/csv_import_service.dart`, kunci deteksi
baris-duplikat-dalam-satu-file adalah:
```dart
final dedupKey = '${name.toLowerCase()}|$unitTypeId'; // baris ~136
```
Cuma nama + tipe satuan — **TIDAK melibatkan barcode maupun kode produk sama
sekali**. Kalau ada dua baris dengan nama+satuan sama tapi barcode/harga
BEDA (SKU yang sesungguhnya berbeda), baris kedua otomatis dianggap
"duplikat" dan **dilewati diam-diam** (`duplicates++; continue;` — tanpa
error, tanpa peringatan ke user).

**Bukti nyata (ditemukan langsung di `docs/reference/Products.csv`):**
```
Sedap Goreng;108500;113000;0;6;14;11060048;Dos;1
Sedap Goreng;108500;111000;0;;14;25588880;Dos;1
```
Dua baris "Sedap Goreng" satuan Dos (`unitTypeId=14`), tapi **barcode beda**
(`11060048` vs `25588880`) dan **harga beda** (113000 vs 111000). Baris kedua
pasti dibuang oleh logika dedup ini — inilah penyebab konkret "Sedap Goreng
per dus tidak ada" yang dilaporkan user.

**Solusi yang perlu diputuskan lalu diimplementasikan:** kunci dedup harus
ikut mempertimbangkan barcode/kode_produk, bukan cuma nama+satuan. Perlu
keputusan desain kecil: kalau barcode kosong di kedua baris (tidak ada
identitas kuat sama sekali), tetap anggap duplikat (fallback ke perilaku
lama) atau tidak?

**File yang terlibat:** `lib/core/services/csv_import_service.dart`
(fungsi utama `importFromBytes`, sekitar baris 135-141).

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

**Prioritas:** Setelah Item 2 & 3 selesai (lihat alasan ketergantungan di
3b). User sudah konfirmasi punya beberapa file rentang tanggal (bukan cuma
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
Item 2 (fix dedup) & Item 3 terutama 3b (fix rasio multi-satuan). Alasan:
pencocokan nama produk di kolom "Rincian" bergantung penuh pada katalog
yang sudah lengkap & berstruktur benar. Kalau katalog masih ada SKU hilang
(Item 2) atau strukturnya kacau (Item 3b — "Sedap Goreng" jadi banyak
entitas tak berhubungan), baris rincian transaksi yang menyebut produk itu
otomatis ikut gagal/salah cocok juga — dua-tiga bug akan saling menumpuk
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

## Urutan eksekusi yang disarankan

1. **Item 1 & Item 2** bisa dikerjakan bersamaan sekarang — kecil, jelas,
   tidak berisiko ke alur lain, tidak saling bergantung.
2. **Item 3** (3a konversi format + 3b fix rasio multi-satuan, keduanya di
   file yang sama jadi wajar dikerjakan sekaligus) — mulai begitu user siap
   kirim/konfirmasi data produk final yang mau diimpor.
3. **Item 5** setelah Item 2 & 3 selesai (ketergantungan struktural, lihat
   penjelasan di atas) — dan setelah user konfirmasi cakupan tanggal file
   `Transaksi ...xlsx` yang tersedia.
4. **Item 4** independen, bisa disisipkan kapan saja setelah user menjawab
   3 pertanyaan desain di atas.
