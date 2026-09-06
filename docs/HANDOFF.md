# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

> Catatan: sebelum sesi ini file ini sudah bertumbuh jadi >6000 baris log
> kronologis (bertentangan dengan tujuannya sbg snapshot ringkas hemat
> token). Ditulis ulang dari nol di sesi ini — histori detail sebelum
> tanggal di bawah ada di `git log`/CHANGELOG.md, BUKAN hilang, hanya
> sudah tidak diduplikasi di sini.

_Update sesi 6 September 2026 (sesi ketiga puluh). Versi kerja
**2.48.0+100** (MINOR naik, PATCH reset — fitur baru terlihat pengguna).
schemaVersion TETAP 40 — TIDAK ADA perubahan skema DB sesi ini (semua
state baru murni Dart-side: `CartMeta.replacesTxId`, persisted via
SharedPreferences seperti field `CartMeta` lain, bukan tabel Drift baru)._

## Sesi ini — "Batalkan & Susun Ulang" SELESAI & di-commit (`708996b`)

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
