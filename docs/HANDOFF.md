# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 8 September 2026 (sesi keempat puluh — chip Kategori Harga
per-item di keranjang, fix reset toggle kategori header antar-transaksi,
redesain sheet Pengaturan Keranjang, fix Tutup Kasir salah hitung kas).
Versi kerja **2.54.0+112** (MINOR — ada fitur baru terlihat pengguna, PATCH
reset 0). schemaVersion **43** (tidak berubah — semua fitur sesi ini murni
provider/query baru, tanpa migrasi)._

## Sesi ini — 4 item independen SELESAI

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
basi): Item 47 (Pengeluaran belum ikut ekspor PDF/Excel Laporan — root
cause+fix sudah jelas, siap eksekusi), Item 48 (warna avatar produk kasir
dibuat soft/pastel — siap eksekusi), Item 41 sisa B.1/C.2/P3, Item 23
sebagian (scope Buku Hutang/Tutup Kasir), Item 28 (lanjutkan pesanan
lintas device, masih konsep), Item 54 (opsi sync LAN otomatis — murni
didiskusikan, user pilih tetap manual utk sekarang, tidak ada rencana
eksekusi).
