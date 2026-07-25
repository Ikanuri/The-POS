# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 25 Juli 2026 — commit `ed6ff36` (SELESAI, terverifikasi): 4
permintaan user (1 fix tampilan + 2 fitur satuan berjenjang + 1 bug sync
yang ditemukan saat investigasi). Lanjutan dari sesi 24 Juli (restore FK +
usulan produk hilang, `d4b17b9`/`1a1224f`) yang sudah selesai sebelumnya._

## Yang baru dikerjakan sesi ini

1. **Nama produk 2 baris di keranjang** (`cart_sheet.dart`) — dulu
   `maxLines: 1` + ellipsis, sekarang `maxLines: 2`. Perubahan isolasi,
   `ListTile` otomatis menyesuaikan tinggi tanpa restrukturisasi
   leading/trailing (checkbox, stepper, harga tetap fixed-size).
2. **Stock Opname input per satuan berjenjang** (`stock_opname_screen.dart`)
   — produk dgn >1 satuan (mis. Pcs/Dus) dapat `DropdownButton` pemilih
   satuan per baris (HANYA produk berjenjang — keputusan eksplisit user,
   produk 1-satuan tidak berubah tampilannya). Qty yang diketik dikonversi
   ke satuan dasar via `ratio_to_base` SEBELUM masuk `_OpnameEntry.counted`
   (dipakai utk diff & `commitOpname` — fungsi itu sendiri TIDAK diubah).
   Layar review menampilkan "diketik: X {satuan}" di samping hasil
   konversi, supaya user tahu apa yg sebenarnya diketik.
3. **Cek Stok pilih satuan per-produk utk output** (`cek_stok_screen.dart`)
   — produk berjenjang yg dicentang (utk restock) dapat `DropdownButton`
   pemilih satuan (dimuat malas — baru query `getProductUnits` saat
   dicentang, bukan semua produk sekaligus). `_buildOrderText` (fitur
   "Order Restock" yg SUDAH ADA sebelumnya, dulu cuma `- {nama}` polos)
   diperluas jadi `"{qty} {satuan} {nama}"` (qty = stok terkini dikonversi
   ke satuan terpilih) — keputusan eksplisit user: perluas fitur lama,
   bukan bikin output terpisah.
4. **Fix bug sync kategori produk** (`app_database.dart`/
   `lan_sync_service.dart`) — ditemukan saat investigasi pertanyaan user
   "apakah kategori ikut sync?". `product_groups` (tabel kategori ITU
   SENDIRI — create/rename/delete/reorder, BEDA dari penugasan produk ke
   kategori yg sudah benar) lupa dimasukkan ke `dumpSince`'s `masterData`
   list & `clientMergeableTables` SEJAK AWAL fitur kategori dibuat. Fix:
   tambahkan ke kedua list. Full-dump tiap sync aman (tabel ini tidak
   punya `updated_at`) krn `deleteProductGroup` menombstone `name=null`
   (bukan DELETE baris sungguhan, slot id dipakai ulang) — jadi
   INSERT OR REPLACE polos sudah cukup, tidak perlu cleanup orphan spt
   `product_group_tags`.

**Test baru** (semua revert-verified): `cart_item_name_two_lines_test.dart`,
`stock_opname_unit_conversion_test.dart`, `cek_stok_unit_output_test.dart`,
`product_group_sync_test.dart` (real HTTP round-trip, pola sama spt
`proposal_unchanged_end_to_end_test.dart`).

## Status test suite

`flutter test` PENUH sukses jalan sampai selesai di commit ini: hanya
kegagalan pra-ada yang SUDAH dikenal (`proposal_unchanged_end_to_end_test.
dart` — "port already in use" krn port sync tetap yang dipakai bareng test
lain saat suite penuh jalan konkuren; lulus bersih saat dijalankan sendiri,
sudah didokumentasikan sejak sesi 24 Juli). `flutter analyze` bersih
(0 issue).

## Yang menggantung / belum sempat

- **PLAN.md item lama** (dicatat sesi 24 Juli, masih berlaku): `sync_
  upload_queue` (antrian sync transaksi, BEDA dari antrian usulan produk
  yang sudah diperbaiki) masih dikunci per-IP mentah — bug potensial yang
  SAMA, belum diperbaiki krn butuh migrasi skema (tambah kolom
  `device_code`) di sandbox yang codegen Drift-nya rusak.
- Tidak ada lagi. Semua pekerjaan sesi ini sudah di-commit & push ke
  `claude/kategori-produk-qty-harga-mqjh21`.
