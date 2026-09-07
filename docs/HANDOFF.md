# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 7 September 2026 (sesi ketiga puluh tiga — fix "pelanggan
tidak terbawa" di "Batalkan & Susun Ulang"). Versi kerja **2.50.1+105**
(PATCH naik — murni bugfix, tanpa fitur baru). schemaVersion TIDAK berubah
(masih 42, tidak ada migrasi sesi ini)._

## Sesi ini — fix bug "pelanggan tidak terbawa" SELESAI (`b3bab3f`)

User laporkan: fitur "Batalkan & Susun Ulang" (`_redoCartFromVoidedTransaction`,
`tx_history_sheet.dart`, dibangun sesi ke-30/31) tidak membawa identitas
pelanggan ke keranjang baru, walau kodenya secara statis terlihat benar.

**Hipotesis awal (dari briefing tugas) — TERBUKTI SALAH**: race
`CartMetaNotifier._load()` (async, tidak di-`await` di constructor) vs
`.replaceAll()` yang dipanggil segera sesudahnya. Dibuktikan false lewat
analisis alur sinkron murni (tanpa perlu test tambahan khusus race ini):
`ref.read(cartMetaProvider(...).notifier)` mengembalikan instance secara
SINKRON, constructor memanggil `_load()` yang suspend di `await
SharedPreferences.getInstance()` — baris `.replaceAll(...)` berikutnya
tetap jalan SEBELUM continuation `_load()` bisa resume (tidak ada `await`
di antara keduanya). Saat continuation itu akhirnya resume, ia membaca
`state.isEmpty` LIVE (bukan snapshot lama) — sudah `false` karena
`replaceAll` sudah jalan duluan. Race ini TIDAK bisa terjadi pada urutan
kode yang ada.

**Akar masalah SEBENARNYA (dibuktikan test nyata, `test/void_restock_redo_flow_test.dart`)**:
`Transactions.customerName` SENGAJA disimpan `null` di DB untuk pelanggan
TERDAFTAR (`customerId` satu-satunya sumber kebenaran — lihat dok kolom
di `transaction_tables.dart`, dan `payment_screen.dart` baris
`customerName = _selectedCustomer == null ? ... : null`). Tapi
`_redoCartFromVoidedTransaction` membawa `tx.customerName` MENTAH ke
`CartMeta` baru — hasilnya `customerId` terisi benar, `customerName`
null. `CartMeta.hasCustomer` **cuma mengecek `customerName`** (bukan
`customerId`), jadi chip pelanggan di cart bar (`kasir_screen.dart`) &
label "Tahan Pesanan" (`_holdCurrent`) tampil seakan TIDAK ADA pelanggan
sama sekali — walau `customerId` sudah benar tersimpan di state
(`payment_screen.dart` sendiri sebenarnya tetap pra-pilih pelanggan
dengan benar via `meta.customerId`, independen dari `hasCustomer` — bug
ini murni soal TAMPILAN sebelum checkout, tapi itu yang dilihat & dikira
"tidak berfungsi" oleh user).

**Fix**: resolve nama pelanggan TERKINI dari tabel `customers` via
`customerId` (pola sama pencocokan `matchedEmployee` yang sudah ada di
fungsi itu) sebelum membentuk `CartMeta` — jadi `CartMeta` yang terbentuk
SELALU konsisten dgn hasil `setCustomer(id, name)` normal (bawa id+nama
sekaligus, tidak pernah id-tanpa-nama). `CartMeta.hasCustomer` SENGAJA
TIDAK diubah (banyak tempat pakai `meta.customerName!` dgn asumsi
non-null saat `hasCustomer` true — ubah semantiknya jadi
`customerId != null || customerName...` berisiko null-check crash di
tempat lain tanpa audit penuh; fix di titik penulisan CartMeta jauh lebih
minimal & aman).

**Test**: 1 test baru (pelanggan terdaftar + insert row `customers`) —
revert-verify dibuktikan (fix di-stash, test GAGAL dgn
`Expected: 'Bu Sari', Actual: <null>` — pesan yang masuk akal & langsung
mencerminkan bug, bukan error lain — dikembalikan, hijau lagi). 3 test
lama di file yang sama (redo lunas+prabayar, redo tempo, guard retur)
tetap hijau tanpa perubahan perilaku (regresi terjaga).

Full suite: **1541 test, semua lulus** (1 run sebelumnya sempat 1540+1
gagal karena flake tak terkait — re-run bersih 0 gagal). `flutter
analyze`: 0 issue.

**Belum dikerjakan / cek sesi depan**: tidak ada — briefing tuntas
dieksekusi.

## Sesi sebelumnya (ringkas — detail lengkap di CHANGELOG.md)

- **7 September, sesi ketiga puluh dua** (`a254152`): redesain toggle
  otomatis "Lunasi Hutang" — ikon footer terpisah dihapus, diganti baris
  toggle di dalam daftar item keranjang (`_DebtSettlementCartRow`,
  `cart_sheet.dart`), otomatis lunasi SELURUH hutang pelanggan yg
  terikat cart via `customerId` (bukan pilih manual).
- **7 September, sesi ketiga puluh satu** (`7655706`, `0913408`): 3
  perbaikan kecil Pra-Bayar — kalkulator mulai Rp 0 (bukan prefill),
  footer Pra-Bayar/Lunasi-Hutang dibungkus `FittedBox`, Riwayat
  Pembayaran mencatat kembalian Pra-Bayar yang diambil sebelum checkout.

## Keputusan/pola penting yang masih berlaku (ringkas — detail di CLAUDE.md)

- Cart provider = family per `cartId` (`kMainCartId`/`kCatalogCartId`/`txId`).
  Jangan buat provider keranjang global baru.
- `CartMeta.hasCustomer` cuma cek `customerName`, BUKAN `customerId` —
  siapa pun yang membentuk `CartMeta` baru (bukan lewat `setCustomer`)
  WAJIB pastikan `customerName` ikut terisi kalau `customerId` terisi
  (lihat fix sesi ini) — kalau tidak, chip pelanggan & alur yang
  bergantung pada `hasCustomer` akan salah kira "tidak ada pelanggan".
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
- Migrasi schema baru WAJIB memutakhirkan assersi `schemaVersion terkini`
  hardcoded di SEMUA file `test/migration_v*_test.dart` lama — dan uji
  keberadaan kolom via `PRAGMA table_info`, JANGAN cuma via query ORM
  drift (`select(table)` pakai `SELECT *`, forgiving thd kolom hilang).
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
