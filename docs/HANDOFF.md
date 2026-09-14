# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 15 September 2026, sesi keenam puluh delapan — Item 73
SELESAI (tombol hapus eksplisit Kategori Harga). Commit `b0f2da1`. Versi
kerja **2.66.2+141** (PATCH — bugfix UX kecil, ADA entri PATCHNOTES.md).
schemaVersion TETAP **44** (murni UI, `deletePriceCategory` sudah ada
sebelumnya, tidak disentuh).

**Item 73** — hapus Kategori Harga dulu HANYA bisa lewat swipe
(`Dismissible`, `_CategoryTile` di `kategori_harga_screen.dart`) — tidak
ada tombol terlihat, tidak mudah ditemukan pengguna yg tidak tahu gestur
itu. Fix: `IconButton` hapus eksplisit ditambah di trailing baris (jadi
`Row` bersama tombol "Ubah nama" yg sudah ada), dialog konfirmasi
di-extract jadi `_confirmDelete`/`_confirmAndDelete` (dipakai bersama
oleh tombol baru & swipe lama — SATU sumber logic, bukan duplikat).
Swipe TETAP jalan sbg jalan pintas tambahan, tidak dihapus.

Test baru `test/kategori_harga_delete_button_test.dart` (3 test: tombol
tampil, tap→dialog→konfirmasi→tertombstone di DB, tap→Batal→tetap ada).
Revert-verify manual OK (3 test gagal sensible saat di-revert, hijau
lagi setelah dipulihkan). `flutter analyze` bersih. Full-suite
background agent dispatch dalam proses saat hand-off ini ditulis — CEK
hasilnya sebelum menganggap sesi ini benar-benar tuntas kalau
melanjutkan dari sini.

Sesi sebelumnya (67) — Item 72: redesain 3 dropdown pilih satuan (Cek
Stok/Hitung Fisik Opname/Jenis Satuan edit produk) — widget baru
`lib/core/widgets/unit_dropdown.dart` (`UnitDropdown<T>`), pola sama
`ProductPickerDropdown`, `PopupMenuButton` dgn `constraints` (maxHeight
320) supaya menu daftar `unit_types` panjang (15-25 entri) tidak lagi
menutupi seluruh layar. Commit `f71c97b`. **Susulan ditemukan SETELAH
hand-off sesi 67 ditulis**: full-suite background agent (dispatch utk
Item 72) melaporkan 1 kegagalan nyata (BUKAN dari Item 72) —
`test/asisten_permissions_screen_test.dart` punya `find.byType(
SwitchListTile)` tak ter-scope yg jadi ambigu (3 match) setelah Item 71
(sesi 66) menambah 2 toggle baru ke layar Izin Asisten. Di-fix dgn
scope finder ke baris spesifik "Izinkan Stok Minus" (murni perbaikan
test, TIDAK ada perubahan kode aplikasi) — commit `7815db5`. Full-suite
KEDUA (dispatch ulang khusus utk verifikasi fix ini) mengonfirmasi
**1691 test semua hijau**, 0 gagal.

Sesi sebelumnya (66) — Item 70 (rata-rata penjualan produk
harian/mingguan/bulanan di `ProductStatsScreen`) + Item 71 (screening
keamanan: guard "Backup & Restore"/"Import-Export CSV" dgn toggle izin
baru Kasir+Asisten, `akses_backup`/`akses_csv_produk` dst — "Alihkan
Owner" TETAP owner-only murni tanpa toggle). Commit `e665f23` + `3b82116`.

Sesi sebelumnya (65) — Item 69: nested dropdown varian + cascade centang
di "Kelola Kategori" (Kategori PRODUK, `CategoryAssignProductsScreen` —
beda dari Kategori Harga Item 68 di sesi 64, keduanya TETAP berlaku).
Commit `8934f07`. Root cause sama dgn Item 68 (`db.searchProducts` tidak
filter varian); tambahan: cascade centang produk induk → SEMUA
variannya (satu arah, uncentang tidak cascade). Test:
`test/category_assign_products_varian_test.dart` (5 test).

Sesi sebelumnya (64) — Item 68 (Kategori Harga, TETAP berlaku): nested
dropdown varian di layar "Tambah Produk" Kategori Harga. Commit
`cbda798`.

Bug: "Dibayar" di Ringkasan struk sudah lama (dari fix lama) menjumlahkan
`_debtSettlementTotal` (uang pelunasan hutang/DP-0 pre-order — dicatat
sbg `transaction_payments` di nota SUMBER/lama, BUKAN nota ini, via
`debtSettlementDetail` JSON blob di nota ini), tapi kartu "Riwayat
Pembayaran"/timeline pembayaran (`_buildPaymentTimeline` in-app,
`_ReceiptPaper` share/gambar, `printer_service.dart` cetak) menampilkan
`_payments`/`payments` apa adanya TANPA ikut menjumlahkan — 2 angka di
layar yang sama jadi tidak saling cocok tanpa penjelasan. User screenshot
kasus "Lunasi Pre-order" DP-0 sekaligus checkout, minta fix SIMPEL
("sesuai apa yg diketik kalkulator") bukan tambah baris baru.

Fix: baris pembayaran PALING AWAL (`identical(p, payments.where((e) =>
!e.voided).firstOrNull)`) di ketiga renderer digabung TAMPILANNYA dgn
`_debtSettlementTotal` — dipilih krn `debtSettlementDetail` HANYA
ditulis saat checkout awal (`saveTransactionWithDebtSettlements`), tidak
pernah oleh cicilan/pembayaran berikutnya, jadi baris tertua = momen
checkout yg sama persis dgn nominal kalkulator. Test baru
`test/receipt_payment_timeline_settlement_test.dart` (4 test: in-app,
share/gambar, cetak, + regresi cicilan 2x pembayaran — HANYA baris
pertama digabung, TIDAK dobel-hitung). `test/receipt_debt_settlement_
total_paid_test.dart` diupdate (assertion count 1->2 / 2->3) krn baris
timeline sekarang IKUT benar menampilkan nominal gabungan (fallout yg
diharapkan, bukan regresi). Revert-verify manual sudah dilakukan (semua
4 test baru gagal sensible saat fix di-revert via patch, hijau lagi
setelah dipulihkan). `flutter analyze` bersih. Full-suite background
agent dispatch dalam proses saat hand-off ini ditulis — CEK hasilnya
sebelum menganggap sesi ini benar-benar tuntas kalau melanjutkan dari
sini.

Yang dikerjakan: sheet "Pilih Pre-order untuk Dilunasi"
(`preorder_settlement_sheet.dart`) dapat toggle per-baris "Sekaligus
ambil/penuhi barang" (cuma tampil saat baris tercentang, default OFF).
`PreorderSettlementEntry.fulfillOnSettle` (field baru, default false,
ikut di-serialize toJson/fromJson & payload hold/resume). Saat checkout,
`saveTransactionWithDebtSettlements` (param `preorderSettlements` dpt
field `fulfillOnSettle` baru) memanggil `fulfillPreorderEntry` (qty
PENUH, BUKAN partial — keputusan desain) SETELAH `collectPreorderDeposit`
sukses, nested transaction (Drift savepoint, pola sama yg SUDAH dipakai
`collectPreorderDeposit` sendiri di fungsi yg sama — bukan mekanisme
baru). Indikator visual "Sekaligus penuhi barang" di baris keranjang
(`_PreorderSettlementEntryRow`, `cart_sheet.dart`) saat toggle aktif.
TIDAK menyentuh dashboard Laci Meja/tombol "Penuhi" struk (#18) sama
sekali — murni tambahan opsional di jalur cart settlement (#17). Test
baru di `test/preorder_settlement_checkout_test.dart` (2 test DB-level,
assert `fulfilledAt`+stok terpotong vs TIDAK tersentuh) &
`test/cart_sheet_preorder_settlement_test.dart` (1 test widget, toggle
cuma muncul saat tercentang + tersimpan ke entri) — revert-verify manual
sudah dilakukan (test "true" gagal sensible saat fix di-revert, test
"false" tetap hijau membuktikan tidak ada regresi).

**Semua 19 task di task manager sekarang `completed`** — tidak ada
pekerjaan menggantung dari sesi-sesi sebelumnya per hand-off ini.

Sesi sebelumnya (61) — ganti label "Pelunasi Pre-order" jadi "Melunasi
Pre-order" di UI (Item lihat di bawah), commit `bf936c2`.

Sesi 60 — fix nominal Bayar/kalkulator/QR (Item 65, lihat di bawah).

Bug nyata ditemukan dari screenshot user: tombol "Bayar Rp 378.150"
& "Uang Pas" di kalkulator cuma menampilkan `_total` (belanja saja),
padahal ada entri "Turut Lunasi Hutang" Rp 553.900 aktif di keranjang
yg sama — "Total Diterima (Belanja + Hutang)" yg BENAR (Rp 932.050)
cuma tampil di ringkasan, tombol Bayar & kalkulatornya sendiri lupa
ikut pakai `_grandTotal`. Audit lanjutan menemukan ini BUKAN cuma bug
tampilan: pelunasan hutang/pre-order (`saveTransactionWithDebtSettlements`
param `debtSettlements`/`preorderSettlements`) dijalankan TANPA SYARAT,
nominalnya beku & tidak pernah dicek ulang terhadap uang yg sungguhan
diterima kasir — kasir bisa checkout dgn `_tendered` cuma cukup utk
`_total` sendiri, sementara hutang pelanggan LAIN tetap tercatat lunas
penuh tanpa uangnya benar-benar berpindah tangan.

Fix (commit `f7cac8b`): `_bayarLabel()`/`_QrisDisplay.total`/
`_CashKeypadSheet.total` semua diganti ke `_grandTotal`. Gerbang baru:
kalau `_settlementTotal > 0` (Lunasi Hutang + Pelunasi Pre-order aktif)
DAN uang yg diketik kasir < `_grandTotal` -> checkout DITOLAK dgn
SnackBar peringatan (bukan lolos diam-diam), baru diizinkan kalau sudah
cukup — nilainya lalu dipetakan balik `_tendered = result -
_settlementTotal` supaya `transactions.total`/`paid` nota BARU tetap
murni porsi belanja sendiri (tidak berubah dari sebelumnya). Tombol
pintas "Selesaikan Transaksi" (Pra-Bayar) juga digerbang sama
(`_prabayarCoversTotal` sekarang WAJIB `_settlementTotal == 0` juga) —
Pra-Bayar cuma menutup belanja, bukan pelunasan hutang/pre-order. Test
baru `test/payment_screen_settlement_grandtotal_test.dart` (4 test),
revert-verify manual sudah dilakukan (2 dari 4 test gagal sensible saat
fix inti di-revert, 2 lainnya menguji jalur lain yg tidak fully exercise
baris yg direvert dlm kombinasi itu — sudah dicek satu-satu).

Task #19 (opsional "sekaligus penuhi" saat pelunasan DP-0, desain sudah
dikonfirmasi user) masih `pending` — belum dieksekusi, menunggu giliran.

_Ringkasan sesi sebelumnya (59, fix "Batalkan & Susun Ulang" Item 64;
58, fix sync Item 63) di bawah ini, dipertahankan sbg histori teknis:_

Bug yang diperbaiki: `transaction_items` (qty/priceAtSale/subtotal)
diperlakukan append-only murni oleh `dumpSince`/`mergeRows` — koreksi
SETELAH insert awal (retur, edit item, void/kumpul DP pre-order) tidak
pernah tersinkron ke device lain (kelas bug SAMA dgn Item 62/
`transactions`, tapi di level baris item). Terbongkar nyata lewat 2
fitur sesi 55/57 (tombol "Penuhi" di struk & "Pelunasi Pre-order" via
keranjang) yang sama² lewat `collectPreorderDeposit` (fungsi lama,
LOGIKANYA TIDAK diubah sesi ini) — device lain yang sudah pernah sync
nota itu berakhir `paid > total` (kembalian/lebih-bayar hantu) & harga
item basi permanen di laporannya sendiri. Fix: kolom `updated_at` baru
(migrasi v44) + stamp di 5 fungsi mutasi + `dumpSince` tambah `OR
updated_at >= ?` + `mergeRows` special-case last-write-wins persis pola
`transactions` (Item 62) — lihat komentar "Item 63" di `app_database.dart`.

Ini rebase TERBARU di atas sesi kelima puluh tujuh (Pelunasi Pre-order
via keranjang, task #17) — sudah digabung bersih, tidak ada konflik.

## Sesi keenam puluh — fix nominal Bayar/kalkulator/QR (Item 65)

Root cause dilaporkan user via screenshot — lihat ringkasan lengkap di
paragraf pembuka file ini. Commit `f7cac8b`.

## Sesi kelima puluh sembilan — fix "Batalkan & Susun Ulang" (Item 64)

Root cause KEDUA (independen dari race #13) utk laporan lama "pesanan
tertahan hilang" — lihat ringkasan lengkap di paragraf pembuka file ini.
Dieksekusi langsung tanpa dicatat ke task manager (instruksi user).
Commit `5887b5c`. Task #19 (fulfill opsional saat pelunasan DP-0) masih
menunggu di antrian, belum dieksekusi.

## Sesi kelima puluh delapan — fix sync transaction_items pasca-insert (Item 63, task #20)

**Root cause** (dikonfirmasi baca kode langsung, bukan cuma laporan):
1. `dumpSince` case `transaction_items` cuma filter
   `transaction_id IN (SELECT id FROM transactions WHERE created_at >=
   ?) OR added_at >= ?` — TIDAK ada cek per-baris utk koreksi
   post-insert. Nota LAMA yang salah satu itemnya dikoreksi belakangan
   (parent `created_at` sudah lewat watermark, `added_at` baris itu
   sendiri null krn bukan item "tambah belanjaan") tidak pernah lolos
   filter.
2. `mergeRows` memperlakukan `transaction_items` sbg `isAppendOnly` →
   `INSERT OR IGNORE` — begitu PK sudah ada di sisi penerima, baris
   di-skip TOTAL, walaupun baris itu BERHASIL ikut dump.

5 titik mutasi (semua `app_database.dart`, semua UPDATE baris
`transaction_items` yang SUDAH ada): retur (nota belum lunas), edit
item (nota belum lunas), `editPaidTransactionItem`, `voidPayment`
(reversal DP pre-order), `collectPreorderDeposit`. **Logika bisnis
kelima fungsi ini TIDAK diubah sama sekali** — murni tambah
`updatedAt: Value(now)` (semua sudah py `now` di scope, 2 titik
`voidPayment`/`collectPreorderDeposit` perlu declare `now` sedikit
lebih awal drpd sebelumnya supaya bisa dipakai di companion yang sama).

**Fix sync** (mirror PERSIS pola "Item 62" yang sudah ada utk
`transactions` — lihat komentarnya di `app_database.dart`):
- `dumpSince`: tambah `OR updated_at >= ?` (varCount 3).
- `mergeRows`: di dalam cabang `isAppendOnly` "PK sudah ada", tambah
  special case `tableName == 'transaction_items'` — last-write-wins by
  `updated_at`, `customUpdate` HANYA menimpa
  `qty`/`price_at_sale`/`subtotal`/`item_note` (+`updated_at`), kolom
  lain (`added_at`, `returned_at`, `product_id`, `product_unit_id`,
  `transaction_id`, `original_price`, `cost_at_sale`,
  `price_overridden`) TIDAK disentuh. `updates: {transactionItems}`
  disertakan (gotcha raw-SQL StreamProvider di CLAUDE.md).

**Test baru**:
- `test/migration_v44_test.dart` — fixture v43 raw sqlite3 (tabel
  minimal `transaction_items` tanpa `updated_at`), buka via
  `AppDatabase` utk memicu `onUpgrade` SUNGGUHAN sampai v44, assert
  kolom fisik ada & NULL utk baris lama.
- `test/transaction_items_updated_at_sync_test.dart` — end-to-end host→
  klien: seed nota pre-order (pola `preorder_deposit_payment_test.dart`,
  `createdAt` SENGAJA dibackdate 3 hari spy join parent `created_at`
  tidak kebetulan ikut lolos), sync pertama (klien dapat copy Rp0),
  `collectPreorderDeposit` di HOST, sync kedua dari watermark antara
  keduanya → assert baris ikut dump (bukti fix dumpSince) → assert
  `mergeRows` benar² menerapkan koreksi ke klien (bukti fix mergeRows)
  → jalankan `reconcileTransactionsByIds` sungguhan di klien → assert
  `paid <= total` (bukti ghost-overpay dicegah). **Revert-verified 2x
  TERPISAH** (dumpSince sendiri via `false && ...`/reset varCount, lalu
  mergeRows sendiri via `false && ...`) — masing² gagal dgn pesan yang
  tepat menunjuk defect yang benar, restore, hijau lagi.
- 22 test migrasi lama (`migration_v7_test.dart` s/d
  `migration_v43_test.dart`) diupdate 1 baris tiap file: assersi
  `PRAGMA user_version` akhir dari `43` → `44` (masing² meng-assert
  schemaVersion TERKINI global, bukan versi migrasi spesifiknya —
  konvensi lama di file-file ini, komentar "schemaVersion terkini").
  Ini BUKAN perubahan perilaku, murni mengikuti kenaikan schemaVersion.

`flutter analyze` 0 issue. Full suite: **1650 test lulus** (naik dari
1629 baseline sebelum sesi ini — +2 file baru `migration_v44_test.dart`
& `transaction_items_updated_at_sync_test.dart`, minus... tidak ada test
dihapus, cuma 22 diupdate assersinya). Full-run pertama sempat
menunjukkan 1 gagal (`proposal_unchanged_end_to_end_test.dart`) — lulus
bersih 2/2 saat diisolasi, flake resource-contention environment yang
sudah berulang kali didokumentasikan sesi-sesi sebelumnya, TIDAK terkait
perubahan sesi ini. Full-run kedua (setelah fix 22 file migrasi): 0
gagal sama sekali (flake tidak muncul lagi di run itu). Commits:
`f2633b4` (schema+stamping), `2b6132b` (sync fix dumpSince/mergeRows).

## Sesi kelima puluh tujuh — fitur "Pelunasi Pre-order" via keranjang (task #17)

Permintaan user (persis): pelanggan dengan pre-order terbuka yang
DP/jaminannya masih terhutang (harga dikunci Rp 0 saat checkout
awal) mungkin JUGA belanja barang lain hari ini, dan tidak mau bayar
terpisah. Dibutuhkan fitur keranjang, ARSITEKTURNYA IDENTIK dgn
"Lunasi Hutang" yang sudah ada, yang menambahkan baris pelunasan utk
nominal pre-order yang terhutang ke keranjang hari ini — TANPA
menduplikasi produk pre-order itu sbg baris item keranjang. Uangnya
dikreditkan ke nota ASLI pre-order itu (via `collectPreorderDeposit`
yang SUDAH ADA sebelumnya, tidak diubah logikanya), bukan ditambahkan
sbg omzet nota baru — persis pola `settleMergedDebt` utk hutang.

**Desain kunci (SENGAJA, jangan diubah tanpa alasan baru)**:
- **TANPA migrasi DB.** Kolom `transactions.debtSettlementDetail`
  (nullable TEXT/JSON, sudah ada) di-reuse utk KEDUA jenis baris
  (hutang & pre-order), dibedakan field diskriminator baru `"type"`
  (`'debt'` — default kalau field ini absen di JSON lama, kompatibel
  mundur — atau `'preorder'`), plus `"preorderEntryId"` utk baris
  pre-order. `DebtSettlementDetailLine` dapat 2 field baru (`type`
  default `'debt'`, `preorderEntryId` nullable); `shortLabel`
  bercabang: "Lunasi Nota #N" (hutang, tidak berubah) vs "Lunasi
  Pre-order #N" (baru). Semua kode render (in-app `receipt_screen.
  dart`, share, cetak `printer_service.dart`) TIDAK PERLU diubah SAMA
  SEKALI — sudah generik (label+amount+link), diverifikasi bukan
  cuma diasumsikan.
- **`saveTransactionWithDebtSettlements`** (`app_database.dart`) dapat
  parameter opsional baru `preorderSettlements` (default `[]`) — di
  dalam `transaction()` yang SAMA (tidak nested), loop tiap entri
  panggil `collectPreorderDeposit` (fungsi lama, TIDAK diubah
  logikanya) memakai nominal BEKU dari cart entry sbg `amount`; kalau
  return `null` (DP sudah terkumpul jalur lain di antaranya — race
  jarang) entri di-SKIP diam-diam dari `detail`, bukan melempar.
  Fungsi & parameter LAMA (`debtSettlements` dkk.) TIDAK berubah
  perilakunya — dibuktikan test regresi eksplisit.
- **Provider baru** `cart_preorder_settlement_provider.dart` —
  `CartPreorderSettlementNotifier`/`PreorderSettlementEntry`, 1:1
  MIRROR `CartDebtSettlementNotifier`/`DebtSettlementEntry`
  (SharedPreferences key `cartpreordersettle_v1_<cartId>`, family per
  `cartId`, `cleanupOrphanPreorderSettlements()`).
- **Query kandidat** `getPreorderSettlementCandidates(customerId)`
  (`app_database.dart`) — JOIN tunggal (preorder_entries+
  transaction_items+transactions+product_units+products+unit_types),
  BUKAN N+1 lewat `getPreorderDepositOwed` per-entri. Gerbang chip
  cart (murah, "ada apa tidak") pakai agregat SQL terpisah
  `getCustomerOutstandingPreorderDeposit`.
- **UI**: `preorder_settlement_sheet.dart` (mirror
  `debt_settlement_sheet.dart` — checklist "Pilih Pre-order untuk
  Dilunasi"), chip pengingat baru (warna tertiary, ikon
  `inventory_2_outlined`) + `_PreorderSettlementEntryRow` di
  `cart_sheet.dart` (menyatu di list item yang sama, SETELAH baris
  hutang), kartu ringkasan "Turut Pelunasi Pre-order" di
  `payment_screen.dart` (baris "Total Diterima" gabungan HANYA
  dirender sekali, di kartu TERAKHIR yang tampil, supaya tidak dobel
  saat hutang+pre-order sama-sama aktif).
- Hold/resume pesanan ditahan (`kasir_screen.dart`, 3 titik: hold
  manual, resume, auto-hold saat pindah antrian) & "Kosongkan
  Keranjang" ikut menyertakan/membersihkan
  `cartPreorderSettlementProvider`, mirror persis siklus
  `cartDebtSettlementProvider`.
- **Bug lama yang IKUT dibenerin** (ditemukan saat wiring
  `cleanupOrphanPreorderSettlements`): `CartDebtSettlementNotifier.
  cleanupOrphanDebtSettlements()` TERNYATA tidak pernah dipanggil dari
  mana pun sejak awal (fungsinya ada, cuma tidak terpasang di
  `main.dart`) — dipasang sekarang bareng versi pre-order-nya.

**Test baru** (semua revert-verified — fix di-stash sementara, test
gagal sensibel, restore, hijau lagi):
- `test/preorder_settlement_checkout_test.dart` (Tier 1, 6 test): DP
  terkumpul ke nota SUMBER tanpa menginflasi nota baru, entri
  owed-null di-skip diam-diam, jalur `debtSettlements`-saja TIDAK
  regresi, gabungan hutang+pre-order dalam satu `detail`, parse JSON
  lama (tanpa `type`) & JSON baru (`type:'preorder'`).
- `test/cart_sheet_preorder_settlement_test.dart` (Tier 2, 4 test):
  gerbang izin sama persis hutang, tap chip -> sheet -> Terapkan ->
  entri masuk + Total naik, tap baris -> entri hilang + Total turun.

`flutter analyze` 0 issue. Full suite: **1649 test lulus, 0 gagal**
(+10 test baru bersih — 6 di `preorder_settlement_checkout_test.dart`,
4 di `cart_sheet_preorder_settlement_test.dart` — tanpa flake
`backup_schema_version_guard_test.dart` di run ini). Commits: lihat
CHANGELOG.md (dipecah backend/UI/payment_screen/docs, urutan
kronologis).

## Sesi kelima puluh enam — select-all teks cari lama saat tap +/- produk

Permintaan user: setelah tap stepper "+"/"-" di kartu grid, tile
daftar, atau baris varian dropdown kasir, KALAU field cari sedang
expanded (fokus) & masih berisi teks sisa pencarian sebelumnya, teksnya
otomatis ter-select-all — supaya kasir bisa langsung ketik ulang produk
berikutnya tanpa hapus manual. Kalau field cari collapsed/tidak fokus,
tap stepper TIDAK boleh menyentuhnya sama sekali (tidak expand, tidak
highlight, tidak memicu keyboard).

**Implementasi** (`kasir_screen.dart`): fungsi baru `_highlightSearchIfActive`
di `_KasirScreenState` — logika select-all sama persis dgn yang sudah
ada di `_KasirTopbarState._onFocusChange` (dipakai saat field BARU
dapat fokus), TAPI tanpa `addPostFrameCallback` karena di kasus ini
field SUDAH fokus (bukan baru dapat fokus), jadi tidak perlu menunggu
cursor default Flutter dulu. Parameter baru `VoidCallback?
onAfterQtyChange` ditambahkan ke 3 widget (pola sama persis dgn
`onBeforeTap` yang sudah ada di 2 di antaranya): `_ProductCard` (kartu
grid), `_ProductListTile` (tile daftar), `_VariantDropdown` (baris
varian — sebelumnya TIDAK punya hook apa pun ke `_KasirScreenState`,
constructor cuma `parent`/`parentDetail`/`cartId`). Dipanggil di akhir
closure `onTap` (setelah `onQuickAdd`/`onOpenEntry`/`_incrementVariant`)
DAN `onMinus` (hanya saat benar-benar terpasang, `qty > 0`) di masing-
masing widget — `AddControl`, `_decrementProduct`, `_incrementVariant`,
`_decrementVariant` (fungsi top-level) TIDAK diubah sama sekali.
`_KasirScreenState` menyambungkan `_highlightSearchIfActive` sbg
`onAfterQtyChange` di 3 titik konstruksi: `_ProductCard(...)` &
`_ProductListTile(...)` (keduanya di `itemBuilder` grid/list), dan
`_ProductListTile` meneruskannya lagi ke `_VariantDropdown(...)` yang
dikonstruksinya sendiri (dropdown varian inline anak dari tile, bukan
langsung dari `_KasirScreenState`).

**Test baru** (`test/kasir_stepper_search_highlight_test.dart`, 10
test, 3 grup — kartu grid/tile daftar/baris varian): tiap grup
menguji field fokus+ada teks (select-all penuh), field fokus+kosong
(tidak error, tidak ada select), field collapsed/tidak fokus+ada teks
(stepper TIDAK menyentuh field sama sekali — focus/selection/teks
semua tetap seperti semula); grup kartu grid ditambah 1 test tombol
"-" (bukan cuma "+") utk membuktikan jalur onMinus juga tersambung.
Catatan teknis test: teks pencarian yang diketik dalam skenario ini
SENGAJA dipilih agar tetap cocok dgn nama produk yang sedang diuji
(mis. "minyak"/"pop ice") — field cari kasir benar-benar memfilter
`StreamProvider` produk, jadi teks yang tidak cocok bikin kartu/tile
lenyap dari tree sebelum stepper sempat di-tap; longPress expand baris
varian juga WAJIB dilakukan SETELAH mengetik query (bukan sebelum) krn
mengetik memicu rebuild list yang mereset state `_expanded` lokal
tile. Revert-verified: fix (kasir_screen.dart) di-stash sementara, 4
test assersi select-all gagal sensibel (`Expected: <0> Actual: <N>` —
posisi selection tidak berubah dari sebelum tap), 6 test lain (KOSONG +
collapsed) tetap hijau krn memang cuma menegaskan TIDAK ada efek;
restore, hijau lagi.

`flutter analyze` 0 issue. Full suite: **1633 test lulus, 0 gagal**
(rebase bersih di atas commit sesi 55 `a9955c5`, tidak ada flake
`backup_schema_version_guard_test.dart` di run ini). Commit: `3c1ddce`
(sebelum rebase; hash final lihat `git log` setelah push).

## Sesi kelima puluh lima — tombol Penuhi pre-order langsung di kartu nota

Permintaan user (persis): "malas buka laci meja misal, jadi langsung
tap keterangan yang ada di cart bar, lalu penuhi di card in app
struknya" — kartu Pre-order di `receipt_screen.dart` sebelumnya cuma
status read-only, kasir harus buka Laci Meja dashboard dulu utk
memenuhi pesanan.

**Implementasi**: `_laciMejaEntryBlock` (dipakai 3 kartu: Pinjaman,
Titip/Ketinggalan, Pre-order) dapat parameter baru `Widget? fulfillButton`
— dirender di Row headline yang sama dgn ikon edit pensil (`[headline
Expanded, ikon edit?, SizedBox(4), fulfillButton?]`), default `null` jadi
2 caller lain (Pinjaman/Titip) TIDAK berubah sama sekali. Hanya
`_buildPreorderCard()` yang mengisinya, digerbangi PERSIS kondisi status
yang sudah ada (`p.cancelledAt == null && p.fulfilledAt == null` — sama
dgn cabang "Sisa X belum dipenuhi", bukan "Dibatalkan"/"Selesai").

Logic tombol (`_fulfillPreorderFromReceipt`) meniru PERSIS alur
"Penuhi" di `laci_meja_dashboard_screen.dart`: dialog qty (`_showQtyDialog`,
duplikat privat kecil — fungsi asalnya `static`/private di file lain,
tidak diekspor, tidak layak diekstrak jadi shared widget utk dialog
sesederhana ini) kalau sisa > 1 (boleh dipenuhi bertahap), langsung
`fulfillPreorderEntry` kalau sisa <= 1, lalu tawarkan
`showDebtPaymentSheet` kalau `getPreorderDepositOwed` masih > 0 (DP/
jaminan Rp0 yang dikunci saat checkout). Ditutup `await _load()` supaya
kartu langsung refresh (screen ini one-shot fetch, bukan `StreamProvider`
— tidak ada auto-refresh reaktif utk data ini).

**Test baru** (`test/receipt_preorder_fulfill_button_test.dart`, 6 test):
sisa > 1 → dialog muncul, konfirmasi parsial → `fulfillPreorderQty`
jumlah benar & kartu refresh; sisa <= 1 → langsung `fulfillPreorderEntry`
tanpa dialog; entri berDP tertunda → sheet DP/jaminan ditawarkan setelah
dipenuhi; entri Dibatalkan/Selesai → tombol tidak muncul sama sekali;
kartu Pinjaman/Titip (2 caller lain) TIDAK terpengaruh. Revert-verified
(fix di-stash sementara, 3 test yg butuh tombol gagal sensibel dgn
"could not find Penuhi", 3 test gating tetap hijau krn memang cuma
menegaskan ketiadaan tombol; restore, hijau lagi).

`flutter analyze` 0 issue. Full suite: **1627 test lulus, 2 gagal**
(`proposal_unchanged_end_to_end_test.dart`, TIDAK terkait file yang
disentuh sesi ini — lulus bersih 2/2 saat diisolasi, flake
resource-contention environment krn sesi lain jalan paralel di branch
yang sama, pola sudah berulang kali didokumentasikan sesi-sesi
sebelumnya). Commits: `9fe57f1` (plumbing parameter), `3242222` (logic
tombol + test).

## Sesi kelima puluh empat — cegah tap dobel tombol cetak struk

**Bug ditemukan lewat audit kode langsung** (bukan laporan user, medium
priority): `_printReceipt` (`receipt_screen.dart`) & `_print`
(`merged_receipt_screen.dart`) tidak punya guard `_isPrinting` — tombol
`Icons.print_outlined` cuma di-disable saat `_tx == null`, tetap
tertekan penuh selama rangkaian async (getSavedMac -> ensurePermissions
-> PrinterService.printReceipt/printMergedReceipt -> connect -> write)
berjalan. Diverifikasi native Android (`MainActivity.kt`, `doWrite`,
~baris 172): tiap panggilan MethodChannel `write` SPAWN THREAD BARU,
TANPA sinkronisasi apa pun terhadap `OutputStream` socket Bluetooth yang
SAMA — 2 tap cepat bisa membuat 2 write nyata bersamaan meng-interleave/
merusak byte stream ESC/POS (struk dobel/garbled, bukan cuma "tercetak
2x" yang jinak).

**Fix (2 bagian, keduanya dikerjakan)**:
1. **Dart** (`receipt_screen.dart` & `merged_receipt_screen.dart`) —
   flag `bool _isPrinting`, seluruh body `_printReceipt`/`_print`
   dibungkus `try/finally` SEJAK AWAL fungsi (bukan cuma setelah
   early-return izin/konfigurasi) supaya guard SELALU terlepas lewat
   jalur keluar manapun (early-return "printer belum dikonfigurasi",
   "izin ditolak", exception tak terduga di tengah, maupun sukses
   normal). `if (_isPrinting) return;` di awal, sebelum `setState`.
   Tombol print `onPressed` digabung kondisi `(_tx == null ||
   _isPrinting) ? null : ...`.
2. **Android native** (`MainActivity.kt`) — defense-in-depth murni
   tambahan: `private val writeLock = Any()`, operasi
   `s.outputStream.write/flush` di `doWrite` dibungkus
   `synchronized(writeLock) { ... }` — serialisasi di level thread
   native kalau 2 panggilan `write` SEMPAT lolos bersamaan dari sisi
   Dart lewat jalur manapun. **TIDAK bisa diuji di device/emulator
   Android sungguhan di lingkungan sesi ini** (tidak ada toolchain
   Android/Gradle) — perubahan sengaja sekecil & sekonservatif mungkin
   (murni tambah mutual exclusion, tidak mengubah logika lain).

**Test baru**: `test/receipt_print_button_guard_test.dart` — mock
channel `com.thepos/bt_print` (channel custom app ini) + channel
`permission_handler`, tap tombol cetak 2x SANGAT CEPAT (tanpa `pump` di
antaranya), assert channel `write` cuma terpanggil TEPAT 1x. Catatan
teknis penting yg ditemukan selama membangun test ini: `tester.
pump(duration)` di `testWidgets` TIDAK bisa memajukan `Future.delayed`
nyata di dalam `PrinterService.connect()` (jeda stabilisasi koneksi
600ms) — harus pakai `tester.runAsync()` diselingi `pump()` (lihat
komentar di file test). Revert-verified: fix Dart di-stash sementara,
test gagal nyata (`write` terpanggil 2x, bukti persis bug), fix
dikembalikan, hijau lagi.

`flutter analyze` 0 issue. Full suite: **1618 test lulus, 1 gagal**
(`proposal_unchanged_end_to_end_test.dart`, TIDAK terkait file yang
disentuh sesi ini — lulus bersih 3/3 saat diisolasi, flake
resource-contention environment akibat sesi lain jalan paralel di
branch yang sama, sudah didokumentasikan berulang kali di sesi-sesi
sebelumnya). Commits: `7e0286f` (Dart), `807d2b1` (native Kotlin,
untested-on-device).

## Sesi kelima puluh tiga — fix race resume/tahan pesanan ditahan (insiden produksi)

**Bug dilaporkan user** (insiden produksi nyata, uang pelanggan sudah
diterima): pesanan pra-bayar yang ditahan lenyap total — tidak ada di
daftar antrian, tidak ada di keranjang aktif.

**Akar masalah**: `kasir_screen.dart` — `_resumeHeld` (tap kartu antrian)
& `_holdCurrent` (tombol "Tahan" di `_CartMetaTab`) sama-sama baca
provider cart aktif, `await` ke DB (`holdOrder`/`deleteHeldOrder`), BARU
memutasi provider cart — TANPA kunci apa pun. Panel antrian dirender
INLINE (bukan `showModalBottomSheet`), jadi toolbar "Tahan" tetap
tertekan selagi panel terbuka → kasir yang menyentuh tap kartu antrian +
tombol "Tahan" nyaris bersamaan bisa membuat operasi kedua meng-clobber
provider yang baru saja diisi operasi pertama sebelum sempat dibaca —
satu pesanan (uangnya sudah diterima) lenyap dari held-orders TABLE
maupun cart SEKALIGUS.

**Fix**:
1. `kasir_screen.dart` — flag `bool _isSwitchingHeld` (state
   `_KasirScreenState`) dicek di AWAL `_resumeHeld` DAN `_holdCurrent`
   (re-entrant call jadi no-op diam-diam), diset `true` sebelum kerja,
   dilepas via `try/finally` (`if (mounted) setState(() =>
   _isSwitchingHeld = false)`) — WAJIB finally supaya exception di tengah
   tidak mengunci fitur tahan/resume selamanya. UI ikut mencerminkan:
   `onHold` di `_CartMetaTab` jadi `VoidCallback?` (null saat terkunci →
   tombol "Tahan" meredup & non-tap), `_HeldInlinePanel` dapat param
   `busy` (opacity 0.5 + `onTap: null` di tiap `_HeldCard` saat terkunci).
2. `cart_sheet.dart` — guard LEBIH RINGAN & TERPISAH (state beda kelas,
   `_CartSheetState._isHolding`): sheet ini modal sungguhan
   (`showModalBottomSheet`, barrier menahan panel/toolbar di belakangnya),
   jadi satu-satunya celah adalah double-tap ke tombol "Tahan Pesanan"nya
   SENDIRI — dicegah pola sama (cek awal + `try/finally`), tombol ikut
   dinonaktifkan (`onPressed: null`) selama proses.

**Test baru**: `test/kasir_held_order_race_test.dart` (2 test) + 1 test
tambahan di `test/cart_sheet_hold_button_test.dart`. Kunci teknis:
`WidgetTester.tap` TIDAK BISA dipanggil dua kali tanpa `await` di
antaranya (guard `TestAsyncUtils` framework test menolak pemanggilan
bertumpuk) — race disimulasikan dgn memanggil `onTap`/`onPressed`
(`VoidCallback` yang sama dipasang widget sungguhan) LANGSUNG dua kali
berturut-turut TANPA pump di antaranya, deterministik krn murni kontrol
sinkron Dart (baris kedua jalan sebelum baris pertama lewat `await`
pertamanya). Revert-verified (guard dinonaktifkan sementara via `false
&& flag`): test race kasir_screen gagal dgn productId salah satu
pesanan LENYAP TOTAL dari kedua tempat (bukti persis bug asli, bukan
cuma "assert gagal"); test double-tap cart_sheet gagal dgn 2 held order
(bukti duplikat) — 8 test lain di file yang sama tetap hijau (regression
guard, tidak terpengaruh). Guard dikembalikan → hijau lagi.

`flutter analyze` 0 issue. Full suite (setelah rebase di atas
`433e2b4`/sesi 52): **1620 test lulus, 0 gagal** (naik dari 1617 baseline
sebelum sesi 51 — +3 test baru bersih: 2 di file race baru, 1 tambahan
di `cart_sheet_hold_button_test.dart`). Commits: `f45ba47` (kasir_screen.
dart), `8437c25` (cart_sheet.dart).

## Sesi kelima puluh dua — fix harga bertingkat baris dobel transfer handoff

**Bug** (ditemukan audit eksternal, bukan laporan user): `parse()`
(`order_parser_service.dart`, cabang merge unitId dobel ~baris 194-224)
menghitung ulang harga tingkat utk qty gabungan lewat `reResolved.price`
(BENAR), tapi lalu buang hasilnya via `price ?? reResolved.price` —
`price` (dari flag `p=`, HANYA ada di transfer handoff QR antar-device
toko sendiri via `encodeHandoff`, SELALU ada di jalur itu) selalu menang,
membekukan harga tingkat LAMA (qty tunggal) ke qty BARU gabungan. Salah
utk toko berharga bertingkat (harga berubah di ambang qty) — TIDAK
mempengaruhi jalur katalog HTML pelanggan (flag kosong di situ,
`price ?? reResolved.price` sudah otomatis jatuh ke `reResolved.price`).

**Fix**: `priceOverridden` (flag `v=1`, sudah ada, artinya "harga sender
adalah override MANUAL, bukan hasil resolve tingkat normal") dipakai
sbg gerbang: `false` → WAJIB `reResolved.price` fresh (harga sender basi
utk qty baru); `true` → tetap percaya `price` sender (override manual
sengaja, berlaku brp pun qty gabungannya). `originalPrice` diberi
percabangan sama (semula ikut fallback chain `price` yg sama, sekarang
konsisten dgn expresi `price`-nya).

Ekspresi final (persis, merge branch SAJA — cabang non-merge ~baris 225
ke bawah TIDAK disentuh):
```dart
price: priceOverridden ? (price ?? reResolved.price) : reResolved.price,
originalPrice: priceOverridden
    ? (originalPrice ?? price ?? reResolved.price)
    : reResolved.price,
```

**Test baru** (`test/order_parser_service_test.dart`): 2 test — (1) tier
qty 1-4 @ Rp13000, qty 5+ @ Rp11000, kirim qty 3 `priceOverridden=false`
lalu tempel dobel (gabung ke qty 6, lintas ambang) → `price` HARUS 11000,
BUKAN 13000 lama; (2) companion `priceOverridden=true` (override manual
Rp12500) dgn skenario sama → `price` TETAP 12500, TIDAK dihitung ulang.
Revert-verified: fix di-revert sementara, test (1) gagal `Expected:
<11000> Actual: <13000>` (persis prediksi bug), fix dikembalikan, hijau
lagi. Test lama ~baris 777-813 (flat pricing, cuma assert
`priceTrustedFromSender`/`currentResolvedPrice`, bukan `.price`) TETAP
LULUS tanpa perubahan assersi (memang tidak menyentuh nilai `.price`).
`flutter analyze` 0 issue. Full suite: **1619 test lulus, 0 gagal**
(naik dari sebelumnya — +2 test baru bersih). Commit: `433e2b4`.

## Sesi kelima puluh satu — riwayat Laci Meja diurut terbaru dulu (menurun)

Permintaan user (persis): "Untuk riwayat laci meja, mungkin sort dari
yang terbaru dulu, menurun ke yang terlama".

**Penting — 2 mode berbeda di fungsi yang SAMA, jangan tertukar**:
`watchLeftBehindItems`/`watchBorrowedItems`/`watchPreorderEntries`
(`app_database.dart`) masing-masing punya mode DEFAULT (dashboard
`LaciMejaDashboardScreen`, "masih terbuka", `includeX: false`) dan mode
RIWAYAT (`RiwayatLaciMejaScreen`, arsip semua entri,
`includeCollected`/`includeFullyReturned`/`includeClosed: true`). Mode
default WAJIB tetap FIFO asc `createdAt` — ini ATURAN BISNIS (Item 52:
urutan pemenuhan pre-order, `paid` tidak boleh ikut menentukan urutan;
komentar kode eksplisit "TIDAK PERNAH, jangan diubah") — SALAH kalau
diubah, karena FIFO di situ menentukan SIAPA YANG DILAYANI DULU, bukan
cuma tampilan. Cuma mode RIWAYAT yang diubah ke desc `createdAt` — mode
default tidak disentuh sama sekali. `watchPreorderEntries` sebelumnya
berbagi SATU `orderBy` antara kedua mode (`includeClosed` cuma mengubah
filter `WHERE`, bukan urutan) — ditambah percabangan
`includeClosed ? desc : asc` di `orderBy` itu sendiri supaya riwayat
bisa desc tanpa menyentuh FIFO mode default. `watchBorrowedItems` mode
riwayat tetap mempertahankan `desc(pinned)` sbg sort primer (kartu
disematkan tetap di atas), cuma sort SEKUNDER `createdAt` yang dibalik
ke desc.

**Test baru**: 1 test per kategori (Titip/Ketinggalan, Pinjaman,
Pre-order) di `test/laci_meja_db_test.dart`, tiap test memanggil query
mode riwayat & assert urutan id `['*-baru', '*-lama']`. Revert-verified
(stash fix, ketiga test baru gagal dgn urutan kebalik, restore, hijau
lagi). `flutter analyze` 0 issue. Full suite: **1617 test lulus, 0
gagal** (naik dari 1614 — +3 test baru bersih, tanpa flake terlihat di
run ini). Commit: `8e7d1c7`.

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
