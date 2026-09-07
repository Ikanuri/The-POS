# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md); rencana yang masih menggantung ada di
[PLAN.md](../PLAN.md).

_Update sesi 7 September 2026 (sesi ketiga puluh lima — "Ekspor Arsip
Tahunan"). Versi kerja **2.51.0+107** (MINOR naik — fitur baru terlihat
pengguna). schemaVersion **43** (tidak berubah sesi ini)._

## Sesi ini — fitur "Ekspor Arsip Tahunan" SELESAI

Audit menemukan file arsip tahunan (`archive_YYYY.db`, hasil "Tutup Buku",
arsip TAHUNAN — beda dari "Tutup Kasir" harian) TIDAK PERNAH ikut backup
app sama sekali: `DbExportService.exportPortable`/`exportOwnerTransfer`
(dipakai Backup & Restore/Alihkan Owner) cuma baca `main.db`. Kalau device
rusak/hilang SETELAH tutup buku, data yang sudah diarsipkan bisa hilang
permanen (cuma tersimpan lokal, tidak ikut backup apa pun).

**Fix**: fitur "Ekspor Arsip" baru, format & entry-point SENGAJA TERPISAH
dari backup biasa (instruksi eksplisit user) supaya tidak disalahpahami
sbg pengganti backup utuh (arsip cuma 1 tahun, backup biasa = seluruh DB
aktif):
- `DbExportService.exportArchive({archiveDb, password, year})` — magic
  baru **`BPOA1`** ("`.posarsip`"), pola SAMA `exportPortable` (PBKDF2
  password+salt acak, gzip(JSON dump)+AES, `CryptoService.
  derivePortableKeyV2`) tapi sumbernya `archiveDb` (dibuka via
  `ArchiveService.open`), bukan `main.db`. Payload tambah field `year`.
  `decrypt()` biasa (jalur restore-seluruh-DB) mendeteksi magic BPOA1 lebih
  dulu & throw pesan jelas "Ini file arsip tahunan (.posarsip), bukan file
  backup biasa" — **restore arsip SENGAJA belum diimplementasikan** (user
  cuma minta ekspor; kalau nanti diminta, harus masuk ke `archive_YYYY.db`
  terpisah, BUKAN `restoreFromDump` ke `main.db`).
- `arsip_screen.dart`: tiap baris `_ArchiveCard` dapat tombol "Ekspor Arsip
  Ini" (`Icons.ios_share`, beda dari `Icons.bar_chart_outlined` "Lihat
  Ringkasan") → dialog password (REUSE pola persis `backup_screen.dart`:
  min 8 karakter) → `ArchiveService.open(year, encryptionKey)` →
  `exportArchive` → `saveOrShareExport` (share sheet/simpan lokal, pola
  existing) → `ArchiveService.close()` di `finally` (tidak nyangkut
  terbuka). Kalau ringkasan arsip sedang terbuka (`_archiveDb != null`)
  saat tombol ekspor ditekan, direset dulu (ArchiveService cuma pegang
  SATU koneksi global — `open()` baru auto-close yang lama).
- Nama file: **`arsip_toko_$year.posarsip`** — beda ekstensi dari
  `.berkahpos` (backup biasa) supaya user tidak salah kira ini pengganti
  backup utuh.

**Isu lingkungan CI ditemukan & dipecahkan** (tidak terkait fitur, tapi
menghambat widget test): `Directory.list()`/`File.copy()` (dart:io async
isolate-based I/O) **HANG TANPA BATAS** (10 menit lalu timeout) di dalam
`testWidgets` sandbox lingkungan CI ini — dikonfirmasi lewat reproduksi
terisolasi (`test()` biasa & operasi `NativeDatabase`/FFI sqlite3 aman,
HANYA dart:io isolate-based I/O yang kena). `ArchiveService.listArchives`
(dipakai provider daftar arsip) pakai `Directory.list()` → widget test yang
merender `ArsipScreen` dgn arsip nyata dari disk akan HANG. Solusi: provider
`archiveListProvider` (di `arsip_screen.dart`) diekspos (bukan private lagi)
supaya widget test bisa override-nya langsung (skip `Directory.list()`
sama sekali), dan arsip test dibuat LANGSUNG via `NativeDatabase` (FFI,
BUKAN lewat `TutupBukuService.execute` yang pakai `File.copy` async).
`test/helpers/pump_app.dart` — `pumpWithFakeApp` sekarang terima
`extraOverrides` opsional (list `Override` tambahan di luar
`databaseProvider`/`deviceProvider`) untuk kasus serupa nanti.
**Catat ini di CLAUDE.md/gotcha kalau bug serupa muncul lagi** — screen
manapun yang exercise `Directory.list()`/`File.copy()` real (bukan lewat
`NativeDatabase`) butuh trik yang sama (provider override / hindari, BUKAN
`tester.runAsync()` — sudah dicoba, TIDAK cukup karena provider yang
dipanggil otomatis dari `ref.watch()` selama build tetap jalan di FakeAsync
test zone, di luar kendali `runAsync` eksplisit).

**Test** (semua baru, revert-verify dibuktikan — fix di-stash, test gagal
compile-error yg relevan, dikembalikan, hijau lagi):
- `test/archive_export_test.dart` — magic bytes BPOA1, round-trip manual
  decrypt (payload valid, field `year` benar), password salah gagal
  dibongkar, `decrypt()` biasa menolak BPOA1 dgn pesan "arsip".
- `test/arsip_export_widget_test.dart` — tombol "Ekspor Arsip Ini" muncul
  per baris, dialog password menyebut tahun yang benar, validasi panjang
  password, `ArchiveService.open`/`exportArchive` benar2 terpanggil
  (arsip nyata dibaca via FFI), lanjut ke dialog `saveOrShareExport`,
  koneksi arsip ditutup lagi setelah selesai/dibatalkan.

Full suite: **1551 test, semua lulus**, `flutter analyze`: 0 issue.

**Belum dikerjakan / cek sesi depan**: restore arsip (`.posarsip` →
`archive_YYYY.db`) belum diimplementasikan sama sekali — SENGAJA (user
cuma minta ekspor). Kalau diminta nanti: payload SUDAH punya field `year`,
tinggal tulis fungsi `restoreArchive` yang menulis ke `archive_YYYY.db`
terpisah (JANGAN pakai `DbExportService.restore`/`restoreFromDump` yang
menyasar `main.db`).

## Sesi sebelumnya (ringkas — detail lengkap di CHANGELOG.md)

- **7 September, sesi ketiga puluh empat** (`0d739f6`): fix
  `price_categories` tidak ikut sync LAN & backup penuh (3 tempat
  sekaligus lupa: `_allTables`/`masterData`/`clientMergeableTables`).
- **7 September, sesi ketiga puluh tiga** (`b3bab3f`): fix "Batalkan &
  Susun Ulang" tidak membawa nama pelanggan terdaftar.
- **7 September, sesi ketiga puluh dua** (`a254152`): redesain toggle
  otomatis "Lunasi Hutang" di keranjang.

## Keputusan/pola penting yang masih berlaku (ringkas — detail di CLAUDE.md)

- Cart provider = family per `cartId` (`kMainCartId`/`kCatalogCartId`/`txId`).
  Jangan buat provider keranjang global baru.
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
