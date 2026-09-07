# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 7 September 2026 (sesi ketiga puluh empat — fix `price_categories`
tidak ikut sync LAN/backup). Versi kerja **2.50.2+106** (PATCH naik — murni
bugfix data-integrity, tanpa fitur baru user-visible). schemaVersion **43**
(naik dari 42 — `price_categories.name` jadi nullable)._

## Sesi ini — fix bug sync/backup `price_categories` SELESAI

Audit manual (bukan laporan user) menemukan tabel `price_categories`
(master "Kategori Harga", Fase B — dibangun sesi-sesi sebelumnya) ADA di
`@DriftDatabase(tables: [...])` tapi TIDAK ADA di 3 tempat sekaligus:
1. `_allTables` (`dumpAllTables`/`restoreFromDump`, backup penuh/"Alihkan
   Owner").
2. `masterData` (`dumpSince`, sync LAN harian host->klien).
3. `LanSyncService.clientMergeableTables` (allowlist merge sisi klien —
   tanpa ini, walau host sudah kirim data via `masterData`, klien diam-diam
   MEMBUANG payloadnya).

Dampak: kategori yang owner buat tidak pernah sampai ke device kasir lain,
dan restore backup/"Alihkan Owner" menghapus semua kategori (nama
"Grosir" dkk hilang, `alt_prices.priceCategoryId` jadi orphan — produk
anggotanya sendiri tetap aman, cuma nama kategorinya hilang).

**Komplikasi yang WAJIB ditangani lebih dulu**: `deletePriceCategory()`
sebelumnya HARD DELETE baris kategori (beda dari `product_groups`, tabel
sejenis yang SUDAH tombstone `name=null` sejak awal). Sync satu-arah
host->klien di app ini (`dumpSince`/`mergeRows`) TIDAK PERNAH propagate
DELETE fisik — full-dump cuma bisa INSERT OR REPLACE apa yang ADA di host.
Kalau `price_categories` ditambah ke `masterData` dengan delete masih
hard-delete, penghapusan kategori TIDAK AKAN PERNAH terpropagasi ke klien
(kategori basi nyangkut selamanya).

**Fix (Opsi A — ikuti presedan `product_groups`, minimal-invasif)**:
- `PriceCategories.name` jadi NULLABLE (`pricing_tables.dart`).
  schemaVersion 42->43, migrasi `alterTable(TableMigration(priceCategories))`
  — dijaga dengan cek keberadaan tabel dulu (fixture test migrasi lama yang
  starting point-nya sudah di atas v40 tidak selalu bikin tabel ini).
- `deletePriceCategory()` diubah dari `delete(priceCategories)...` jadi
  `update(...).write(PriceCategoriesCompanion(name: Value(null)))` —
  logic pelepasan `alt_prices.priceCategoryId` sebelum delete TETAP
  dipertahankan apa adanya.
- `getAllPriceCategories()`/`watchPriceCategories()` filter
  `name IS NOT NULL` supaya kategori ditombstone tidak lagi tampil di UI
  (3 tempat baca: `kategori_harga_screen.dart`, `cart_sheet.dart` toggle
  chip, `price_category_margin_sheet.dart` picker — semua sudah pakai
  `!` non-null assertion karena filter query menjamin non-null).
- `price_categories` ditambahkan ke `_allTables` (posisi SEBELUM
  `alt_prices` — FK logis `alt_prices.priceCategoryId`), `masterData`
  (full-dump tiap sync tanpa delta `updated_at`, sama pola `product_groups`
  — TIDAK perlu kolom `updatedAt`/Opsi B, jumlah baris realistis kecil
  sepanjang hidup toko), dan `LanSyncService.clientMergeableTables`.

**Test** (semua baru, revert-verify dibuktikan — fix di-stash, test GAGAL
dgn pesan masuk akal, dikembalikan, hijau lagi):
- `test/migration_v43_test.dart` — kolom `name` jadi nullable via
  `PRAGMA table_info` (bukan cuma query ORM), data lama utuh.
- `test/price_categories_sync_test.dart` — create/rename/delete kategori
  di host ikut tersinkron ke klien via LAN HTTP **sungguhan** (pola
  `product_group_sync_test.dart`), termasuk kasus tombstone (klien tidak
  lagi lihat kategori yang dihapus, tapi baris fisiknya tetap ada).
- `test/price_categories_backup_test.dart` — `dumpAllTables`/
  `restoreFromDump` roundtrip, urutan FK terjaga (`alt_prices.
  priceCategoryId` tidak orphan setelah restore).
- `test/price_categories_db_test.dart` — assert tombstone tambahan di
  test `deletePriceCategory` yang sudah ada.

**Efek samping perlu-diperbaiki**: menaikkan `schemaVersion` ke 43 bikin
SEMUA `test/migration_v*_test.dart` lama (yang hardcode assert
`PRAGMA user_version` = versi lama) gagal — sudah diperbaiki (21 file,
assert dinaikkan ke 43). **Ini WAJIB dicek ulang tiap kali schemaVersion
naik** (sudah dicatat di §Keputusan di bawah, bukan hal baru, tapi
kelewat kena lagi sesi ini — jalankan full `flutter test` SEBELUM
menganggap migrasi baru selesai).

Full suite: **1546 test, semua lulus**, `flutter analyze`: 0 issue. (Catatan:
`test/proposal_unchanged_end_to_end_test.dart` sempat gagal 2x saat run
paralel penuh tapi lulus bersih saat dijalankan sendiri baik di kode lama
maupun baru — flake paralelisme tak terkait perubahan sesi ini, bukan
regresi.)

**Belum dikerjakan / cek sesi depan**: tidak ada — audit tuntas
dieksekusi, sudah di-merge ke `main`.

## Sesi sebelumnya (ringkas — detail lengkap di CHANGELOG.md)

- **7 September, sesi ketiga puluh tiga** (`b3bab3f`): fix "Batalkan &
  Susun Ulang" tidak membawa nama pelanggan terdaftar — akar masalah
  `Transactions.customerName` sengaja null utk pelanggan terdaftar, fungsi
  redo bawa nilai itu mentah ke `CartMeta` baru.
- **7 September, sesi ketiga puluh dua** (`a254152`): redesain toggle
  otomatis "Lunasi Hutang" di keranjang.
- **7 September, sesi ketiga puluh satu** (`7655706`, `0913408`): 3
  perbaikan kecil Pra-Bayar.

## Keputusan/pola penting yang masih berlaku (ringkas — detail di CLAUDE.md)

- Cart provider = family per `cartId` (`kMainCartId`/`kCatalogCartId`/`txId`).
  Jangan buat provider keranjang global baru.
- Tabel master-data BARU (mis. tabel Fase-baru) WAJIB langsung dicek masuk
  ke 3 tempat: `_allTables` (backup), `masterData` di `dumpSince` (sync
  harian), DAN `LanSyncService.clientMergeableTables` (allowlist sisi
  klien) — lupa salah satu = data itu diam-diam tidak pernah sampai ke
  device lain. `price_categories` lupa ke SEMUA TIGA, `product_groups`/
  `suppliers`/`purchases` pernah lupa sebagian juga sebelumnya (pola bug
  berulang, cek CHANGELOG utk riwayat lengkap).
- Tabel yang mendukung DELETE oleh user WAJIB tombstone (kolom nullable
  jadi penanda, mis. `name=null`), BUKAN hard delete, kalau mau ikut
  full-dump sync satu-arah host->klien (delete fisik tidak pernah
  ter-propagate). Pola: `product_groups`, sekarang juga `price_categories`.
- Menaikkan `schemaVersion` WAJIB memutakhirkan assersi
  `PRAGMA user_version` hardcoded di SEMUA `test/migration_v*_test.dart`
  lama ke versi baru — jalankan `flutter test` PENUH (bukan cuma file
  baru) sebelum yakin migrasi selesai; fixture migrasi lama yang skema
  awalnya minimal (starting point > tabel yang diubah) butuh guard
  "cek tabel ada dulu" sebelum `alterTable`/`addColumn`.
- `CartMeta.hasCustomer` cuma cek `customerName`, BUKAN `customerId` —
  siapa pun yang membentuk `CartMeta` baru (bukan lewat `setCustomer`)
  WAJIB pastikan `customerName` ikut terisi kalau `customerId` terisi.
- `Transactions.customerName` SENGAJA null utk pelanggan TERDAFTAR
  (`customerId` != null) — nama HARUS di-resolve ulang dari tabel
  `customers` kalau butuh ditampilkan/dibawa ke tempat lain.
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
