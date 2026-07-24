# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu
mencerminkan keadaan sekarang. Histori panjang ada di
[CHANGELOG.md](../CHANGELOG.md).

_Update sesi 24 Juli 2026 — commit `d4b17b9` (SELESAI, terverifikasi): 2 bug
nyata dilaporkan user diperbaiki sekaligus (restore backup gagal FK
constraint + usulan produk asisten hilang saat sync). Lanjutan dari sesi 23
Juli (Item 54/55/56/57, sudah selesai & di-commit sebelumnya)._

## Yang baru dikerjakan sesi ini

1. **Restore backup gagal total** dgn "FOREIGN KEY constraint failed ...
   DELETE FROM product_groups" (kode 787) — dialami user via screenshot
   error nyata. Akar masalah: `_allTables` (`app_database.dart`, dipakai
   `dumpAllTables`/`restoreFromDump`) tidak pernah diperbarui saat
   `product_group_tags` (Item 54) & `reserved_order_numbers` (Item 55)
   ditambah ke skema — baris lama `product_group_tags` tidak pernah ikut
   dihapus di awal restore (FK ke `products`+`product_groups`), masih
   menunjuk ke `product_groups` lama saat `DELETE FROM "product_groups"`
   dijalankan → SQLite menolak. Dampak diam-diam lain: kedua tabel itu
   juga tidak pernah ikut ter-backup sama sekali. **Kena SEMUA toko yang
   pernah pakai kategori-tambahan** — bukan kasus langka. Fix: tambahkan
   `product_group_tags` (posisi setelah `products`+`product_groups`, WAJIB
   sesuai dependensi FK) & `reserved_order_numbers` ke `_allTables`.
   `sync_upload_queue` SENGAJA tidak dimasukkan (antrian transient host,
   bukan data bisnis, tidak masuk akal di-restore dari backup lama).
2. **Usulan produk asisten hilang tanpa jejak dari antrian owner** setelah
   sync LAN, bahkan tanpa owner pindah layar sama sekali — dilaporkan &
   berhasil DIREPRODUKSI (test sekali-pakai, bukan cuma dugaan) sebelum
   diperbaiki. Akar masalah: `_pendingProposals` (`lan_sync_service.dart`)
   dikunci "satu slot per alamat IP pengirim" — kalau 2 device BERBEDA
   kebetulan tersambung dari IP yang SAMA (lazim di hotspot HP dgn pool
   DHCP kecil, setup umum toko kecil), sync device kedua MENIMPA slot
   device pertama walau usulannya belum sempat ditinjau owner. Fix: kunci
   slot (`PendingProductProposal.slotKey`) sekarang preferensi `deviceCode`
   (parameter baru opsional di `syncToHost`, dikirim via payload
   `'deviceCode'`, diteruskan dari `sync_state_provider.dart` pakai
   `device.deviceCode`) drpd IP mentah — fallback ke IP kalau klien lama
   belum kirim `deviceCode` (kompatibilitas mundur).
   - **BELUM diperbaiki, dicatat di PLAN.md**: `sync_upload_queue` (antrian
     sync transaksi/dll, BEDA dari antrian usulan produk) masih rawan bug
     yang SAMA (kunci per-IP mentah) — belum diperbaiki krn perlu migrasi
     skema (tambah kolom `device_code`) di sandbox yang codegen Drift-nya
     rusak (butuh hand-patch `app_database.g.dart` lagi).
   - Investigasi juga menutup pertanyaan susulan user: "kalau produk tidak
     ada di host, apakah produk di client bisa ke-delete otomatis?" —
     TIDAK, `mergeRows` murni upsert (INSERT/UPDATE), tidak pernah ada
     logika "hapus krn tidak ada di dump" utk data sync biasa. Tidak perlu
     pengaman tambahan di client utk skenario ini.

**Test baru** (semua revert-verified): `backup_restore_bug_test.dart`
(tambah 1 test kasus `product_group_tags`), `proposal_device_slot_key_test.
dart` (2 test: device beda IP sama vs device sama sync ulang).

## Status test suite

`flutter test` PENUH sukses jalan sampai selesai di commit ini: hanya
kegagalan pra-ada yang SUDAH dikenal (`proposal_unchanged_end_to_end_test.
dart` — "port already in use" krn port sync tetap yg dipakai bareng test
lain saat suite penuh jalan konkuren; lulus bersih saat dijalankan sendiri).
`flutter analyze` bersih (0 issue).

## Yang menggantung / belum sempat

- **PLAN.md item baru**: `sync_upload_queue` per-IP collision (lihat detail
  di atas) — sesi fokus tersendiri, butuh migrasi skema.
- Tidak ada lagi. Semua pekerjaan sesi ini sudah di-commit & push ke
  `claude/kategori-produk-qty-harga-mqjh21`.
