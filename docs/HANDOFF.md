# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 7 September 2026 (sesi ketiga puluh satu — 3 perbaikan/fitur
kecil seputar Pra-Bayar). Versi kerja **2.49.0+103** (MINOR naik, PATCH
reset — ada 1 fitur kecil terlihat pengguna: histori "kembalian diambil
sebelum checkout"; 2 lainnya murni bugfix). schemaVersion **41 -> 42** —
kolom baru nullable `transaction_payments.
prabayar_change_taken_before_checkout`._

## Sesi ini — 3 perbaikan Pra-Bayar SELESAI (`7655706`, `0913408`)

1. **Kalkulator Pra-Bayar mulai nol** — `_addPrabayar` (`cart_sheet.dart`)
   sekarang panggil `showDebtPaymentSheet(..., prefillRemaining: false)`.
   Pemanggil LAIN (Lunasi Hutang via `debt_settlement_picker.dart`, Buku
   Hutang) TIDAK diubah — mereka memang mau prefill `remaining`.
2. **Footer Pra-Bayar tidak lagi terpotong** — `_PrabayarFooterSummary`
   (Pra-Bayar/Sisa/Kembalian/riwayat kembalian diambil) & baris "Turut
   lunasi hutang" di sebelahnya sekarang dibungkus `FittedBox(fit:
   scaleDown, alignment: centerLeft)` per baris (pola sama nominal
   "Total" di atasnya yang sudah dinamis dari sesi sebelumnya) — gantikan
   `TextOverflow.ellipsis` polos yang memotong nominal besar (mis. lebih
   dari Rp 12 juta) secara permanen & tak terbaca. Teks widget (`.data`)
   tetap utuh, cuma render-nya yang mengecil otomatis.
3. **Riwayat Pembayaran mencatat kembalian Pra-Bayar yang sudah diambil
   sebelum checkout** — sebelumnya, porsi `changeTakenTotal` (checkbox
   "kembalian sudah diambil" di footer keranjang, fase Pra-Bayar) dipotong
   LANGSUNG dari `amount` baris `TransactionPayments` terkait
   (`buildPrabayarCheckout`, `payment_screen.dart`) TANPA jejak — kembalian
   itu "menghilang" dari riwayat, seolah tidak pernah terjadi.

   **Fix (bukan mengubah invariant lama)**: kolom baru NULLABLE
   `TransactionPayments.prabayarChangeTakenBeforeCheckout` (int,
   schemaVersion 41->42) — metadata MURNI, diisi HANYA utk baris yang
   kena potongan mundur, berisi NOMINAL yang dipotong dari entri itu.
   `amount`/`changeGiven` baris TETAP seperti sebelumnya (uang sungguhan
   yang tercatat diterima kasir) — invariant `Σ payments.amount ==
   combinedPaid` (dilindungi `payment_prabayar_checkout_test.dart`) TIDAK
   berubah sama sekali, cuma ditambah test regresi eksplisit utk
   membuktikannya masih terjaga.

   Kartu "Riwayat Pembayaran" in-app (`receipt_screen.dart`,
   `_buildPaymentTimeline`) menampilkan baris keterangan tambahan italic
   "Kembalian Rp Y sudah diambil sebelum checkout" di bawah baris
   pembayaran yang membawa metadata ini — SENGAJA beda visual dari
   `_ChangeTakenRow` (tanpa checkbox, kalimat eksplisit) supaya tidak
   tertukar makna dgn kembalian NORMAL baris "sekarang"/kasir loket.

   **Keputusan: TIDAK ditambahkan ke struk cetak/share**
   (`printer_service.dart`) — ini detail audit teknis-transaksional
   (kembalian yang sudah diselesaikan tuntas SEBELUM nota ini bahkan
   ada), bukan informasi yang perlu diketahui ulang lewat struk fisik;
   in-app Riwayat Pembayaran sudah tempat yang tepat utk audit rinci,
   struk cetak/share tetap ringkas. Beda dari "Lunasi Hutang" (3 jenis
   struk) yang memang perlu diketahui pelanggan/kasir di kertas.

**Migrasi schemaVersion 41->42**: 19 file `test/migration_v*_test.dart`
lama diupdate (assert `PRAGMA user_version` 41 -> 42 — WAJIB tiap bump
schemaVersion, sudah 3x kejadian di sesi-sesi sebelumnya, jangan lupa
lagi). Test migrasi baru `migration_v42_test.dart` SENGAJA assert langsung
`PRAGMA table_info` (bukan cuma query ORM `select(table)`) — ditemukan
saat revert-verify bahwa drift's `SELECT *` forgiving thd kolom fisik
yang hilang (baca `null` diam-diam), jadi query ORM saja TIDAK cukup utk
membuktikan migrasi benar-benar menambah kolom.

**Test** (revert-verify dibuktikan utk semua 3 poin — masing-masing
di-stash sesaat, terbukti gagal dgn pesan yang masuk akal, baru
dikembalikan):
- `test/cart_sheet_prabayar_test.dart` — kalkulator mulai 0 (bukan
  prefill), nominal besar (Rp 12.345.678+) di 360dp tidak overflow &
  `Text.overflow` sudah bukan `ellipsis` lagi.
- `test/payment_prabayar_checkout_test.dart` — metadata
  `prabayarChangeTakenBeforeCheckout` (potongan satu entri, potongan
  melintasi 2 entri, entri habis terpotong, default 0) + round-trip DB
  sungguhan + invariant `Σamount == combinedPaid` eksplisit.
- `test/receipt_prabayar_change_taken_before_checkout_test.dart` — baris
  keterangan tampil/tidak tampil sesuai metadata.
- `test/migration_v42_test.dart` — kolom fisik benar ditambahkan.

Full suite: **1541 test** (1540 lulus + 1 pre-existing flaky
order-dependent `proposal_unchanged_end_to_end_test.dart`, TERBUKTI lulus
isolated baik SEBELUM maupun SESUDAH perubahan sesi ini — bukan
regresi). `flutter analyze`: 0 issue.

**Belum dikerjakan / cek sesi depan**: tidak ada — ketiga poin briefing
tuntas dieksekusi.

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
