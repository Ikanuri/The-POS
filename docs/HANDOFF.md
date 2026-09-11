# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 11 September 2026, sesi kelima puluh — pesan sukses
setelah ekspor/backup/share dinetralkan jadi "Selesai" (menghindari
klaim palsu "berhasil dibagikan" saat user sebenarnya batal share).
Versi kerja **2.59.0+123** (MINOR naik dari 2.58.1+122 — perubahan UX
yg terlihat pengguna di 6 file, PATCH direset). schemaVersion **43**
(tidak berubah)._

## Sesi kelima puluh — pesan sukses ekspor/backup/share dinetralkan jadi "Selesai"

**Masalah dilaporkan user** (kata-kata persis, diterjemahkan): di
download/share laporan tidak perlu pesan eksplisit "sukses dibagikan"
— cukup pesan netral, karena `Share.shareXFiles` (`share_plus`)
resolve begitu OS share sheet DITUTUP, tak peduli user benar-benar
pilih aplikasi tujuan share atau cuma batal/dismiss — app lama tetap
klaim "berhasil dibagikan" walau user batal. Diminta berlaku juga di
tab Sinkron Harga & Backup di Pengaturan, plus tempat lain dgn masalah
sama.

**Fix**: ganti pesan sukses jadi string netral **"Selesai"** (bukan
kata Inggris "done" — UI WAJIB Bahasa Indonesia per CLAUDE.md) di
SEMUA jalur download maupun share (bukan cuma share — user eksplisit
minta "download atau share" dinetralkan sama-sama, demi konsistensi),
di 8 titik pesan, 6 file: `report_export.dart` (`exportReport()` +
`shareReport()`), `price_sync_screen.dart` (`_exportCsv()` +
`_exportPriceFile()`), `backup_screen.dart`, `pengaturan_screen.dart`
(Export Produk CSV), `alih_owner_screen.dart`, `arsip_screen.dart`.
Semua 8 titik ini adalah pesan yg tampil PERSIS setelah pemanggilan
helper bersama `saveOrShareExport()` (`export_destination.dart`) atau
setara custom di `report_export.dart` — akar masalah identik di semua
titik. Pesan ERROR (`showError`) & `showSuccess` lain yg TIDAK terkait
download/share (mis. sukses restore backup, sukses alih owner) TIDAK
disentuh — tetap deskriptif seperti semula, tidak ambigu.

**Test**: TIDAK ada test lama yg meng-assert teks pesan sukses persis
ini (dicek eksplisit — test widget yg ada utk fitur2 ini cuma
memverifikasi dialog pilihan "Bagikan"/"Simpan ke Perangkat" muncul &
Batal menutupnya, tidak pernah menunggu sampai pesan sukses akhir
tampil, krn `share_plus`/`path_provider` tidak resolve sungguhan di
`flutter_test` — lihat keterbatasan test yg sudah dicatat sesi-sesi
sebelumnya). Jadi tidak ada test lama yg perlu diupdate; perubahan
murni string constant tanpa logika baru, tidak butuh test regresi baru
(perubahan deterministik, tidak ada cabang logika utk dibuktikan).
`flutter analyze` 0 issue. Full suite: **1614 test lulus, 0 gagal**.
Commit: `4dd9a2b`.

## Sesi keempat puluh — ikon share laporan + CSV katalog harga bisa dibagikan

`lib/features/laporan/laporan_screen.dart` + `lib/features/produk/price_sync_screen.dart`.
1. `_ExportFormatChip` (laporan_screen.dart) — ikon share dropdown ekspor
   `Icons.ios_share_outlined` -> `Icons.share` (ikon "cabang" klasik, sama
   dgn tombol "Bagikan Gambar" di `cart_sheet.dart`/`receipt_screen.dart`)
   sesuai konvensi share/share_outlined yang sudah didokumentasikan di
   `cart_sheet.dart` (~baris 1132-1136): `Icons.share` utk tombol yang
   men-trigger share LANGSUNG (bukan cuma buka sheet dulu) — dropdown
   laporan ini memang direct-share (`Navigator.pop(('share', format))` ->
   `shareReport()` -> `Share.shareXFiles` langsung), jadi `Icons.share`
   adalah ikon yang benar. `test/laporan_export_chip_dropdown_test.dart`
   diperbarui (3 assersi `Icons.ios_share_outlined` -> `Icons.share`).
2. `_exportCsv()` (price_sync_screen.dart, ekspor CSV katalog harga tab
   Sinkron Harga produk — BEDA dari "Export Produk CSV" di
   `pengaturan_screen.dart` yang sudah diperbaiki sesi sebelumnya)
   sebelumnya langsung `FilePicker.platform.saveFile` tanpa opsi share
   sama sekali. Diganti pakai `saveOrShareExport` (helper yang sudah ada
   di `export_destination.dart`, sudah dipakai `_exportPriceFile` di file
   yang sama sbg referensi pola) — muncul dialog "Simpan CSV" dgn opsi
   "Bagikan"/"Simpan ke Perangkat".

**Test baru**: `test/price_sync_export_csv_share_test.dart` (widget test,
pola PERSIS `test/pengaturan_export_csv_share_test.dart` — tap "Export ke
CSV" -> dialog "Simpan CSV" dgn tombol Bagikan & Simpan ke Perangkat
muncul, Batal menutup tanpa memanggil plugin apa pun). Revert-verified
(gagal dgn `findsNothing` utk teks "Simpan CSV" sblm fix, hijau lagi
setelah). `flutter analyze` 0 issue. Full suite: **1612 test lulus, 0
gagal** (naik dari 1610 — +2 test file baru/dimodifikasi bersih, tanpa
flake terlihat di run ini). Commit: `ab159a4`.

## Sesi keempat puluh sembilan — fix reaktivitas stream pasca approve usulan kasir

**Temuan audit eksternal (2 item, semua SUDAH DIEKSEKUSI sesi ini)**:
1. `applyProductProposals` (`app_database.dart`, ±baris 6827-6955) — kelas
   bug SAMA dgn `TutupBukuService`/`mergeRows`: DELETE `price_tiers`/
   `alt_prices` lama per satuan pakai `customStatement` (TIDAK bisa
   terima `updates:` sama sekali — diganti `customUpdate`) dan INSERT OR
   REPLACE per baris (5 tabel: products/product_units/price_tiers/
   alt_prices/product_barcodes) via `customInsert` tanpa `updates:`.
   Fix: `tableInfo` diresolve SEKALI di luar loop dari nama tabel literal
   `order` (bukan pola null-safety `mergeRows` yg menerima nama dari luar
   device — 5 nama ini kita kontrol sendiri), dipasang ke KEDUA call site.
   Test baru `.listen()` live: `apply_product_proposals_reactive_test.dart`
   (subscribe `watchBaseUnitPrices()`, JOIN `product_units`+`price_tiers`
   — kena kedua tabel yg diperbaiki).
2. `saveTransactionWithDebtSettlements` (±baris 3400) — write
   `debtSettlementDetail` ke nota TIDAK mencap ulang `updatedAt`, padahal
   `dumpSince` filter transaksi `WHERE created_at >= ? OR updated_at >= ?`
   (Item 62). Low severity (field ini murni tampilan struk, bukan
   dipakai recalculation apa pun) tapi tetap real sync gap pada nota
   LAMA. Fix: tambah `updatedAt: Value(DateTime.now())` ke
   `TransactionsCompanion` yg sama. Test baru (Tier 1, one-shot cukup —
   bukan bug reaktivitas stream): `debt_settlement_detail_updated_at_test.dart`.

Kedua fix REVERT-VERIFIED (masing² di-revert sementara, test baru
terbukti gagal dgn pesan jelas, dikembalikan, hijau lagi). `flutter
analyze` 0 issue. Full suite: **1613 test lulus, 0 gagal** (tidak ada
flake `backup_schema_version_guard_test.dart` di run ini). Commit:
`af825c5`.

**Sesi sebelumnya** — fix reaktivitas stream pasca Tutup Buku: kelas bug
yang SAMA, di `tutup_buku_service.dart` (fungsi `execute()`, ±baris
247-327) — 10 `customUpdate` (DELETE) + 1 `customInsert` (carry-forward
`stock_ledger`) di dalam transaksi tutup buku TIDAK SATUPUN menyertakan
parameter `updates: {...}`. Sudah dikasih `updates:` sesuai tabel yang
disentuh. Test `.listen()` live: `tutup_buku_stock_stream_reactive_test.dart`.
Commit: `b890ee2`.

## Sesi lalu — redesain KEDUA dropdown ekspor laporan (bukan chip lagi)

User bilang desain chip badge warna (merah PDF/hijau Excel) dari sesi
kemarin BELUM cocok: "design chip itu harusnya bukan chip, cukup teks
biasa namun tidak default juga hurufnya... Icon juga, sebisa mungkin
hanya garis, sementara backgroundnya transparan. Saya punya design
iconnya." — user lampirkan 2 PNG (icon PDF & Excel, monokrom hitam murni
di atas transparan, dikonfirmasi via Pillow: TIDAK ada warna sama sekali,
cuma variasi alpha). Disimpan ke `assets/icons/export_pdf.png` &
`export_excel.png` (didaftarkan di `pubspec.yaml` assets), dirender via
`Image.asset(..., color: scheme.onSurface, colorBlendMode:
BlendMode.srcIn)` supaya ikon hitam otomatis ikut warna teks tema
terang/gelap. `_ExportFormatChip` (`laporan_screen.dart`) dirombak: HAPUS
`Container` pembungkus (background/border/borderRadius) & badge kotak
warna, ganti `Icon` Material jadi `Image.asset` custom, hapus subtitle
"Unduh ke HP" (cukup label "PDF"/"Excel" teks biasa, `fontWeight.w500`
bukan `w700` bold ala chip). 2 zona tap independen (badan baris = unduh,
ikon share terpisah `ios_share_outlined` = share langsung) TETAP
dipertahankan dari redesain pertama, cuma dipisah garis vertikal tipis
tanpa card/border di sekelilingnya lagi.

Test `test/laporan_export_chip_dropdown_test.dart` diperbarui mengikuti
(cek `Image.asset` via `assetName`, bukan `Icons.picture_as_pdf_rounded`/
`grid_on_rounded` lama; `Icons.ios_share_outlined` bukan `ios_share_rounded`;
assert badge & subtitle lama SUDAH TIDAK ADA). Revert-verified (stash
redesign, 2/3 test baru gagal sensibel thd desain lama sblm 8 Sep, restore,
hijau lagi). `flutter analyze` 0 issue. Full suite hijau (1 gagal
`backup_schema_version_guard_test.dart` di full-run tapi lulus 3/3 saat
diisolasi — flake resource-contention environment, BUKAN regresi, sudah
terjadi berulang kali sepanjang sesi ini akibat banyak worktree/agent
paralel jalan bersamaan, tidak terkait file yang disentuh sesi ini sama
sekali).

## Sesi SEBELUMNYA (10 September) — ekspor PDF/Excel Hutang/Stok/Pengeluaran/Arus Kas + redesain PERTAMA dropdown unduh

Permintaan user (persis, 2 hal terpisah tapi dikerjakan sekaligus):
1. "Ada beberapa tab di laporan yang masih belum ada ekspor pdf dan .xlsx
   nya. Tambahkan hal tersebut sesuai logika kategori laporan
   masing-masing." — 4 tab (Hutang/Stok/Pengeluaran/Arus Kas, index 4-7)
   sebelumnya digerbangi `_canExportCurrentTab` (index < 4). Sekarang
   `ReportTab` diperluas 4→8, tiap tab dapat builder PDF+XLSX sendiri di
   `report_export.dart` (pola persis tab lama). Hutang & Stok = snapshot
   "sekarang" (bukan terikat rentang tanggal, SAMA spt kartu on-screen-nya
   sendiri sudah dokumentasikan) — judul PDF pakai "per [tanggal ekspor]"
   bukan rentang, `range` param tetap ada di signature (tak dipakai tab
   ini, orkestrator `exportReport`/`shareReport` tidak direstrukturisasi).
   Hutang dibatasi 1000 baris PDF/5000 XLSX (Stok/Pengeluaran/Arus Kas tak
   perlu cap — agregat kecil).
2. "Redesign tombol dropdown untuk download ringkasan pdf dan excel...
   Berikan icon juga... icon share juga untuk tiap-tiap chip... jika tekan
   biasa di badan chip, itu akan download ke internal, jika tekan share,
   maka langsung share." — `PopupMenuButton` teks polos lama diganti
   custom (`showMenu` + `PopupMenuItem(enabled:false)` + row 2 `InkWell`
   independen): chip PDF (badge merah `picture_as_pdf_rounded`) & chip
   Excel (badge hijau `grid_on_rounded`), tiap chip py ikon share
   (`ios_share_rounded`) terpisah di ujung (garis vertikal tipis
   memisahkan). Tap badan = unduh (`FilePicker.saveFile`, jalur lama, via
   `exportReport()`). Tap ikon share = `shareReport()` BARU — tulis ke
   temp file lalu `Share.shareXFiles`, TANPA singgah ke storage lokal,
   TANPA dialog tambahan (beda dari `saveOrShareExport` yg dipakai backup/
   CSV — di sini pemilihannya sudah lewat 2 zona tap terpisah, bukan
   dialog). `_buildReportBytes` diekstrak supaya kedua jalur pakai builder
   yg sama persis.

**Sekalian**: PLAN.md Item 47 (disetujui user sebelumnya, "siap eksekusi")
dieksekusi & dihapus dari PLAN.md — ekspor Ringkasan (PDF+XLSX) sebelumnya
TIDAK PERNAH menyertakan "Pengeluaran"/"Laba Bersih" (beda dari tampilan
on-screen `ringkasan_tab.dart` yg sudah py keduanya). `_RingkasanData`/
`_fetchRingkasan` sekarang alirkan `getNetProfitExpenseTotal()`.

**Test baru**: `test/report_export_new_tabs_test.dart` (Tier 1 —
`AppDatabase(NativeDatabase.memory())` sungguhan, 4 tab baru + kasus Item
47 Ringkasan, verifikasi byte PDF magic `%PDF` & XLSX round-trip
`Excel.decodeBytes`, angka benar). `test/laporan_export_chip_dropdown_
test.dart` (Tier 2 widget test — dropdown custom bukan `PopupMenuButton`
lama, chip PDF/Excel + ikon share tampil, tap badan vs ikon share memicu
JALUR KODE BEDA — dibuktikan via pesan error berbeda `FilePicker.
saveFile`/"Gagal export" vs jalur share yg TIDAK pernah munculkan pesan
itu sama sekali dalam window waktu yg sama). SEMUA revert-verified.
`flutter analyze` 0 issue. Full suite: **1610 test lulus, 0 gagal**.

**Keterbatasan test yang disadari**: `Share.shareXFiles`/`getTemporaryDirectory`
sungguhan TIDAK PERNAH resolve di lingkungan `flutter test` ini (tak ada
mock method channel utk `share_plus`/`path_provider`, sama sekali belum
ada precedent-nya di codebase — dicek eksplisit, `backup_share_option_
test.dart` juga sengaja berhenti sebelum titik itu) — test dropdown
TIDAK menunggu sampai tuntas hasil share sungguhan, cukup buktikan
tap-zone yg beda memicu pemanggilan fungsi yg beda (`_export` vs
`_share`).

## Sesi sebelumnya — ekspor CSV produk bisa dibagikan langsung SELESAI

Permintaan user (persis): "Buat ekspor csv produk bisa share juga (sama
seperti file backup)". `_exportProductsCsv` (`pengaturan_screen.dart`)
sebelumnya panggil `FilePicker.platform.saveFile` langsung, tanpa opsi
lain. Diganti pakai helper yang SUDAH ADA `saveOrShareExport`
(`lib/core/utils/export_destination.dart`, sebelumnya dipakai
`backup_screen.dart`/`alih_owner_screen.dart`/`arsip_screen.dart`/
`price_sync_screen.dart`) — muncul dialog pilihan "Bagikan" (share sheet
OS via `share_plus`, tulis ke temp file dulu) atau "Simpan ke Perangkat"
(`FilePicker.saveFile`, alur lama).

`saveOrShareExport` ditambah parameter opsional `title` (default
`'Simpan Backup'` — SEMUA 4 caller lama TIDAK berubah perilaku/teksnya)
karena judul itu misleading kalau dipakai apa adanya utk ekspor CSV
(bukan backup) — dipanggil `title: 'Simpan CSV'` dari pengaturan_screen.
dart. Prefix nama file temp share (`backup_...`) di `export_destination.
dart` SENGAJA TIDAK diubah utk CSV — dicek: itu murni konvensi
penamaan/pembersihan file temp (`TempShareCleanup`), bukan klaim isi
file, jadi aman dipakai lintas jenis ekspor.

**Test baru**: `test/pengaturan_export_csv_share_test.dart` (widget test,
pola PERSIS `backup_share_option_test.dart` — tap "Export Produk CSV" →
dialog "Simpan CSV" dgn tombol Bagikan & Simpan ke Perangkat muncul,
Batal menutup tanpa memanggil plugin apa pun). Revert-verified (gagal
dgn `findsNothing` utk teks "Simpan CSV" sblm fix). `flutter analyze` 0
issue. Full suite: **1602 test lulus, 0 gagal** (naik dari 1601 — +1
test file baru).

## Sesi sebelumnya — fix kembalian pre-checkout Pra-Bayar TERUS terhitung setelah Tambah Belanjaan SELESAI

**Bug dilaporkan user** (kata-kata persis): "ketika kembalian dari
pre-paid sudah diambil, kemudian paid, dan ternyata tambah barang dan ada
kembalian, total kembalian dihitung bahkan dari fase pre-paid (yang tentu
uang itu sudah di pelanggan). Ini bug serius karena kasir akan bayar
kembalian lebih (yang sebelumnya sudah diberikan kepada pelanggan) jika
tidak aware." Regresi dari fix sesi lalu (`22ba425`) — ringkasan atas
struk (in-app, share/gambar, cetak) menjumlah `prabayarChangeTakenBeforeCheckout`
dari SEMUA baris payment TANPA syarat, termasuk baris ronde checkout ASLI
yang sudah tuntas/historis begitu ada ronde "Tambah Belanjaan" berikutnya
pada nota yang sama.

**Kenapa heuristik timestamp/jumlah-baris TIDAK dipakai**: ronde checkout
ASLI sendiri BISA punya banyak baris payment (beberapa entri Pra-Bayar +
satu baris "sekarang") yang semuanya SAH ikut dihitung — jadi "kalau >=2
baris, exclude" salah. `paidAt` juga tidak bisa dipakai sbg urutan
andal: baris "sekarang" ronde ASLI sendiri `paidAt`-nya (submission
checkout) ALAMI lebih baru dari baris Pra-Bayar (`lockedAt`) di ronde yang
SAMA — jadi tidak bisa dibedakan dari ronde Tambah Belanjaan yang
sungguhan lebih baru pakai timestamp saja.

**Fix**: `_confirmAddItems` (payment_screen.dart, alur "Tambah
Belanjaan") menulis baris payment dgn marker `note: 'Tambah belanjaan'`
(SATU-SATUNYA tempat literal ini ditulis sbg payment note di codebase) &
TIDAK PERNAH set `prabayarChangeTakenBeforeCheckout` (field itu eksklusif
milik ronde checkout asli). Jadi: keberadaan >=1 baris non-voided dgn
`note == 'Tambah belanjaan'` = ronde asli sudah tertutup/historis →
`totalPrabayarChangeTakenBeforeCheckout()` (`receipt_screen.dart`)
kembalikan 0 utk kasus itu (helper baru `_hasLaterAddItemsRound`).
Duplikat inline yg sama diperbaiki di `printer_service.dart`: builder
struk tunggal (~line 980) & builder nota gabungan (~line 1422, per-tx
scoped). `_buildPaymentTimeline`/Riwayat Pembayaran per-baris — TIDAK
disentuh, tetap benar menampilkan histori tiap ronde apa adanya.
`_latestPayment?.changeGiven` (kembalian ronde SAAT INI) — TIDAK disentuh,
sudah benar & tidak bawa `prabayarChangeTakenBeforeCheckout` di baris
Tambah Belanjaan mana pun (ronde ke-2, ke-3, dst — tidak perlu
special-case tambahan).

**Test baru**: `test/receipt_prabayar_change_taken_after_add_items_test.dart`
(4 test: fungsi murni skenario bug persis + regresi tanpa Tambah
Belanjaan, in-app Ringkasan atas, cetak ESC/POS struk tunggal). Revert-
verified (3 skenario-bug gagal dgn nilai lama 105150/breakdown row yg
seharusnya sudah tidak ada/`Rp 220,900` sblm fix — 1 test regresi tetap
hijau krn memang tidak disentuh bug ini). Builder nota GABUNGAN diperbaiki
di kode tapi TIDAK ada test baru menyentuhnya langsung — codebase belum
punya `visibleForTesting` debug-hook utk builder gabungan (beda dari
`debugBuildBytes` struk tunggal), sama seperti keterbatasan yg sudah
dicatat di sesi sebelumnya. `flutter analyze` 0 issue. Full suite:
**1601 test lulus, 0 gagal**.

## Sesi sebelumnya — fix kembalian pre-checkout Pra-Bayar tidak terhitung di Ringkasan atas struk SELESAI

**Bug dilaporkan user** (screenshot): Pra-Bayar dikunci, kembalian Rp200
diambil SEBELUM checkout → Ringkasan atas struk in-app menampilkan
"Total" & "Dibayar" SAMA-SAMA persis Total, TANPA baris "Kembalian" sama
sekali — padahal Riwayat Pembayaran di bawahnya (sudah benar sejak fix
sesi lalu, `191570c`) menampilkan "Tunai Rp 254.000" + catatan
"Kembalian Rp 200 sudah diambil sebelum checkout".

**Akar masalah**: `dibayarDisplay(tx, payments, kembalian)` dipanggil dgn
`_latestPayment?.changeGiven ?? 0` SAJA — TIDAK PERNAH
mempertimbangkan `TransactionPayments.prabayarChangeTakenBeforeCheckout`
(kolom TERPISAH, dari baris Pra-Bayar yg BUKAN pembayaran terakhir). Utk
nota yg SEMUA kembaliannya dari potongan pre-checkout (bukan
`changeGiven` momen checkout), `kembalian` param = 0 → jatuh ke
`netPaidDisplay` (= Total, TANPA baris Kembalian).

**Fix**: fungsi baru `totalPrabayarChangeTakenBeforeCheckout(payments)`
(SUM SEMUA baris payment non-voided, BUKAN cuma baris terakhir spt
`latestChangeGiven`) digabung dgn komponen checkout-moment di 3 tempat:
- **In-app** (`_ReceiptScreenState`): getter `_kembalianGabungan` dipakai
  utk argumen `dibayarDisplay`. Baris "Kembalian" checkout-moment
  (`_ChangeTakenRow`, checkbox toggle) TIDAK berubah. Ditambah baris BARU
  terpisah (italic, TANPA checkbox, label "Kembalian (sebelum checkout,
  sudah diambil)") yang muncul saat `_totalPrabayarChangeTakenBeforeCheckout
  > 0` — **keputusan desain**: breakdown 2 baris terpisah, BUKAN digabung
  jadi 1 angka buta, supaya checkbox toggle (yg cuma valid utk komponen
  checkout-moment) tidak jadi salah kaprah bisa di-uncheck utk bagian yg
  sebenarnya sudah PASTI diambil (checkbox pre-checkout-nya sudah ditekan
  kasir sebelum layar struk ini pernah ada).
- **Share/gambar** (`_ReceiptPaper`): `kembalianGabungan` lokal = fix
  analog, dipakai di baris "Bayar.."/"Kembali" (TIDAK ada breakdown 2
  baris di sini — widget ini sudah tidak py breakdown per-payment sama
  sekali, konsisten dgn desain sebelumnya).
- **Cetak ESC/POS** (`printer_service.dart`): struk tunggal & nota
  gabungan — pola sama (`kembalianGabungan`/`grandKembalian`).

**Test**: `test/receipt_prabayar_change_taken_summary_test.dart` (7
test: skenario user in-app+share+cetak, regresi kembalian normal, KOMBINASI
checkout-moment+pre-checkout sekaligus). Semua revert-verified (6/7 gagal
dgn pesan masuk akal sblm fix — 1 test regresi murni tetap hijau krn
memang tidak disentuh bug ini). `flutter analyze` 0 issue. Full suite:
**1597 test lulus, 0 gagal**.

**Scope TIDAK disentuh**: `_buildMergedBytes`/`printMergedReceipt` (ESC/POS
nota gabungan) diperbaiki di kode tapi TIDAK ada test baru menyentuhnya —
codebase ini belum py `visibleForTesting` debug-hook utk builder gabungan
(beda dari `debugBuildBytes` struk tunggal), jadi tidak ada precedent test
existing utk dipakai; menambah hook baru di luar scope bug ini.

## Sesi sebelumnya — fix nominal utama struk Pra-Bayar dipotong diam-diam oleh kembalian pre-checkout SELESAI

**Bug dilaporkan user** (2 screenshot: keranjang & struk): Pra-Bayar
dikunci Rp426.000, kembalian Rp600 diambil SEBELUM checkout (fitur
"kembalian sudah diambil" di footer keranjang) → struk/Riwayat
Pembayaran menampilkan **"Tunai Rp 425.400"** (426.000 dikurangi 600)
sbg nominal utama, padahal yang BENAR-BENAR dikunci/diterima kasir
adalah Rp426.000. Potongan 600 seharusnya cuma catatan terpisah — persis
pola `changeGiven` pada pembayaran normal (nominal utama TETAP gross
tendered, kembalian di baris terpisah di bawahnya).

**Akar masalah**: `buildPrabayarCheckout` (`payment_screen.dart`)
menulis `TransactionPaymentsCompanion.amount` sbg `entry.amount - cut`
(dipotong duluan), BEDA dari pola baris "sekarang" yang pakai `amount`
GROSS + `changeGiven` terpisah.

**Fix**: `amount` yang ditulis SEKARANG selalu `entry.amount` (gross
ASLI), TIDAK PERNAH dipotong. Kolom `prabayarChangeTakenBeforeCheckout`
(sudah ada, TIDAK ada migrasi baru) tetap merekam berapa yang dipotong,
tapi maknanya jadi metadata TERPISAH murni (analog PERSIS `changeGiven`)
— bukan lagi pengurang `amount`.

**Invariant BARU** (mengganti invariant lama `Σ amount == combinedPaid`,
yang PECAH krn `amount` skrg gross):
`Σ (amount - changeGiven - prabayarChangeTakenBeforeCheckout) == combinedPaid`.

**Titik yang ikut disesuaikan** (invariant lama pecah):
- `getTodayCashRecap` (Tutup Kasir): bucket `cash` sekarang JUGA
  mengurangi `prabayar_change_taken_before_checkout`, PERSIS perlakuan
  `change_given` (potongan pre-checkout ini SELALU fisik tunai, terlepas
  metode ASLI baris itu) — tanpa ini `cash` over-count.
- `getCashInByMethod`/`getCashFlowDaily` (Arus Kas): net PER-METHOD juga
  dikurangi kolom yang sama (konsisten dgn `change_given` yang sudah net
  per-method di situ).
- `netPaidDisplay`/`grossReceived` (`receipt_screen.dart`) **TIDAK
  diubah** — `tx.paid` (`combinedPaid`) sudah dihitung NET dari
  `poolTersedia` SEBELUM proses alokasi ke baris individual, jadi
  independen dari cara `amount` per baris ditulis. Diverifikasi eksplisit
  via test, bukan asumsi.
- Riwayat Pembayaran in-app (`_buildPaymentTimeline`) & struk cetak/share
  (`printer_service.dart`, `_ReceiptPaper` di `receipt_screen.dart`) —
  **TIDAK perlu ubah kode**, keduanya sudah menampilkan `p.amount` apa
  adanya (termasuk timeline "Pembayaran:" di struk cetak & gambar share,
  DIVERIFIKASI langsung — bukan asumsi "cuma ringkasan") — begitu
  `amount` tersimpan benar, tampilan otomatis benar.

**Test**: `test/payment_prabayar_checkout_test.dart` (semua assersi
invariant lama diupdate ke rumus baru + skenario persis 426.000/600
ditambahkan), `test/receipt_prabayar_change_taken_before_checkout_test.dart`
(widget test skenario user), `test/tutup_kasir_recap_paid_at_test.dart`
(+2 test cash recap). Semua revert-verified (gagal dgn pesan masuk akal
sblm fix, hijau lagi setelah). `flutter analyze` 0 issue. Full suite:
**1590 test lulus, 0 gagal**.

## Sesi sebelumnya — fix Tutup Kasir tidak net dari kembalian (`change_given`) SELESAI

`getTodayCashRecap` (baru diperbaiki commit `3004bcb` sesi lalu utk basis
`paid_at`) masih menjumlahkan `tp.amount` MENTAH (gross tendered) TANPA
mengurangi `TransactionPayments.changeGiven` — tiap transaksi berkembalian
membengkakkan rekap kas Tutup Kasir sebesar kembaliannya (uang itu sudah
keluar lagi ke pembeli, tidak pernah benar-benar mengendap di laci).

**Keputusan desain penting** (dicek hati-hati, JANGAN diubah tanpa
verifikasi ulang sekuat ini): kembalian di app ini SELALU diserahkan FISIK
TUNAI dari laci, apa pun metode pembayaran ASLI baris yang menghasilkannya
— sejak Item 62, kalkulator kembalian dipakai SAMA utk tunai maupun
non-tunai (`payment_screen.dart` `_paid`/`_tendered`), jadi transfer/QRIS
kelebihan bayar BISA menghasilkan `changeGiven` juga, dan app ini TIDAK
PUNYA mekanisme "kembalikan lewat rekening lagi" — fisiknya pasti tunai.
Karena itu:
- `cash` = `SUM(amount WHERE method='tunai')` **DIKURANGI SELURUH
  `change_given` LINTAS SEMUA METODE** (bukan cuma dari baris method
  'tunai' sendiri) — kalau satu-satunya pembayaran hari itu adalah
  transfer 100rb dgn kembalian tunai 20rb, `cash` jadi **-20000** (VALID,
  JANGAN di-floor ke 0 — itu representasi tunai laci net berkurang).
- `nonCash` = `SUM(amount WHERE method NOT IN ('tunai','tempo'))` **UTUH,
  TIDAK dikurangi** — uang transfer/QRIS masuk penuh ke rekening/dompet,
  tidak berkurang oleh kembalian yang keluar via laci tunai.
- Baris marker retur/edit nota BELUM-LUNAS (`method` 'retur'/'edit',
  `amount=0`, jejak audit "retur nota belum lunas" — lihat
  `_isReturLinkedPayment` di `receipt_screen.dart`) **DIKECUALIKAN** dari
  pengurangan `change_given` — nilainya di baris itu murni metadata utk
  histori/rekonsiliasi hutang, BUKAN uang yang sungguhan keluar laci HARI
  itu (refund SUNGGUHAN nota lunas pakai `amount` NEGATIF dgn `method`
  nyata, `changeGiven` default 0 — tidak kena masalah ini).
- **SENGAJA beda** dari `getCashInByMethod`/`getCashFlowSummary` (tab Arus
  Kas, `app_database.dart` ~line 5714) yang net `change_given` per BUCKET
  METODE ASALNYA SENDIRI (`GROUP BY method`) — itu laporan akuntansi "nilai
  bersih tiap kanal pembayaran", tujuannya beda dari `getTodayCashRecap`
  yang REKONSILIASI FISIK LACI (`tutup_kasir_screen.dart` membandingkan
  `physical - recap.cash` — kasir menghitung uang FISIK di tangan). Dua
  fungsi ini BOLEH & MEMANG SEHARUSNYA menghasilkan angka tunai yang beda
  utk hari yg sama kalau ada transaksi non-tunai berkembalian-tunai —
  bukan inkonsistensi, tapi pertanyaan yang beda-beda yang dijawab.

**Test baru**: `test/tutup_kasir_recap_paid_at_test.dart` (+3 test: tunai
berkembalian → net bukan gross; transfer berkembalian tunai → nonCash
utuh + cash negatif; marker retur/edit → changeGiven metadata TIDAK
dipotong). Revert-verify: 2 dari 3 gagal dgn angka gross yg salah sblm
fix (test marker retur sudah lolos bahkan tanpa fix krn method-nya bukan
'tunai', jadi tidak masuk hitungan `cash` sama sekali di query lama —
tetap dipertahankan sbg regression guard eksplisit thd fix ini sendiri).
`flutter analyze` 0 issue. Full suite: **1586 test lulus, 0 gagal**.

## Sesi sebelumnya — chip Kategori Harga per-item, fix reset toggle, redesain sheet Pengaturan Keranjang, fix Tutup Kasir (paid_at) SELESAI

1. **Chip Kategori Harga per-item di baris keranjang** (fitur BARU) — baris
   produk yg tergabung >=1 `PriceCategories` (dicek via `AltPrices.priceCategoryId`
   utk `productUnitId` baris itu) menampilkan deretan chip PENUH per
   kategori + "Normal" di dekat subtotal, scrollable horizontal
   (`SingleChildScrollView`, BUKAN wrap — baris tidak melebar ke bawah).
   Tap chip → `_ItemPriceCategoryChips._apply` (`cart_sheet.dart`) resolve
   harga via `PriceService.resolvePrice(activeCategoryId: ...)` lalu
   `notifier.setItem(item.copyWith(..., priceOverridden: true))` — SENGAJA
   reuse invariant `priceOverridden` yg sudah ada (BUKAN mekanisme baru)
   supaya `repriceCartForCategoryChange` (dipanggil toggle HEADER, fitur
   lama tidak berubah) otomatis skip baris ini selamanya sampai diubah
   manual lagi — urutan prioritas manual > header konsisten tanpa
   perubahan ke fungsi itu. Chip per-item digerbangi izin
   `override_harga` sama beratnya dgn toggle header (`canOverrideHargaProvider`)
   krn sama-sama mengubah harga jual. Toggle on/off seluruh fitur ini =
   `cartPriceCategoryChipsProvider` (`theme_provider.dart`, persisted
   SharedPreferences, default ON), dikontrol dari sheet Pengaturan
   Keranjang (lihat #3). Badge kecil "harga dari kategori"
   (`Icons.sell_outlined`) di baris nama produk SEKARANG dicek DULUAN
   sebelum badge `priceOverridden` (`Icons.edit`) — chip per-item skrg BISA
   set keduanya sekaligus (beda dari sebelumnya yg saling eksklusif).
   DB baru: `AppDatabase.getPriceCategoriesForProductUnit()`. Di
   `item_entry_sheet.dart`, chip Kategori Harga di `_priceOptions()` diberi
   aksen `scheme.tertiary` + ikon `sell_outlined` (beda dari chip Harga
   Lain biasa).

2. **Fix reset toggle kategori header antar-transaksi** (BUG) —
   `cartPriceCategoryProvider(kMainCartId)` singleton per-cartId (bukan
   per-transaksi) nempel ke transaksi berikutnya. `clear()` ditambahkan di
   `payment_screen.dart` (setelah checkout sukses & setelah tambah
   belanjaan) dan `cart_sheet.dart::_confirmClear` (kosongkan manual).

3. **Redesain sheet "Pengaturan Keranjang"** — dari `AlertDialog` generik
   ke bottom sheet custom (gaya SAMA PERSIS "Pengaturan Struk"
   `receipt_screen.dart::_showReceiptSettingsSheet`: handle bar, judul+ikon
   aksen, `SwitchListTile` dgn leading `CircleAvatar`). Isi lama (posisi
   checkbox verifikasi, konfirmasi minus qty) dipertahankan PLUS toggle
   baru dari #1.

4. **Fix Tutup Kasir salah hitung kas** (BUG NYATA) —
   `getTodayCashRecap` (`app_database.dart`) sebelumnya basis
   `transactions.created_at`/`paid` (tanggal NOTA DIBUAT + kumulatif
   nota) — nota yg dibuat kemarin tapi dilunasi HARI INI (mis. pre-order
   DP 0, dilunasi saat pengambilan) TIDAK PERNAH muncul di rekonsiliasi
   kas hari pelunasan. Diganti JOIN `transaction_payments`
   (`paid_at`/`amount` per baris pembayaran SUNGGUHAN, dikelompokkan per
   `method` baris pembayaran, exclude `voided` & transaksi `status='void'`
   saat ini). **Temuan verifikasi**: `'tempo'` TIDAK PERNAH muncul sbg
   `method` di `transaction_payments` (tempo = belum ada uang masuk, tidak
   ada baris payment sama sekali — dikonfirmasi lewat grep seluruh titik
   `into(transactionPayments).insert(...)` di codebase, semua method yg
   ditulis adalah metode pembayaran nyata atau `'retur'`/`'edit'` dgn
   `amount=0` sbg jejak audit) — jadi filter exclude `'tempo'` di query
   tetap dipertahankan sbg guard defensif (murni jaga-jaga, bukan krn
   pernah ditemukan kasusnya) tanpa exclude tambahan yg tidak perlu utk
   `'retur'`/`'edit'` (amount=0 otomatis tidak menyumbang SUM apa pun).
   `readsFrom: {transactions, transactionPayments}` (2 tabel). Query ini
   `Future` (bukan `Stream`) jadi tidak ada isu reactivity `.watch()`.

**Regresi test lama akibat interaksi fitur baru** (SUDAH diperbaiki, bukan
dibiarkan): `cart_sheet_price_category_toggle_test.dart` (scope finder ke
`ChoiceChip` supaya tidak bentrok label dgn chip per-item baru di baris
yg sama), `cart_minus_confirm_test.dart` (scope `Switch` finder ke
`SwitchListTile` spesifik, sheet skrg py 2 Switch), `cash_closing_test.dart`
(basis `transaction_payments`, txCount nota tempo tanpa pembayaran turun
4→3 sesuai perilaku baru yg benar).

**Test baru**: `test/tutup_kasir_recap_paid_at_test.dart` (5, WAJIB
buktikan bug asli via revert-verify — nota created_at kemarin + payment
paid_at hari ini), `test/cart_price_category_reset_test.dart` (2, checkout
sukses & kosongkan manual mereset toggle header),
`test/price_categories_for_product_unit_test.dart` (5, query DB murni),
`test/cart_item_price_category_chips_test.dart` (5, widget: chip hanya
tampil produk berkategori, scroll horizontal, tap override, toggle off),
`test/cart_settings_sheet_redesign_test.dart` (2, sheet baru + toggle).
SEMUA revert-verified. `flutter analyze` 0 issue. Full suite: **1581 test
lulus, 0 gagal** (2 test lain gagal HANYA saat full-suite paralel —
`proposal_unchanged_end_to_end_test.dart` — dan lolos bersih saat
dijalankan terisolasi, flake pre-existing bukan regresi dari sesi ini).
Commits `3004bcb`, `c2eae64`, `786fe9e`, `83ed2d0`. Push ke
`claude/kategori-produk-qty-harga-mqjh21` lalu merge ke `main`.

## Sesi sebelumnya — gabung "Total"/"Dibayar" dgn nota hutang di struk SELESAI

User kirim screenshot: baris "Lunasi Nota #X" sudah menyatu ke list item
struk (redesain ketiga, sesi lalu), TAPI baris "Total"/"Total akhir" &
"Dibayar" di ringkasan bawah TIDAK ikut menjumlahkan nominal nota hutang —
cuma `tx.total`/`tx.paid` mentah (item saja). Contoh: item Rp 212.400 +
Lunasi Nota #16 Rp 690.000 seharusnya Total Rp 902.400, tapi cuma tampil
Rp 212.400.

**Fix** (MURNI tampilan — `tx.total`/`tx.paid` TIDAK disentuh sama sekali,
Laporan/kalkulasi lain aman): getter/variabel baru `_debtSettlementTotal`
(in-app & `_ReceiptPaper`, `receipt_screen.dart`) / `debtSettlementTotal`
(`printer_service.dart`) = sum nominal `_debtSettlementLines`, ditambahkan
ke:
- In-app: `_SummaryRow('Total'/'Total akhir', ...)` & `_SummaryRow
  ('Dibayar', ...)`.
- Share/gambar (`_ReceiptPaper`): baris "Total"/"Akhir" & "Bayar..".
- Cetak ESC/POS: baris "Total"/"Total akhir" & "Bayar".

**SENGAJA TIDAK ikut ditambah** (basis lama sudah benar):
- **Poin loyalitas** (`tx.pointsEarned`) — dihitung backend dari
  pembelian barang saja, pelunasan hutang lama bukan pembelian baru.
- **"Sisa Tagihan"** (`netRemainingOwed`, in-app) & baris "Sisa" (share/
  cetak, dari `tx.total - netPaid` mentah) — sisa tagihan nota INI
  sendiri, nota hutang yg dilunasi justru uang yg SUDAH diterima
  (kombinasi kurang_bayar+debt-settlement diverifikasi test eksplisit,
  tidak perlu penanganan khusus tambahan — `netRemainingOwed`/baris
  "Sisa" sudah otomatis benar krn tidak pernah menyentuh
  `debtSettlementTotal`).

**Test baru**: `test/receipt_debt_settlement_total_paid_test.dart` (6
test: in-app Total+Dibayar gabung, share/gambar gabung, cetak ESC/POS
gabung, regresi nota tanpa hutang tidak berubah, poin TIDAK ikut naik,
kombinasi kurang_bayar+hutang — Sisa Tagihan murni item sendiri).
Revert-verified (4 dari 6 test gagal dgn pesan relevan saat fix di-stash,
2 sisanya — regresi & poin — tetap hijau krn memang tidak disentuh fix
ini). `flutter analyze` 0 issue. Full suite: **1564 test lulus, 0 gagal**.
Commit `5e7f737`.

## Sesi sebelumnya — sejajarkan baris "Lunasi Nota #X" dgn baris produk (struk in-app) SELESAI

User kirim screenshot: baris "Lunasi Nota #19" di struk IN-APP TIDAK
sejajar kolom dgn baris produk di atasnya (`_DebtSettlementSummaryRow`
sebelumnya cuma `Padding`+`Row` polos tanpa leading/indent, sementara
baris produk pakai `ListTile`). Fix: `_DebtSettlementSummaryRow` jadi
`ListTile` juga (contentPadding/dense sama persis `_itemCheckRow`
non-varian, leading ikon `Icons.receipt_long_outlined` dibungkus SizedBox
lebar sama dgn Checkbox produk). Warna aksen (`scheme.tertiary`) tetap
dibedakan dari produk — user: "boleh dibedakan asal simetris", prioritas
alignment bukan warna. Kode nota LENGKAP (`invoiceLocalId`) dipindah jadi
"catatan item" via `_Blockquote` (reuse widget `item.itemNote` produk) —
judul tetap `shortLabel` ringkas. Hyperlink ke nota asal tetap
dipertahankan (test baru membuktikan tap-nya sungguhan navigasi). Konsisten
di share/gambar (`_ReceiptPaper`) & cetak ESC/POS (`printer_service.dart`):
baris catatan "* Nota asal: <localId>" italic ditambahkan.

Test baru: `test/receipt_debt_settlement_row_alignment_test.dart` (5 test,
revert-verified). `flutter analyze` 0 issue, `flutter test` 1558 lulus.
Commit `e64dba3`.

**Catatan proses**: sesi kerja untuk task ini SEMPAT TERPUTUS krn container
di-restart di tengah eksekusi agen background — untungnya worktree agen
survive restart (file edit tidak hilang), jadi pekerjaan dilanjutkan
langsung dari situ (bukan mulai ulang) begitu ketahuan lewat notifikasi
"container restarted".

## Sesi sebelumnya — redesain KETIGA "Lunasi Hutang" (struk) SELESAI

Lanjutan redesain kedua (sesi 36, di bawah). User minta: baris nota lama yg
ikut dilunasi di struk (in-app/share-gambar/cetak ESC/POS) tidak lagi
bagian TERPISAH berheader "Turut melunasi hutang:"/"Turut lunasi hutang:"
di bawah Total — harus MENYATU LANGSUNG ke list item produk (baris
terakhir, SEBELUM Total), jadi satu daftar tunggal dgn satu angka Total yg
menjumlahkan semuanya. MURNI perubahan presentasi/urutan render —
logika angka (`saveTransactionWithDebtSettlements`/`settleMergedDebt`/
`payment_screen.dart`) **TIDAK DISENTUH SAMA SEKALI**.

**Perubahan:**
1. `DebtSettlementDetailLine.shortLabel` (getter baru, `app_database.dart`)
   — satu sumber kebenaran format nama singkat "Lunasi Nota #12" (segmen
   terakhir `invoiceLocalId`, pola sama `CartMeta.displayOrderNumber`),
   menggantikan "Nota K1-20260907-0012" (localId penuh, verbose). Dipakai
   ketiga tempat di bawah.
2. In-app (`receipt_screen.dart` `_buildItemRows`) — baris hutang
   (`_DebtSettlementSummaryRow`, hyperlink TETAP ADA) dipindah dari dalam
   `Padding` ringkasan SETELAH Total ke akhir `rows` (list item), SEBELUM
   `Divider`. Teks jadi `line.shortLabel`.
3. Share/gambar (`_ReceiptPaper`) — dipindah dari section `_DashedLine`
   terpisah (setelah Refund/sebelum Timeline) ke akhir
   `_ordered.expand(...)`, SEBELUM `_DashedLine` ke ringkasan Total. Style
   font disamakan persis dgn baris item produk (bukan lagi fontSize 11.5
   custom).
4. ESC/POS (`printer_service.dart`) — dipindah dari dalam blok
   `showPaymentDetail` (setelah Bayar/Kembali/Sisa) ke akhir loop item,
   SEBELUM `bodySep()` yg memisahkan item dari Total. Gating
   `settings.showPaymentDetail` DIPERTAHANKAN (parity perilaku lama,
   bukan perubahan logika baru).
5. Header section lama ("Turut melunasi hutang:"/"Turut lunasi hutang:")
   DIHAPUS di ketiga tempat — konteks sudah jelas dari nama baris itu
   sendiri ("Lunasi Nota #X") yg kini langsung di antara barang.

**Test baru**: `test/receipt_debt_settlement_merged_list_test.dart` (2
test — in-app: baris "Lunasi Nota #12" jadi SIBLING `ListTile` item produk
dlm `Column` yg sama, header lama TIDAK ADA; share/gambar: sama, tanpa
header). `test/printer_service_debt_settlement_merged_test.dart` (1 test,
pakai `test()` polos + `TestWidgetsFlutterBinding.ensureInitialized()`
manual, BUKAN `testWidgets()` — lihat gotcha di bawah — verifikasi byte
ESC/POS: nama singkat muncul SEBELUM "Total", localId penuh & header lama
tidak ada). Revert-verify dibuktikan (stash fix → ketiga test gagal dgn
pesan relevan → fix dikembalikan, hijau lagi).

**Gotcha BARU ditemukan sesi ini**: test yg memanggil
`PrinterService.debugBuildBytes` (builder ESC/POS, load `CapabilityProfile`
via `rootBundle.loadString`) **HANG SAMPAI TIMEOUT 10 MENIT** kalau dibungkus
`testWidgets()` TANPA `tester.pump()` sama sekali (test murni logic/bytes,
tidak pump widget apa pun). Fix: pakai `test()` polos +
`TestWidgetsFlutterBinding.ensureInitialized()` manual di awal `main()`
(supaya `rootBundle` tetap bisa baca asset test) — BUKAN `testWidgets()`.
Perlu ditambahkan ke CLAUDE.md §Gotcha kalau kejadian lagi di test lain yg
menyentuh `PrinterService`.

Full suite penuh (bukan cuma file baru): **1555 test lulus, 0 gagal**.
`flutter analyze`: **0 issue**.

## Sesi sebelumnya — redesain KEDUA "Lunasi Hutang" (ringkas)

Entry point pindah dari toggle di list produk ke chip pengingat hutang yg
sudah ada (tap → sheet "Pilih Nota untuk Dilunasi",
`widgets/debt_settlement_sheet.dart`), checklist per-nota (bukan agregat
FIFO lagi). `DebtSettlementEntry` restruktur: SATU entri = SATU nota
sumber (`invoiceId`/`invoiceLocalId`/`invoiceDate`). Entri aktif tampil
sbg baris terpisah di keranjang (`_DebtSettlementEntryRow`), Total
keranjang = belanja + SUM entri aktif. `DebtSettlementDetailLine`/
`parseDebtSettlementDetail` (`app_database.dart`) tambah field nullable
`invoiceId`+`invoiceDate`. Detail lengkap: `466a51d` di CHANGELOG.md.

## Sesi sebelumnya (ringkas — detail lengkap di CHANGELOG.md)

- **7 September, sesi ketiga puluh lima** (`183dd29`): Ekspor Arsip Tahunan
  terpisah dari backup biasa.
- **7 September, sesi ketiga puluh empat** (`0d739f6`): fix
  `price_categories` tidak ikut sync LAN & backup penuh.
- **7 September, sesi ketiga puluh tiga** (`b3bab3f`): fix "Batalkan &
  Susun Ulang" tidak membawa nama pelanggan terdaftar.
- **7 September, sesi ketiga puluh dua** (`a254152`): redesain PERTAMA
  toggle otomatis "Lunasi Hutang" — SUDAH DIGANTIKAN redesain kedua sesi
  ini, `_DebtSettlementCartRow` tidak ada lagi.

## Keputusan/pola penting yang masih berlaku (ringkas — detail di CLAUDE.md)

- Cart provider = family per `cartId` (`kMainCartId`/`kCatalogCartId`/`txId`).
  Jangan buat provider keranjang global baru.
- **"Lunasi Hutang"**: SATU `DebtSettlementEntry` = SATU nota sumber (lihat
  detail di atas) — kalau mau ubah lagi, JANGAN kembalikan pola agregat
  FIFO lintas-nota (`planFifoSettlement`) tanpa alasan kuat, backend
  `settleMergedDebt` tetap generik menerima banyak target per grup jadi
  keduanya sebenarnya bisa dipetakan, tapi UI SEKARANG per-nota eksplisit
  sesuai permintaan user (partial per-nota).
- Tabel master-data BARU WAJIB langsung dicek masuk ke 3 tempat:
  `_allTables` (backup), `masterData` di `dumpSince` (sync harian), DAN
  `LanSyncService.clientMergeableTables` (allowlist sisi klien) — lupa
  salah satu = data itu diam-diam tidak pernah sampai ke device lain.
- Tabel yang mendukung DELETE oleh user WAJIB tombstone (kolom nullable
  jadi penanda), BUKAN hard delete, kalau mau ikut full-dump sync
  satu-arah host->klien.
- Format file ekspor terenkripsi (`.berkahpos`/`.posarsip`) SEMUA pakai
  pola sama: magic bytes 5-byte unik + salt(16) + IV(16) + AES(gzip(JSON)),
  key dari `CryptoService.derivePortableKeyV2(password, salt)`. Tiap
  format BARU dgn payload/tujuan beda WAJIB magic & fungsi terpisah
  (bukan flag) — lihat dok kelas `DbExportService` utk daftar lengkap &
  alasan tiap pemisahan (BPOS1/BPOSP/BPOP2/BPOT1/BPRC1/BPOA1).
- `Directory.list()`/`File.copy()` (dart:io async isolate-based I/O) HANG
  TANPA BATAS di dalam `testWidgets` sandbox lingkungan CI ini —
  `NativeDatabase`/FFI aman. Screen yang bergantung padanya butuh provider
  override di widget test (contoh: `archiveListProvider`,
  `pumpWithFakeApp(..., extraOverrides: [...])`).
- Menaikkan `schemaVersion` WAJIB memutakhirkan assersi
  `PRAGMA user_version` hardcoded di SEMUA `test/migration_v*_test.dart`
  lama ke versi baru.
- `CartMeta.hasCustomer` cuma cek `customerName`, BUKAN `customerId`.
- `Transactions.customerName` SENGAJA null utk pelanggan TERDAFTAR.
- Gerbang lisensi (`license_provider.dart`/`license_service.dart`) — Ed25519
  murni-Dart, public key developer KOSONG = kill-switch aman (jangan hapus).
- `PriceMatchService` (sinkron harga antar-toko independen) — fuzzy-matching
  SENGAJA dihapus total, jangan ditambah lagi tanpa justifikasi baru.
- Barcode non-13-digit adalah kasus UTAMA (mayoritas data toko nyata), bukan
  edge case — kode label/sync/generator WAJIB anggap itu normal.
- Soft-delete/update master-data WAJIB cap ulang `updated_at` eksplisit;
  raw SQL write WAJIB sertakan `updates: {table}` biar StreamProvider refresh.
- Lihat CLAUDE.md §Gotcha untuk daftar lengkap jebakan yang sudah pernah
  kejadian (HID scanner, TextDirection PDF, DateFormat locale, tombol Row
  overflow, Clipboard mock, dll) — SEMUA masih berlaku, belum ada yg dicabut.

## Item PLAN.md yang masih menggantung

Lihat [PLAN.md](../PLAN.md) langsung untuk detail teknis lengkap tiap
item — ringkasan judul saja di sini (jangan diduplikasi, biar tidak
basi): Item 48 (warna avatar produk kasir dibuat soft/pastel — siap
eksekusi), Item 41 sisa B.1/C.2/P3, Item 23 sebagian (scope Buku Hutang/
Tutup Kasir), Item 28 (lanjutkan pesanan lintas device, masih konsep),
Item 54 (opsi sync LAN otomatis — murni didiskusikan, user pilih tetap
manual utk sekarang, tidak ada rencana eksekusi). Item 47 SUDAH SELESAI
sesi ini (lihat atas) — dihapus dari daftar.
