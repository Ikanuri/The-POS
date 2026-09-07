# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 7 September 2026 (sesi ketiga puluh delapan — sejajarkan baris
Lunasi Hutang dgn baris produk di struk, susulan redesain ketiga). Versi
kerja **2.53.1+110** (PATCH — murni fix alignment visual, bukan fitur
baru). schemaVersion **43** (tidak berubah)._

## Sesi ini — sejajarkan baris "Lunasi Nota #X" dgn baris produk (struk in-app) SELESAI

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
