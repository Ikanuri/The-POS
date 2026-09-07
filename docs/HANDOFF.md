# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 7 September 2026 (sesi ketiga puluh dua — redesain toggle
"Lunasi Hutang"). Versi kerja **2.50.0+104** (MINOR naik, PATCH reset —
perubahan UX terlihat pengguna: cara pakai fitur "Lunasi Hutang" diganti
total). schemaVersion TIDAK berubah (masih 42, tidak ada migrasi sesi
ini)._

## Sesi ini — redesain toggle "Lunasi Hutang" SELESAI (`a254152`)

Fitur "Lunasi Hutang" (dibangun sesi sebelumnya, `a921860` dkk) direvisi
TOTAL atas permintaan user — alasan: (1) ikon terpisah di footer
`cart_sheet.dart` makan ruang yang sudah padat (sebelah Pra-Bayar), (2)
BISA MISCLICK pilih hutang pelanggan LAIN, bukan pelanggan yang sedang
diinput di cart bar.

**Desain lama (dihapus total)**: ikon "Lunasi Hutang" di footer -> buka
`debt_settlement_picker.dart` (pilih pelanggan berhutang -> checklist nota
tempo miliknya -> kalkulator nominal manual `showDebtPaymentSheet`). File
`debt_settlement_picker.dart` DIHAPUS total (dicek dulu, tidak ada
pemanggil lain).

**Desain baru**: satu baris toggle `_DebtSettlementCartRow`
(`cart_sheet.dart`) DI DALAM daftar item keranjang itu sendiri (bukan
produk, item tambahan di ujung `ListView.separated`) — muncul HANYA bila
(a) gerbang izin sama persis Pra-Bayar (`canDebtSettlement`: kasir utama
`kMainCartId` + `terima_pembayaran`), (b) `CartMeta.customerId` keranjang
ini terisi, DAN (c) `cartCustomerDebtProvider(customerId)` > 0 (pelanggan
ITU, bukan pelanggan lain, yang punya hutang). Default REDAM (`Opacity`
0.5, ikon `Icons.account_balance_wallet_outlined` konsisten dgn pengingat
hutang cart bar). Tap pertama -> solid (tint `scheme.tertiary`) & OTOMATIS
membuat SATU `DebtSettlementEntry` senilai SELURUH `customerDebt.total`
(bukan manual/parsial) — rencana FIFO ke nota lama tetap dihitung via
`planFifoSettlement` yang SUDAH ADA (logika TIDAK diubah, cuma dipindah
dari `debt_settlement_picker.dart` ke `cart_debt_settlement_provider.dart`,
sumbernya sekarang `getUnpaidTxDetails` OTOMATIS bukan checklist manual).
Tap lagi -> kembali pudar, entri (dicari via `customerId`) dihapus.
Paling banyak SATU entri per cart (API list `cartDebtSettlementProvider`
DIPERTAHANKAN, bukan diganti nullable tunggal — format hold/resume JSON
`kasir_screen.dart` tidak perlu migrasi).

**Keputusan metode pembayaran entri** (tidak ada lagi kalkulator/pemilihan
metode terpisah di titik toggle): `DebtSettlementEntry.method` diisi
placeholder `'tunai'` saat entri otomatis dibuat, lalu `payment_screen.
dart` MENIMPA `method`/`methodName` dengan metode FINAL yang kasir pilih
di layar Bayar (`_selectedMethodType`/`_selectedMethod?.name`) tepat
sebelum `saveTransactionWithDebtSettlements` — rasionalnya: kasir cuma
menerima SATU nominal fisik gabungan (belanja + turut lunasi hutang)
sekali jalan, jadi metodenya logis ikut metode transaksi baru itu sendiri.
Pengecualian: metode final `'tempo'` (Bayar Nanti — TIDAK ada uang fisik
diterima sama sekali) jatuh ke `'tunai'` sbg asumsi netral (bukan klaim
metode spesifik yang tidak pernah dipilih kasir) — edge case jarang
(kasir menunda bayar belanja baru TAPI tetap menerima uang tunai utk
melunasi hutang lama pelanggan yang sama), tidak diminta eksplisit user,
diputuskan sendiri & didokumentasikan di sini.

**TIDAK berubah** (dicek eksplisit, logika lama dipakai apa adanya):
`planFifoSettlement`, `settleMergedDebt`, `saveTransactionWithDebtSettlements`,
`_grandTotal`/kartu info "Turut Lunasi Hutang" checkout, struk
(`debtSettlementDetail`), siklus hold/resume (`kasir_screen.dart`, masih
generik List, sekarang isinya maks 1).

**Test**: `test/cart_sheet_debt_settlement_test.dart` ditulis ulang total
(hapus test UI lama — ikon footer, alur picker 3 langkah; tambah test
toggle baru: gerbang izin, gerbang `customerId`+`debt>0` termasuk "ada
pelanggan LAIN yang berhutang tapi TIDAK terikat cart ini", tap
aktif/nonaktif + verifikasi entri FIFO benar) — tetap pertahankan 3 test
`planFifoSettlement` (pure, logika tidak berubah). Revert-verify
dibuktikan (disable `_toggle` sesaat -> test toggle gagal dgn pesan
"Expected 1.0, Actual 0.5" yang masuk akal -> dikembalikan, hijau lagi).
`debt_settlement_checkout_test.dart` (DB-level, backend
`saveTransactionWithDebtSettlements`) TIDAK disentuh sama sekali, tetap
hijau tanpa perubahan (backend tidak diubah).

Full suite: **1540 test**, semua lulus. `flutter analyze`: 0 issue.

**Belum dikerjakan / cek sesi depan**: tidak ada — briefing tuntas
dieksekusi.

## Sesi sebelumnya (ringkas — detail lengkap di CHANGELOG.md)

- **7 September, sesi ketiga puluh satu** (`7655706`, `0913408`): 3
  perbaikan kecil Pra-Bayar — kalkulator mulai Rp 0 (bukan prefill),
  footer Pra-Bayar/Lunasi-Hutang dibungkus `FittedBox` (nominal besar tak
  lagi terpotong), Riwayat Pembayaran mencatat kembalian Pra-Bayar yang
  sudah diambil sebelum checkout (kolom baru `TransactionPayments.
  prabayarChangeTakenBeforeCheckout`, schemaVersion 41->42).
- **6 September, sesi ketiga puluh** (`a921860` dkk): versi AWAL fitur
  "Lunasi Hutang" (ikon footer + picker manual) — sudah digantikan TOTAL
  oleh redesain toggle sesi ini, lihat di atas.

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
