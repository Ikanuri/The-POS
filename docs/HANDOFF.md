# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 6 Juli 2026 (lanjutan 7)._

---

## Di Mana Kita Sekarang

Sesi **deep debug + stress test + test integrasi + redesign retur hutang +
test Tier 1, 2 & 3 (termasuk widget-test harness) + feedback device Tier 4
dari user (termasuk 2 bug backup/restore NYATA yang ditemukan & diperbaiki)**.
`flutter analyze` bersih, **83 test hijau** (`test/widget_test.dart`,
`test/migration_v7_test.dart`, `test/db_fixes_test.dart`,
`test/transaction_lifecycle_test.dart`, `test/db_tier2_test.dart`,
`test/discount_allocation_test.dart`, `test/chart_utils_test.dart`,
`test/receipt_retur_widget_test.dart`, `test/tx_history_row_widget_test.dart`,
`test/receipt_kasir_name_overflow_test.dart`, `test/backup_restore_bug_test.dart`).

### Feedback device Tier 4 dari user (6 poin ditest langsung di HP)
User meng-update (bukan uninstall — data lama tetap ada, sudah dicek tidak
ada yang hilang) dan mencoba 6 fitur:
1. **Retur** — bekerja baik.
2. **Overflow nama kasir panjang** (baris "Kasir: ..." di struk) — user
   belum sempat test di device (ganti nama device butuh setup ulang,
   berisiko ganggu pairing asli). **Diverifikasi sesi ini via widget test**
   (`test/receipt_kasir_name_overflow_test.dart`, commit `a0c4c6c`) memakai
   `DeviceIdentity` palsu bernama sangat panjang — dikonfirmasi TIDAK
   overflow (fix `7307740` sudah benar). Test-nya sendiri divalidasi
   benar-benar mendeteksi regresi (sempat direvert sementara ke kode lama,
   terbukti gagal dengan RenderFlex overflow 773px, sebelum dikembalikan).
3. **Produk bervarian di struk** — dikonfirmasi benar via screenshot (Pop
   Ice + varian Coklat tampil dengan qty & harga benar).
4. **QRIS** — dikonfirmasi benar via screenshot (render QR sungguhan, bisa
   discan).
5. **Nota gabungan (merged invoice)** — logika pembayaran sudah benar, TAPI
   user sempat bingung kenapa status tidak "lunas semua" karena info sisa
   hutang / kembalian cuma ada di dalam struk, tidak di baris Riwayat
   Transaksi. → **Ditindaklanjuti sesi ini, lihat di bawah.**
6. **Backup/restore** — DITEST, **2 BUG NYATA ditemukan & sudah diperbaiki
   sesi ini** (commit `b97ffcb`), lihat detail di bawah.

### 2 bug backup/restore ditemukan user via test device — diperbaiki commit `b97ffcb`
User test: setup fresh device A → backup (1 produk/1 pegawai/1 pelanggan,
password simpel) → restore di fresh device B → gagal "password salah atau
data rusak". Juga: restore ulang di device A sendiri bilang "berhasil" tapi
perubahan data (pelanggan dihapus/ditambah setelah backup) tidak ter-revert.

**Bug 1 (blocking, cross-device restore MUSTAHIL selalu gagal)**:
`backup_screen.dart` memakai `DbExportService.export()` (format BPOS1) yang
menurunkan kunci file dari **storeKey TOKO ASAL + password**. `storeKey`
acak 256-bit di-generate ULANG setiap kali setup toko baru — jadi device
tujuan (fresh install = storeKey baru) TIDAK MUNGKIN menghasilkan kunci
yang sama walau password 100% benar. Ironisnya teks UI sudah menjanjikan
"file ini hanya bisa dibuka dengan password yang Anda tentukan" — janji itu
cuma benar untuk format portable (`exportPortable`/BPOP2, kunci HANYA dari
password) yang sudah ada di `db_export_service.dart` tapi TIDAK PERNAH
dipanggil dari UI manapun (dead code). Fix: `backup_screen.dart` sekarang
memanggil `exportPortable()`, bukan `export()`.

**Bug 2 (silent, restore "berhasil" tapi UI tidak berubah)**: `restoreFromDump`
menulis DELETE via `customStatement` dan INSERT via `customInsert` TANPA
parameter `updates:` — raw SQL lewat Drift TIDAK otomatis diketahui tabel
mana yang berubah. Semua `StreamProvider` yang bergantung pada `.watch()`
(daftar produk, pelanggan, pegawai, kasir_permissions, payment_methods —
konvensi paling umum di app ini) TIDAK ter-notifikasi sama sekali, walau
DB sungguhan sudah benar-benar berubah. Fix: DELETE pakai `customUpdate`
(bukan `customStatement`, yang sama sekali tak punya param `updates:`) +
setiap `customInsert` diberi `updates: {table}` (via lookup `allTables`
by `entityName`). Provider berbasis `FutureProvider` sekali-ambil (mis.
Ringkasan, grup produk) tetap tidak auto-refresh — untuk itu pesan sukses
sekarang menyarankan tutup-buka ulang aplikasi.

3 test baru (`test/backup_restore_bug_test.dart`) membuktikan kedua fix,
masing-masing DIVERIFIKASI benar-benar gagal di kode lama sebelum fix
diterapkan (bukan cuma "lolos kebetulan").

### Fitur baru sesi ini: Sisa/Kembali langsung di baris Riwayat Transaksi — commit `79aa836`
Respons langsung ke poin 5 di atas. `tx_history_sheet.dart` `_TxRow`:
`trailing` Column sekarang menampilkan baris tambahan di bawah nominal total:
- **"Sisa Rp X"** (merah, `AppTheme.debtFg`) kalau `status` kurang_bayar/tempo.
- **"Kembali Rp X"** (hijau, `AppTheme.changeFg`) kalau lunas & `changeAmount > 0`.
- Tidak ada tambahan kalau uang pas (bukan retur pula — baris retur tidak
  menampilkan badge lunas/sisa sama sekali, sudah sesuai desain lama).

Harness widget-test (dari sesi lalu) sekali lagi menemukan overflow NYATA
sebelum sempat dipakai user: header Row "Riwayat Transaksi" (dengan tombol
mode-pilih di sampingnya) overflow di layar sempit saat teksnya jadi
"N nota dipilih". Fix sama seperti overflow-overflow sebelumnya
(`Expanded` + `maxLines:1` + `ellipsis`, `Spacer` dihapus karena `Expanded`
sudah mendorong tombol ke kanan).

**Catatan debugging penting** (biar tidak terulang): test baru sempat gagal
terus dengan pesan "Found 0 widgets with text ...", padahal `print()` debug
manual dalam isolasi menunjukkan teks itu ADA di tree. Ternyata bukan soal
timing/race Riverpod — `formatRupiah()` (`app_theme.dart`) sengaja memakai
**non-breaking space (U+00A0)** antara "Rp" dan angka (biar tidak terpisah
baris), sedangkan literal string di test pakai spasi biasa (U+0020) —
`==` string gagal walau terlihat identik saat di-print. Fix: literal test
pakai karakter U+00A0 asli (`const _nbsp = ' '`), BUKAN spasi biasa.
Setelah tahu akar masalahnya, `pump_app.dart` yang tadinya ditambah pump
manual berlapis (dikira perlu untuk timing) berhasil disederhanakan
KEMBALI ke satu `pumpAndSettle()` saja — semua test tetap hijau.

### Widget-test harness (Tier 3, bagian kedua) — commit `7307740`
`test/helpers/pump_app.dart` — `pumpWithFakeApp(tester, db:, child:)`:
override `databaseProvider`/`deviceProvider` Riverpod dengan versi palsu
(in-memory `AppDatabase` + `DeviceIdentity` ter-configured), tanpa perlu
device/SQLCipher sungguhan. **Catatan penting**: surface di-set generus
(430x2400) karena banyak screen pakai `ListView(children:)` yang lazy-build
anak di luar viewport — kalau lupa ini, widget yang "di bawah" (mis. tombol
Retur) tidak akan ketemu `find.text(...)` padahal bukan itu yang salah.

Widget test pertama (`receipt_retur_widget_test.dart`) langsung menemukan
**2 overflow layout NYATA** (bukan kesalahan test) di `receipt_screen.dart`,
keduanya sudah diperbaiki (pola: bungkus `Expanded` + `ellipsis` pada teks
yang bisa panjang, biarkan teks penting di sisi lain tetap utuh):
1. Baris "Kasir: <nama device>" — nama device bebas diisi user saat setup.
2. Baris "Total Dikurangi dari Hutang" (dari redesign retur sesi ini) —
   labelnya lebih panjang dari "Total Refund".

Ini bukti nyata harness widget-test bernilai LEBIH dari sekadar "membuktikan
kode saya benar" — dia menemukan bug yang test logika/DB TIDAK BISA
menangkap (masalah tata letak visual).

### Diskusi kesiapan production — peta test (4 tier berdasar risiko)
- **Tier 1 (kritis, tersentuh tiap transaksi)** — ✅ SELESAI (`9b9b3cc`):
  `saveTransaction`, `voidTransaction`, `addReturnTransaction` (nota lunas),
  `settleMergedDebt`.
- **Tier 2 (penting, lebih jarang)** — ✅ SELESAI (`3a7ce6b`):
  `PriceService.resolvePrice`, `mergeRows` master-data LWW & dedup
  price_tiers, `restoreFromDump`, `generateUniqueLocalId`.
- **Tier 3 (nice-to-have)** — ✅ SELESAI:
  - Alokasi diskon proporsional diekstrak dari `payment_screen.dart`
    (duplikat persis di `_confirm` & `_confirmAddItems`) jadi
    `allocateCartTotal` murni (`lib/features/kasir/discount_allocation.dart`,
    commit `5a4ee57`). Diverifikasi manual byte-per-byte bahwa hasil
    `TransactionItemsCompanion` identik sebelum/sesudah (satu kondisi yang
    hilang, `_totalOverride != null`, terbukti redundan — `_total` selalu
    `== _cartTotal` saat override null, jadi rasio otomatis 1.0).
  - Matematika clamp tinggi bar chart (fix crash omzet negatif) diekstrak
    dari 3 lokasi duplikat jadi `clampedBarHeight`
    (`lib/core/utils/chart_utils.dart`, commit `9991519`). Parameter
    `emptyHeight` dibedakan eksplisit per situs supaya visual persis sama.
  - Widget-test harness dibangun (`test/helpers/pump_app.dart`, commit
    `7307740`) — lihat detail di atas. Menemukan & memperbaiki 2 overflow
    layout nyata di `receipt_screen.dart`.
  - Sisa pekerjaan Tier 3 yang REALISTIS untuk lanjutan (belum dikerjakan,
    bukan mendesak): tambah widget test serupa untuk screen lain yang
    fix-nya sesi ini murni visual & belum ketahuan lewat device — kandidat:
    `_QrisDisplay` di payment_screen.dart (butuh setup cart+payment method
    lebih berat), dan chart harian/per-jam (opsional, karena
    `clampedBarHeight` sendiri sudah dites tuntas secara matematis).
- **Tier 4** — ✅ SELESAI, 6/6 poin ditest user & ditindaklanjuti
  (lihat "Feedback device Tier 4" di atas). 1 poin (Sisa/Kembali di Riwayat
  Transaksi) jadi fitur baru; 1 poin (overflow nama kasir) diverifikasi
  lewat widget test otomatis; 1 poin (backup/restore) menemukan **2 bug
  nyata yang sudah diperbaiki** (lihat "2 bug backup/restore" di atas).

Kalau lanjut sesi berikutnya: semua 6 poin feedback Tier 4 sudah
ditindaklanjuti — kalau user tidak punya temuan device baru, kandidat
lanjutan adalah widget test untuk screen lain (QRIS) atau mulai bahas
kesiapan rilis. Versi (`pubspec.yaml`) masih `2.0.0+1` — belum dinaikkan,
belum ada PR ke `main` (branch ini ~70+ commit di depan), keduanya
menunggu keputusan user.

### Retur untuk nota belum lunas — REDESIGN (keputusan user: Opsi A)
User menunjukkan contoh dari app pembanding: retur atas nota **tempo/kurang_bayar**
seharusnya **mengedit nota asli langsung** (item hilang dari nota, total &
hutang berkurang), **bukan** membuat nota retur terpisah dengan refund tunai
(yang sebelumnya salah — toko seolah harus keluar uang tunai padahal pembeli
belum pernah bayar sama sekali).

Diimplementasikan sebagai method baru **`returnUnpaidTransactionItems`**
(app_database.dart) — terpisah dari `addReturnTransaction` yang lama (tetap
dipakai HANYA untuk nota **lunas**, karena di situ uang memang sudah
berpindah tangan sungguhan). Method baru:
- Mengurangi/menghapus baris `transaction_items` yang diretur langsung (baris
  hilang total dari nota bila qty diretur penuh — persis seperti contoh
  referensi).
- Mengembalikan stok (`return_in`, sama seperti jalur lama).
- **Tidak** membuat nota baru, **tidak** ada refund tunai.
- Rekonsiliasi total/status pakai `_reconcileTransactionTotals` yang sudah
  ada (dipakai bersama tambah-belanjaan & sync) — otomatis menangani kasus
  kelebihan bayar relatif (paid > total baru) sebagai kembalian.
- Guard eksplisit: throw `StateError` bila dipanggil pada nota berstatus
  selain tempo/kurang_bayar (mencegah salah pakai).

UI (`receipt_screen.dart` `_showReturSheet`) bercabang berdasar status nota:
nota belum lunas → sembunyikan pilihan "Kembalikan via", tampilkan banner
info "mengurangi hutang", label "Total Dikurangi dari Hutang"; nota lunas →
UI lama (pilihan metode refund) tidak berubah.

**4 test baru** di `db_fixes_test.dart` membuktikan: retur sebagian (status
tetap tempo), retur penuh (status→lunas, baris hilang), retur yang membuat
overpay relatif (kembalian otomatis benar), dan guard menolak nota lunas.

Poin diskusi lama "Retur atas nota tempo/kurang-bayar..." di bawah **sudah
selesai/resolved** lewat perubahan ini — dihapus dari daftar "sengaja belum
diperbaiki".

### Sebelumnya di sesi ini (masih berlaku)

**Test integrasi Drift nyata** (bukan simulasi/reimplementasi) membuktikan:
- Migrasi schema v6→v7 (indeks `transaction_payments`) benar-benar jalan di
  DB lama + query planner memakai indeks (`EXPLAIN QUERY PLAN`).
- `getReturnedQtyByUnit` mengecualikan retur yang di-void.
- `mergeRows` rename local_id mencari suffix bebas (-S, -S2, ...), bukan
  berhenti di percobaan pertama.
- `TutupBukuService.execute()` dijalankan end-to-end sungguhan (file I/O nyata
  via fake `PathProviderPlatform`) — saldo stok unit yang ledger-nya habis
  terarsip terbukti dibawa via entri baru, bukan hilang.


**Hasil stress test (paling penting):**
- **Aritmatika AMAN untuk skala waktu tak realistis.** Uang `int64` overflow di
  ~1 miliar tahun (toko ramai); presisi Rp-satuan (2^53) di ~987 ribu tahun.
  Stok `double` running-balance: drift 0 untuk pecahan terminating (0.25 kg);
  ~0.02 gram setelah 1 juta penjualan 0.1. **Bukan faktor pembatas.**
- **Faktor pembatas = PERFORMA, bukan korektnes.** Ditemukan cacat serius:
  tidak ada indeks pada `transaction_payments(transaction_id)` → anti-join
  `backfillMissingPayments` (jalan TIAP startup) O(n²). Terukur 90k tx = 156
  detik. **Diperbaiki di `61c7455`** (indeks + schema v7): 90k=28ms,
  1,1jt=368ms. Ini yang menentukan "berapa lama data stabil".
- **Jawaban durability:** dengan fix v7 + tutup buku tahunan, praktis stabil
  tanpa batas. Tanpa tutup buku, startup melambat linear (~O(total tx)) dari
  dua backfill-scan; nyaman s/d ~1-2 juta transaksi (~beberapa tahun toko
  ramai), lalu startup mulai terasa (ratusan ms).

Sebelumnya (commit `16ad934`) 10 kelompok bug fungsional diperbaiki:

- **Tutup buku** tak lagi me-reset stok produk yang seluruh riwayat ledger-nya
  ada di tahun terarsip (saldo dibawa via entri `adjustment` baru).
- **Backup/restore/export** kini menyertakan tabel `employees` (sebelumnya
  hilang saat restore).
- **Sync LAN**: rekonsiliasi header memakai id transaksi dari item & pembayaran
  juga (cicilan/item susulan nota lama kini terkoreksi di perangkat penerima);
  `dumpSince` menyertakan item susulan via `added_at`; rename `local_id`
  tabrakan mencari suffix bebas.
- **Struk in-app & share**: `transaction_items` selalu berisi qty EFEKTIF —
  jangan pernah mengurangi qty varian lagi saat menampilkan (double-subtract
  membuat induk+varian tampil kosong). Printer sudah benar sejak awal.
- **QRIS** di layar bayar kini dirender `QrImageView` (dulu teks mentah).
- **Chart harian/per-jam** di-clamp — omzet negatif (hari didominasi retur)
  sempat bisa membuat tinggi bar negatif → crash render.
- Konversi stok rasio satuan < 1 dibetulkan; retur void tak dihitung
  `getReturnedQtyByUnit`; draft katalog tak ikut tersapu pembersihan keranjang
  24 jam; hapus induk dari modal entri ikut membersihkan varian yatim; total
  kartu pesanan ditahan pakai `cartTotalOf` (helper baru di cart_provider).

## Kandidat Optimasi Durability Berikutnya (belum dikerjakan)
- **Backfill tiap startup masih O(n) full-scan.** `backfillMissingSummaries`
  (DISTINCT-date scan: 42ms@90k, 180ms@365k) & `backfillMissingPayments`
  (kini pakai indeks, tapi tetap men-scan semua tx paid). Idealnya pakai
  watermark ('last_backfill_ts') agar hanya memproses data baru. Belum
  mendesak karena tutup buku mereset ukuran; indeks sudah menutup O(n²).
- `getReturnedQtyByUnit` scan `transactions.internal_note` tanpa indeks —
  jarang (hanya saat buka sheet retur), prioritas rendah.

## Temuan yang SENGAJA Belum Diperbaiki (kandidat diskusi)

- **Multi-satuan + varian bercampur**: invariant `storedQty induk = base +
  Σvarian` ambigu bila satu produk punya ≥2 baris satuan non-varian di
  keranjang (varian "menempel" ke produk, bukan ke baris). Efek: qty efektif
  bisa salah hitung pada kombinasi langka ini. Perbaikan butuh refactor
  atribusi varian per-baris — jangan disentuh tanpa keputusan user.
- Tombol minus di kartu produk (`_decrementProduct`) selalu mengurangi baris
  satuan PERTAMA bila produk ada di keranjang dengan >1 satuan.
- Sync saat ini selalu full-dump (`since` = epoch, satu-satunya caller di
  sync_screen tidak mengirim `since`) — filter incremental di `dumpSince`
  sudah dibetulkan dan siap bila kelak dibuat incremental.

## Keputusan Penting yang Masih Berlaku
- Cart meta tab = shrink-wrap kiri, **bukan** full-width.
- Animasi scan yang dipilih = **Opsi E** (garis pulse hijau), dari 8 opsi.
- Referensi proyek tinggal di `docs/reference/` (jangan hapus).
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.

## Menggantung / Kandidat Berikutnya
- Tidak ada tugas terbuka selain daftar "temuan belum diperbaiki" di atas.
- Proposal "Barokah Order" masih menunggu keputusan user
  (`docs/PROPOSAL_PERTIMBANGAN_BAROKAH_ORDER.md`).

## Preferensi User
- Untuk fitur bervisual (mis. animasi), **usulkan beberapa opsi desain dulu**
  sebelum implementasi.
- Bahasa komunikasi & teks UI: Indonesia.
- Hati-hati agar perubahan tidak merusak logika/alur aplikasi yang sudah ada.
