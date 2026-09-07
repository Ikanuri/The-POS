# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 7 September 2026 (sesi ketiga puluh enam — redesain KEDUA
"Lunasi Hutang"). Versi kerja **2.52.0+108** (MINOR naik — redesain UX
terlihat pengguna). schemaVersion **43** (tidak berubah sesi ini — field
baru `invoiceId`/`invoiceDate` cuma ditambah ke dalam JSON string
`transactions.debtSettlementDetail` yang sudah nullable, tanpa migrasi)._

## Sesi ini — redesain KEDUA "Lunasi Hutang" SELESAI

User merevisi desain "Lunasi Hutang" LAGI (setelah redesain PERTAMA di sesi
32/`a254152` — toggle boolean tunggal pudar/solid di dalam list produk).
Backend (`settleMergedDebt`/`saveTransactionWithDebtSettlements`) **TIDAK
berubah logikanya** — cuma cara UI membuat entrinya berubah total.

**Perubahan desain:**
1. Entry point pindah dari baris toggle DI DALAM list produk (dihapus
   total, `_DebtSettlementCartRow`) ke chip pengingat hutang yang SUDAH
   ADA (merah, `Icons.account_balance_wallet_outlined`) — sekarang
   INTERAKTIF di 2 tempat: cart bar `kasir_screen.dart` (`_CartBar.
   onTapDebt`) & banner baru di dalam `cart_sheet.dart` (di atas list
   produk). Tap → `showDebtSettlementSheet` (`widgets/debt_settlement_
   sheet.dart`, file BARU).
2. Sheet "Pilih Nota untuk Dilunasi" — checklist SEMUA nota tempo/
   kurang_bayar pelanggan (REUSE `getUnpaidTxDetails`, query TIDAK
   berubah), toggle "Centang Semua", tombol "Terapkan".
3. `DebtSettlementEntry` (`cart_debt_settlement_provider.dart`) —
   RESTRUKTUR TOTAL: dulu list dibatasi maks 1 entri agregat (field
   `targetInvoices` = rencana FIFO lintas-nota via `planFifoSettlement`,
   DIHAPUS). SEKARANG: list bebas banyak entri, **SATU entri = SATU nota
   sumber** langsung (field baru `invoiceId`/`invoiceLocalId`/
   `invoiceDate` langsung di entri, bukan list target lagi). Partial
   per-nota (uncentang sebagian) didukung native.
4. Entri aktif tampil sbg baris TERPISAH di keranjang (`_DebtSettlementEntryRow`,
   `cart_sheet.dart`) — gaya visual SAMA PERSIS `_CartItemTile` 3-baris
   (nama 17px / tanggal 13px onSurfaceVariant / nominal numStyle 14px
   w700), leading `Icons.receipt_long_outlined`. Ditempel di UJUNG list
   produk dalam `ListView.separated` yang sama. Tap baris = hapus entri.
5. Total keranjang (nominal besar) = `totalAmount` + SUM entri aktif,
   breakdown "+ Lunasi Hutang Rp X (N nota)" di bawahnya (pola
   `_PrabayarFooterSummary._shrinkToFit`, reuse).
6. Struk (in-app/share/print) — baris "Turut lunasi Nota X" sekarang
   2-baris (nama nota + tanggal, posisi PERSIS pola qty·satuan·harga item
   produk biasa). `DebtSettlementDetailLine`/`parseDebtSettlementDetail`
   (`app_database.dart`) ditambah field `invoiceId`+`invoiceDate`
   (NULLABLE — JSON lama tanpa field ini tetap aman diparse, `invoiceId`
   fallback `''`, `invoiceDate` fallback `null`).
7. In-app struk (`receipt_screen.dart`) — "Nota X" jadi HYPERLINK (tap →
   `context.push('/kasir/struk/$invoiceId')`, pola SAMA persis
   `_preorderRefSpan`/`_preorderLinkRecognizers` yg sudah ada, REUSE pola
   TapGestureRecognizer per-id). HANYA in-app — share/print statis/gambar
   tidak bisa hyperlink.

**File baru**: `formatTanggalPendek` (`app_theme.dart`, dekat
`formatRupiah`) — format tanggal manual aman-locale (`_idMonthsShort`
ASCII), dipakai bareng sheet pemilihan nota, baris entri keranjang, & struk
in-app (SATU sumber format, bukan 3 implementasi terpisah).

**Test**: `test/cart_sheet_debt_settlement_test.dart` DITULIS ULANG total
(5 test: chip gate x3, tap-chip→Centang Semua→2 entri terpisah+Total naik,
partial-selection, tap-entri→hapus+Total turun) — `planFifoSettlement`
pure-function tests DIHAPUS (fungsinya sendiri sudah dihapus, tidak relevan
lagi). `test/debt_settlement_checkout_test.dart` — 4 test lama ditambah
`invoiceDate` ke tuple `targets`, +3 test baru (parse JSON lama tanpa
invoiceId/invoiceDate, parse JSON baru, `saveTransactionWithDebtSettlements`
menulis invoiceDate ke detail). Revert-verify dibuktikan manual (2 bug
sengaja disuntik — tap-hapus dimatikan, Centang Semua dirusak — test
terkait gagal dgn pesan relevan, lalu dikembalikan & hijau lagi).

Full suite & `flutter analyze`: **lihat commit terakhir sesi ini** (jalankan
`flutter test` kalau perlu angka pasti terkini — jangan asumsikan dari sini,
snapshot ini ditulis SEBELUM run penuh selesai kalau sesi terputus).

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
