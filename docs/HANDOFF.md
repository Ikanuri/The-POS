# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 25 Juli 2026 — commit `d7b8851` (SELESAI, terverifikasi):
lanjutan langsung dari commit `ed6ff36` sesi yang sama (4 permintaan user +
fix sync kategori). Item ini menutup 2 hal: bug `sync_upload_queue` yang
tadinya ditunda krn butuh migrasi skema, dan Item 38 di PLAN.md yang
ternyata TERBUKTI berdampak nyata._

## Yang baru dikerjakan sesi ini

1. **Fix `sync_upload_queue` per-IP collision** (sama persis dgn bug
   `_pendingProposals` yang sudah diperbaiki commit `d4b17b9`) — kolom baru
   `SyncUploadQueue.deviceCode` (nullable, migrasi v20->v21, guard
   `from >= 18` krn `createTable` di step v18 sudah pakai definisi tabel
   TERKINI shg addColumn lagi akan gagal "duplicate column" utk upgrade
   yang lewat kedua step di satu chain). `enqueueSyncUpload` sekarang kunci
   slot "1 per pengirim" pakai `deviceCode` (fallback `fromIp` utk klien
   lama yg belum kirim). `lan_sync_service.dart`: parsing `rawDeviceCode`
   dipindah lebih awal, dipakai ulang utk kedua antrian (proposal + upload
   queue) — tidak lagi diparse 2x.
2. **Fix Item 38 (PLAN.md) — `_rawBaseStock` tie-break tidak kronologis**
   — ditemukan TAK SENGAJA lewat investigasi flake test Stock Opname
   (`stock_opname_unit_conversion_test.dart` gagal ~1-in-5 di full-suite,
   TIDAK reproducible isolasi). Sempat salah duga akar masalah popup
   `DropdownButton` timing (rewrite ke `onChanged` langsung TIDAK
   menghilangkan flake) — debug print `stock_ledger` row content
   membuktikan WRITE benar, READ salah → `ORDER BY created_at DESC, id
   DESC`: `created_at` presisi detik, `id` UUID acak, 2 tulis stok di
   detik sama bisa salah pilih baris lama. Fix: tie-break kedua pakai
   `rowid` SQLite built-in (monoton sesuai insert, tanpa migrasi).
   **Sudah dibuktikan berdampak nyata** (bukan cuma teoretis spt status
   PLAN.md sebelumnya) — item ini SUDAH DIHAPUS dari PLAN.md.

**Test baru** (semua revert-verified): `migration_v21_test.dart`,
`sync_upload_queue_device_slot_key_test.dart` (real HTTP round-trip),
`stock_ledger_tiebreak_test.dart` (deterministic DB-level, id string
sengaja dibalik leksikografis supaya bug ke-trigger PASTI, bukan
untung-untungan UUID acak).

## Audit pra-rilis 2.2.0 (25 Juli) — hasil & 2 fix susulan

Diminta user sebelum memutuskan tag resmi. **Verifikasi bersih**: 677 test
hijau, analyze 0 issue, APK build hijau di CI (`e796189`), rantai migrasi
v1→v21 konsisten (tiap `addColumn` yg tabelnya pernah di-`createTable`
lebih awal SUDAH ber-guard), bug kelas `_allTables` TIDAK terulang
(`sync_upload_queue` satu-satunya yg dikecualikan & itu benar: tanpa FK +
antrian transien), tak ada pola crash di kode baru, tak ada TODO/`print`
bocor.

**2 temuan, keduanya sudah diperbaiki** (lihat CHANGELOG utk detail):
1. `_loadUnits()` Stock Opname N+1 berlapis + memblokir seluruh layar di
   balik spinner → satu query JOIN (`getUnitsWithTypeNamesFor`). Diukur:
   1000 produk = 3000 query/441ms → 1 query/7ms.
2. Dialog "Sesuaikan Stok" `autofocus` + field terisi = ketikan MENEMPEL
   (stok 5 + ketik "12" → tersimpan 512, bahaya data nyata, bukan cuma
   merepotkan) → select-all. Plus field Poin pelanggan berhenti prefill '0'.

**Sisa risiko yang TIDAK bisa ditutup test otomatis** (perlu Anda coba di
device fisik sebelum tag resmi): **Item 32** scanner HID (PLAN.md sendiri
menandai "TIDAK BISA diverifikasi otomatis", masih menunggu konfirmasi
user) & **uji printer thermal Bluetooth Android ≤11** (Item 41/D.1).
Surface rilis ini besar: 157 commit sejak 2.1.1, nol jam pemakaian toko
nyata.

## Status test suite

`flutter test` PENUH: **681 test, 679 hijau**. `flutter analyze` bersih
(0 issue).

2 kegagalan sisa = **flake port, BUKAN regresi**: `lan_sync_item41_test.
dart` gagal dgn `SocketException: Address already in use, port = 8625`.
**8625 itu port sync TETAP milik app** (`lan_sync_service.dart`), dan 4
file test real-HTTP memperebutkannya saat `flutter test` menjalankan file
secara paralel: `lan_sync_item41_test.dart`, `lan_sync_slow_transfer_test.
dart`, `lan_sync_timeout_test.dart`, `proposal_unchanged_end_to_end_test.
dart`. Lolos bersih 2/2 saat dijalankan sendiri — sudah diverifikasi, dan
kelas flake yg sama sudah tercatat sejak sesi 24 Juli (dulu muncul di
`proposal_unchanged_end_to_end_test.dart`). Kalau mau benar-benar
dihilangkan: port harus bisa disuntik per-test (bukan konstanta), itu
perubahan pada kode produksi jadi ditahan dulu.

Flake lama `stock_opname_unit_conversion_test.dart`/`cek_stok_unit_output_
test.dart` (akar masalahnya Item 38) dikonfirmasi HILANG — 3x run batch
berulang semua bersih.

## Yang menggantung / belum sempat

- Tidak ada item baru dari sesi ini. Semua pekerjaan sudah di-commit &
  push ke `claude/kategori-produk-qty-harga-mqjh21`.
- Item lama yang masih terbuka: lihat `PLAN.md` (Item 17+21 sync ditunda
  sesi fokus, Item 23 sisa, Item 28 konsep, Item 32 tunggu konfirmasi user
  device fisik, Item 41 sisa P3, Item 51 tunggu keputusan user).
