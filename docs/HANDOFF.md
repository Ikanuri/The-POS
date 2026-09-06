# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

> Catatan: file ini sebelumnya bertumbuh jadi >6000 baris log kronologis
> (bertentangan dengan tujuannya sbg snapshot ringkas hemat token). Ditulis
> ulang dari nol (dua sesi paralel sama-sama melakukan ini, digabung di
> commit merge) — histori detail sebelum tanggal di bawah ada di
> `git log`/CHANGELOG.md, BUKAN hilang, hanya sudah tidak diduplikasi di sini.

_Update sesi 6 September 2026 (sesi ketiga puluh — TIGA sesi paralel:
fix sync LAN supplier/pembelian, "Lunasi Hutang" dari keranjang aktif,
& "Batalkan & Susun Ulang"). Versi kerja **2.48.0+102** (MINOR naik,
PATCH reset — "Lunasi Hutang" terlihat pengguna; fix sync
supplier/pembelian murni PATCH-shaped tapi modulnya sendiri masih
schema-only/belum dipakai fitur apa pun, jadi tidak menaikkan level
bump; ketiga sesi kebetulan sama-sama bump BUILD berbeda sebelum
digabung, BUILD dinaikkan sekali lagi jadi `+102` di commit merge).
schemaVersion **40 -> 41** — gabungan 2 perubahan independen: kolom
`transactions.debt_settlement_detail` (TEXT nullable, dari "Lunasi
Hutang") + kolom `updated_at` baru (nullable) di `suppliers`/
`purchases` & `created_at` baru di `purchase_items` (dari fix sync
supplier/pembelian, tabel ini sebelumnya TIDAK PUNYA timestamp sama
sekali). "Batalkan & Susun Ulang" TIDAK menyentuh skema DB sama sekali._

## Sesi ini — suppliers/purchases/purchase_items ikut sync LAN harian SELESAI (`4eaa885`)

User melaporkan tabel-tabel ini cuma ikut backup penuh/"Alihkan Owner",
tidak pernah ikut `dumpSince` harian; device kasir lain di toko yang
sama tidak pernah melihat data supplier/pembelian yang diinput owner
di device lain.

Temuan penting: **modul Supplier & Pembelian (tabel `Suppliers`/
`Purchases`/`PurchaseItems`) saat ini SCHEMA-ONLY** — tidak ada satu pun
fungsi CRUD yang menyentuhnya di `app_database.dart`, tidak ada layar
fitur di `lib/features/`, tidak ada test yang memakainya sebelum sesi
ini. Jadi item "audit semua fungsi mutasi & restamp updated_at" di
briefing tidak menemukan fungsi apa pun untuk diaudit — TIDAK ADA bug
riil di kode APLIKASI hari ini (beda dari pola `deactivateProduct`/
`applyProductProposals` yang sudah kejadian sebelumnya), tapi
skema+`dumpSince` sekarang sudah siap dipakai benar begitu fitur
Pembelian dibangun (sesi depan yang membangunnya WAJIB restamp
`updated_at` eksplisit di tiap fungsi update `suppliers`/`purchases` —
kolom TIDAK auto-touch, sama gotcha yang sudah ada di CLAUDE.md).

Fix (`lib/core/database/tables/supplier_tables.dart`,
`lib/core/database/app_database.dart`):
- `Suppliers.updatedAt`, `Purchases.updatedAt` (keduanya baru,
  NULLABLE — bukan `withDefault(currentDateAndTime)`, krn SQLite
  menolak `ALTER TABLE ADD COLUMN` dgn default non-konstan).
  `PurchaseItems.createdAt` (baru — tabel ini sebelumnya TANPA
  timestamp sama sekali; cukup `createdAt`, TIDAK butuh `updatedAt`,
  krn baris ini immutable begitu dibuat).
- Migrasi v41: `addColumn` + backfill (`updated_at = created_at` utk 2
  tabel pertama, `created_at = now()` utk `purchase_items`) — DIJAGA
  cek `sqlite_master` dulu (fixture test migrasi lama, mis.
  `migration_v14_test.dart`, sengaja cuma bikin tabel yg relevan utk
  migrasi ITU, tabel-tabel ini bisa belum ada di fixture semacam itu —
  tanpa guard ini migrasi lama JEBOL "no such table: suppliers", sempat
  kejadian saat dikerjakan, sudah difix).
- `suppliers`, `purchases`, `purchase_items` ditambah ke `masterData` di
  `dumpSince` (urutan parent dulu). `purchase_items` delta by
  `created_at` saja (bukan full-dump — tumbuh terus seiring pembelian).
- `mergeRows` (klien) TIDAK butuh kode tambahan — generik by nama tabel,
  last-write-wins by `updated_at` otomatis berlaku begitu kolomnya ada
  (diverifikasi baca kode, bukan asumsi).
- 19 test migrasi lama diupdate (`PRAGMA user_version` hardcode 40 ->
  41 — assert ini SELALU perlu diupdate tiap bump `schemaVersion`,
  gotcha buat sesi depan yang naikkan skema lagi — jadi 2x kejadian di
  sesi paralel yang sama, lihat juga catatan sesi "Lunasi Hutang" di
  bawah).

Test baru (`test/migration_v41_test.dart`, `test/
supplier_purchase_sync_test.dart`) — revert-verify dibuktikan (stash
`app_database.dart`/`app_database.g.dart`/`supplier_tables.dart` →
compile error "getter tidak ditemukan"/"no such table", masuk akal,
baru kembalikan fix). Full suite: **1508 test, 0 gagal** (run
sebelumnya sempat 8-21 gagal semuanya di test LAN-sync REAL yg BEDA
tiap run — `lan_sync_upload_queue_test.dart`/
`asisten_permission_sync_test.dart`/
`proposal_unchanged_end_to_end_test.dart` — pre-existing flaky
kontensi-port paralel, sudah didokumentasikan sesi sebelumnya juga,
lulus normal saat dites sendiri-sendiri, TIDAK terkait perubahan sesi
ini). `flutter analyze`: 0 issue.

**Belum dikerjakan / cek sesi depan**: kalau fitur Pembelian benar²
dibangun (form beli dari supplier dll), WAJIB restamp `updated_at`
eksplisit di setiap fungsi yang meng-update `suppliers`/`purchases` —
lihat komentar di `supplier_tables.dart`.

## Sesi ini (paralel) — "Lunasi Hutang" dari keranjang aktif SELESAI (`a921860`)

Desain sudah disetujui eksplisit user di sesi sebelumnya, dieksekusi penuh
sesi ini. Kasir bisa menambahkan pelunasan hutang tempo/kurang_bayar milik
SEORANG pelanggan langsung dari keranjang aktif SEBELUM checkout — uangnya
diterima bersamaan dgn belanja baru, satu proses.

Keputusan desain kunci:
- **Entry point**: ikon "Lunasi Hutang" (`Icons.receipt_long_outlined`) di
  FOOTER `cart_sheet.dart`, sebelah tombol Pra-Bayar (BUKAN header
  ikon-row) — dipilih karena konsisten scope dgn Pra-Bayar (keduanya
  "nominal yang perlu diterima kasir SEBELUM checkout", bukan aksi
  navigasi/utility spt Tahan Pesanan/Transfer QR di header). Gerbang sama
  persis Pra-Bayar: `kMainCartId` & izin `terima_pembayaran`.
- **Alur**: pilih pelanggan berhutang (`_DebtCustomerPickerSheet`, dari
  `db.getDebtBook()`, ada search) -> checklist nota tempo/kurang_bayar
  miliknya (`_DebtInvoicePickerSheet`, dari `db.getUnpaidTxDetails`,
  default SEMUA tercentang, boleh sebagian) -> kalkulator nominal
  (`showDebtPaymentSheet` yang SUDAH ADA, di-reuse penuh — sama dipakai
  Pra-Bayar & Buku Hutang).
- **Rencana FIFO dibekukan saat entri dibuat** (`planFifoSettlement`, pure
  function di `debt_settlement_picker.dart`) — bukan dihitung ulang saat
  checkout. Alasan: supaya ringkasan yg kasir lihat di keranjang (nota
  mana dapat berapa) konsisten sampai checkout beneran. Saat checkout,
  `settleMergedDebt` (fungsi lama, TIDAK diubah) tetap yang menentukan
  alokasi FINAL sungguhan by design (bisa beda tipis dari rencana beku
  kalau sisa nota berubah di antaranya — jarang, single-device) — dan
  yang PALING PENTING, `settleMergedDebt` SUDAH cap otomatis ke sisa
  aktual per nota, jadi TIDAK PERNAH overpay hutang walau kasir input
  nominal lebih besar dari sisa (kelebihan jadi `changeGiven` di nota
  lama, bukan ditambahkan ke `paid`).
- **Uang pelunasan hutang TIDAK ikut logika keypad/status-lunas nota
  BARU** — nominalnya sudah final sejak kalkulator entri sendiri (persis
  spt entri Pra-Bayar yang sudah terkunci tidak perlu diketik ulang di
  keypad `payment_screen.dart`). `_grandTotal` (= `_total` +
  `_debtSettlementTotal`) HANYA figur tampilan ("Total Diterima Belanja +
  Hutang" di kartu info) — TIDAK dipakai utk `_paid`/`_tendered`/status
  lunas nota baru, yang tetap murni berbasis `_total` (cart) spt
  sebelumnya.
- **Field referensi struk**: `transactions.debtSettlementDetail` (TEXT
  nullable, JSON list `{invoiceId, invoiceLocalId, amount, customerName}`)
  — murni utk TAMPILAN struk (in-app/share/cetak), ditulis SEKALI oleh
  `saveTransactionWithDebtSettlements` dari rencana beku yang sama yang
  dipakai memanggil `settleMergedDebt` (bukan dihitung ulang terpisah).
  Parser bersama `parseDebtSettlementDetail`/`DebtSettlementDetailLine` di
  `app_database.dart`.
- **DB method baru** `saveTransactionWithDebtSettlements` (app_database.
  dart) membungkus `saveTransaction` (lama, tidak diubah) + loop
  `settleMergedDebt` per entri + update kolom detail, SEMUA dalam SATU
  `transaction()` (Drift savepoint nested — aman, transaction() lama di
  dalam transaction() baru).
- **Siklus hidup entri** (`CartDebtSettlementNotifier`,
  `cart_debt_settlement_provider.dart`) — pola PERSIS `CartPrabayarNotifier`:
  StateNotifierProvider.family per cartId, persist SharedPreferences
  (`cartdebtsettle_v1_<cartId>`), ikut ter-hold/resume (`kasir_screen.dart`
  `_parseHeldPayload`/`_holdCurrent`/`_resumeHeld`/`_autoHoldCurrentIfAny`
  — key payload baru `debtSettlement`), clear saat cart di-clear/checkout.

**Test** (revert-verify DIBUKTIKAN 2x — DB layer `settleMergedDebt` cap &
picker layer `planFifoSettlement` cap, masing-masing di-stash sesaat &
terbukti gagal dgn pesan overpay yang masuk akal sebelum dikembalikan):
- `test/debt_settlement_checkout_test.dart` (7 test, DB murni) — FIFO 1
  nota, partial, ANTI-OVERPAY (nominal > sisa aktual -> `paid` nota lama
  dicap ke `total`, TIDAK PERNAH lebih, kelebihan jadi `changeGiven`),
  gabungan 2 pelanggan dalam 1 checkout, parser detail (null/rusak/normal).
- `test/cart_sheet_debt_settlement_test.dart` (8 test, widget + pure-unit)
  — gerbang izin (owner lihat ikon, kasir tanpa izin/mode Katalog tidak),
  seed entri langsung -> ringkasan footer -> hapus, ALUR LENGKAP
  end-to-end (tap ikon -> pilih pelanggan -> pilih nota -> kalkulator ->
  entri tersimpan benar), `planFifoSettlement` pure (cukup 1 nota, meluber
  FIFO ke nota ke-2, ANTI-OVERPAY tiap nota dicap ke sisa masing-masing).
- **Migrasi schemaVersion 40->41 memutakhirkan 19 file test migrasi lama**
  (`migration_v7_test.dart` s/d `migration_v40_test.dart`, semua yang
  assert `expect(ver.data.values.first, 40)` hardcoded "schemaVersion
  terkini") — WAJIB dilakukan tiap migrasi baru, jangan lupa lagi.

Full suite (dijalankan setelah merge dgn sesi paralel "Batalkan & Susun
Ulang"): **1528 test, 0 gagal terkait salah satu fitur**. Kegagalan yang
sempat muncul di beberapa run penuh (`proposal_unchanged_end_to_end_
test.dart`, `lan_sync_transaction_items_repro_test.dart` — port 8625
`Address already in use`) TERBUKTI pre-existing flaky kontensi-resource
dari sesi paralel LAIN yang jalan bersamaan di environment yang sama
(banyak worktree agent lain kepakai port sama), lulus 100% saat dites
sendirian/isolated. `flutter analyze`: 0 issue.

**Belum dikerjakan / cek sesi depan**: tidak ada — briefing user tuntas
dieksekusi semua poinnya (model, entry point, UI keranjang, checkout
atomik, field referensi struk, ketiga jenis struk), tidak ada keputusan
desain yang masih menggantung utk fitur ini.

## Sesi ini (paralel) — "Batalkan & Susun Ulang" SELESAI & di-commit (`708996b`)

Fitur yg didesain & disetujui user di sesi SEBELUMNYA (baru sempat
dieksekusi sekarang): tombol "Batalkan" di Struk (`receipt_screen.dart`)
& Riwayat Transaksi (`tx_history_sheet.dart`) sekarang punya opsi kedua
"Batalkan & Susun Ulang" — void nota (reuse `voidTransaction()` apa
adanya) lalu isi ulang keranjang kasir aktif (`kMainCartId`) dari barang
nota yg baru divoid, supaya kasir bisa lanjut checkout sbg TRANSAKSI BARU
tanpa mengetik ulang (nota lama tetap permanen void, jejak audit).

**Bagian kunci** (lihat CHANGELOG untuk detail lengkap):
- `AppDatabase.cartItemsFromTransaction(txId)` (app_database.dart) — DB
  helper baru, menyusun `transaction_items` (qty positif saja, baris
  retur qty negatif dikecualikan) jadi `List<CartItem>`, urut INDUK dulu
  baru VARIAN (penting: `CartNotifier.addItem` butuh induk sudah ada di
  cart dulu supaya storedQty-nya ikut naik otomatis saat varian
  menyusul — TIDAK perlu hitung ulang manual).
- `CartMeta.replacesTxId` (cart_meta_provider.dart) — field baru,
  persisted sama pola field lain di class ini. Diisi via
  `setReplacesTxId()` saat redo-cart dibentuk, dibaca SEKALI oleh
  `payment_screen.dart` saat checkout utk menulis
  `internalNote: 'GANTI:<id nota lama>'` (pola sama `RETUR:<id>` di
  `addReturnTransaction`).
- `showVoidTransactionDialog()` (tx_history_sheet.dart) — param baru
  `allowRestockOption` (default `false`). Kedua caller di
  `receipt_screen.dart`/`tx_history_sheet.dart` (dalam alur Kasir) pakai
  `true`; caller di `transaksi_tab.dart` (tab Laporan, di luar alur
  Kasir) SENGAJA tetap default `false` — opsi ini TIDAK muncul di sana.
  Guard tambahan: nota RETUR tidak ditawari opsi ini sama sekali.
- Fungsi baru `_redoCartFromVoidedTransaction()` (tx_history_sheet.dart)
  — isi ulang cart+meta+prabayar, lalu TAWARKAN (dialog, bukan otomatis)
  bawa `tx.paid` sbg 1 entri Pra-Bayar bila nota lama status
  `lunas`/`kurang_bayar` dgn `paid>0` (nota `tempo` murni TIDAK
  ditawari). Navigasi balik ke `/kasir` pakai `context.go` + pop
  Navigator (aman dipanggil dari route go_router yg di-push MAUPUN
  modal sheet biasa — dua konteks pemanggil berbeda).
- Test baru (semua revert-verify terbukti): `void_restock_cart_items_test.dart`
  (DB murni), `void_restock_ganti_note_test.dart` (widget checkout →
  internalNote), `void_restock_redo_flow_test.dart` (widget end-to-end
  Struk: tombol gated, tap → cart terisi, tawaran Pra-Bayar kondisional).

**Pending/menggantung dari sesi ini**: TIDAK ADA — fitur ini item tunggal,
sudah selesai sepenuhnya, tidak pernah masuk PLAN.md (baru didiskusikan &
langsung dieksekusi sesi berikutnya).

## Keputusan/pola penting yang masih berlaku (ringkas — detail di CLAUDE.md)

- Cart provider = family per `cartId` (`kMainCartId`/`kCatalogCartId`/`txId`).
  Jangan buat provider keranjang global baru.
- Gerbang lisensi (`license_provider.dart`/`license_service.dart`) — Ed25519
  murni-Dart, public key developer KOSONG = kill-switch aman (jangan hapus).
- `PriceMatchService` (sinkron harga antar-toko independen) — fuzzy-matching
  SENGAJA dihapus total, jangan ditambah lagi tanpa justifikasi baru.
- Barcode non-13-digit adalah kasus UTAMA (mayoritas data toko nyata), bukan
  edge case — kode label/sync/generator WAJIB anggap itu normal.
- Soft-delete/update master-data WAJIB cap ulang `updated_at` eksplisit;
  raw SQL write WAJIB sertakan `updates: {table}` biar StreamProvider refresh.
- Migrasi schema baru WAJIB memutakhirkan assersi `schemaVersion terkini`
  hardcoded di SEMUA file `test/migration_v*_test.dart` lama (lihat sesi
  ini — 19 file terlewat sebentar sampai full suite dijalankan).
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
