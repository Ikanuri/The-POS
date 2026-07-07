# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 7 Juli 2026 (audit + pemeriksaan ulang menyeluruh)._

---

## Di Mana Kita Sekarang

Sesi **audit kode menyeluruh** pasca rilis v2.1.0: seluruh lib/ dibaca,
14 bug ditemukan (2 Tinggi, 5 Sedang, 7 Rendah) + inventaris kode mati.
User memilih (via poll): **fix semua** + bersihkan kode mati. Selesai di
commit `7d1fc6f` (fix) + `81f1af6` (cleanup). Pemeriksaan ULANG menyeluruh
atas permintaan user menemukan 3 temuan lanjutan (semuanya dalam mandat
poll yang sama) — diperbaiki di `c1bafd7`:
- 'Lunasi' di Riwayat Transaksi & 'Tambah Bayar' di tab Laporan masih
  memakai pola lama B7 → keduanya kini lewat `addPaymentToTransaction`
  (satu-satunya jalur pelunasan; jangan tulis paid/changeAmount manual
  dari UI lagi).
- `filterArchivedRows` kini per TAHUN YANG PUNYA FILE ARSIP
  (`TutupBukuService.listArchivedYears`), bukan cutoff `last_archive_year`
  — tahun sebelum arsip pertama tidak pernah diarsip & datanya masih sah.
`flutter analyze` bersih, **106 test hijau** (91 lama + 15 regresi baru di
`test/audit_fixes_test.dart` — tiap fix dibuktikan gagal saat di-revert
sementara, sesuai metodologi CLAUDE.md).

### Fix penting sesi ini (commit `7d1fc6f`)
1. **B1 (Tinggi)** — transaksi tahun ter-tutup-buku tidak lagi "hidup lagi"
   di host lewat sync: `LanSyncService.filterArchivedRows` (dipanggil di
   `approveSync`) membuang baris append-only ber-`created_at` di tahun
   `<= last_archive_year`, termasuk child rows yatim (jaga FK). Metode
   dipilih user dari 3 opsi ("filter di host" — opsi watermark-ACK ditolak
   karena besar, masih kandidat jangka panjang, lihat bawah).
2. **B2 (Tinggi)** — dropdown "Kembalikan via" di sheet retur di-key `id`
   metode (bukan `type`) — dua metode setipe (2 rekening bank) dulu bikin
   assertion dropdown gagal, retur nota lunas terkunci.
3. **B3** — import CSV ulang meng-UPDATE produk lama (match barcode → SKU →
   nama+satuan, pilihan user "Update produk lama"), bukan duplikasi +
   pencurian barcode. Hasil import kini punya hitungan "updated".
4. **B7** — "Tambah Bayar" lewat method DB baru `addPaymentToTransaction`:
   `paid` dicatat PENUH (boleh > total, pilihan user "Catat paid penuh"),
   kembalian selamat dari `_reconcileTransactionTotals` (dulu tertimpa 0).
5. **B4** — `resolvePrice` cabang harga-grup ambil HPP dari tier (dulu 0 →
   laba palsu). Catatan: fitur harga grup sendiri masih TIDAK terhubung ke
   UI mana pun (tidak ada UI buat grup; `ItemEntrySheet.customerGroupId`
   sudah dihapus karena tak pernah diisi).
6. **B5** — `databaseProvider` kini `select(storeKey)` — ganti nama toko
   tidak lagi menutup-buka DB di tengah sesi.
7. **B6** — price sync (port 8626, katalog memuat HPP): lockout brute-force
   per-IP (5 gagal → 5 menit) + constant-time compare, meniru LanSync.
8. **B8-B14 (Rendah)** — search kasir per-cartId (family+autoDispose);
   toast scan pakai qty efektif; void retur memulihkan poin loyalty;
   pesan clock-skew sync berbahasa Indonesia; cache nonce dibatasi 5000;
   parser CSV dukung newline-dalam-kutip + sanitize tidak memangkas nama
   berawalan `-` yang sah; backfill startup pindah ke setelah `runApp`.

### Cleanup kode mati (commit `81f1af6`)
Dihapus: `countTodayTransactions`; `CartNotifier.removeItemByIndex/setNote/
overridePrice/qtyForProduct/qtyForUnit/itemCount`; `PrinterService.testPrint`;
`DbExportService.export()` (BPOS1 — jalur DECRYPT file lama TETAP ada);
param `iv` di `CryptoService.encryptText`; file `top_toast.dart`,
`placeholder_screen.dart`, `product_with_units.dart`; param
`ItemEntrySheet.customerGroupId`. Izin `input_pengeluaran` &
`input_pembelian` DISEMBUNYIKAN dari layar Izin Kasir (key tetap di DB &
tersinkron — tinggal munculkan lagi saat fiturnya dibangun).

### Lingkungan build (catatan sesi remote)
Flutter SDK tidak terpasang di container remote — sesi ini memasang manual
Flutter 3.24.5 (versi sama dengan CI di `.github/workflows`) ke `/tmp/flutter`
untuk menjalankan analyze + test. Kalau sesi berikutnya juga remote, ulangi:
unduh tar dari storage.googleapis.com, `git config --global --add
safe.directory /tmp/flutter`, `flutter pub get`.

## Temuan yang SENGAJA Belum Diperbaiki (kandidat diskusi)
- **Multi-satuan + varian bercampur**: invariant `storedQty induk = base +
  Σvarian` ambigu bila satu produk punya ≥2 baris satuan non-varian di
  keranjang. Butuh refactor atribusi varian per-baris — jangan disentuh
  tanpa keputusan user.
- Tombol minus di kartu produk (`_decrementProduct`) selalu mengurangi baris
  satuan PERTAMA bila produk ada di keranjang dengan >1 satuan.
- **Upload sync klien→host masih full-dump** (sengaja — antrian approval
  host hanya di memori; watermark upload butuh mekanisme ACK approve dari
  host, pekerjaan tersendiri). B1 fix membuat full-dump ini aman terhadap
  tutup buku, tapi payload tetap membesar seiring data klien.
- Fitur "hantu" yang tabel-nya ada tapi tanpa UI: `expenses` (paling layak
  dibangun — lihat saran fitur), `suppliers/purchases/purchase_items`,
  `customer_groups/customer_group_prices` (butuh UI kelola grup + wiring
  `customerGroupId` ke alur kasir bila mau dihidupkan; HPP-nya sudah benar).

## Saran Fitur dari Audit (menunggu keputusan user, urut prioritas)
1. Pencatatan pengeluaran (tabel/sync/izin sudah ada → laba bersih di laporan).
2. Tukar poin loyalty di layar bayar (tipe ledger `redeem` sudah disiapkan).
3. Pilih metode bayar saat pelunasan hutang (kini hardcode 'tunai' di
   Tambah Bayar & pelunasan gabung nota).
4. Peringatan stok menipis (ambang minimum per satuan).
5. Layar "Buku Hutang" terpusat (siapa berhutang, umur hutang, aksi lunasi).
6. Backup otomatis terjadwal + pengingat "backup terakhir X hari lalu".
7. Edit/hapus metode pembayaran (kini hanya tambah + on/off).
8. Rekap tutup kasir harian (uang seharusnya di laci vs fisik).

## Keputusan Penting yang Masih Berlaku
- Cart meta tab = shrink-wrap kiri, **bukan** full-width.
- Animasi scan yang dipilih = **Opsi E** (garis pulse hijau), dari 8 opsi.
- Referensi proyek tinggal di `docs/reference/` (jangan hapus).
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.
- Metode fix audit dipilih user via poll: B1 filter-di-host, B3 update
  produk lama, B7 catat paid penuh.

## Menggantung / Kandidat Berikutnya
- Saran fitur di atas menunggu keputusan user.
- Proposal "Barokah Order" masih menunggu keputusan user
  (`docs/PROPOSAL_PERTIMBANGAN_BAROKAH_ORDER.md`).
- Versi masih `2.1.0+2`; belum ada PR ke `main` (branch audit:
  `claude/code-audit-features-in6is5`).

## Preferensi User
- Untuk fitur bervisual (mis. animasi), **usulkan beberapa opsi desain dulu**
  sebelum implementasi.
- Bahasa komunikasi & teks UI: Indonesia.
- Hati-hati agar perubahan tidak merusak logika/alur aplikasi yang sudah ada.
- Untuk perbaikan bug: laporkan dulu dengan contoh kasus + severity, tawarkan
  metode fix via poll, baru eksekusi sesuai konfirmasi.
