# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 10 Juli 2026 (eksekusi 5 item PLAN.md: fix dropdown
pelanggan, fix dedup importer CSV, optimasi performa HTML Katalog Pesanan,
urutan qty/satuan struk, reorder Harga Lain — commit `6f1fbc4`..`b949268`)._

---

## Di Mana Kita Sekarang

### Sesi terbaru — audit dataset toko lama → `PLAN.md` → eksekusi 5 item
Sesi ini dimulai dari pertanyaan user soal update data berkala dari dataset
toko lama (`docs/reference/Contoh_Dataset.rar`, `Products.csv`), berkembang
jadi audit besar (bug dropdown pelanggan, bug importer CSV, bug rasio
multi-satuan hilang saat import, dll). Semua temuan dimasukkan ke
[PLAN.md](../PLAN.md) (aturan proses ada di CLAUDE.md §Perencanaan — SETIAP
rencana kerja masuk situ, dihapus begitu selesai dieksekusi). Lalu user minta
eksekusi 5 item yang sudah "siap dikerjakan sekarang" sekaligus:

1. **Fix dropdown pelanggan** (`ea6e952`) — hapus
   `.take(5)`/`.take(8)` di `payment_screen.dart` &
   `cart_meta_pickers.dart`, ganti `ListView.builder` lazy dengan tinggi
   terkunci. Ini juga menyelesaikan bug "Mbak Ima tidak ketemu saat ketik
   ima" (root cause: dipotong sebelum sempat scroll).
2. **Fix dedup importer CSV** (`3bff1b6`) — kunci dedup lama cuma
   `nama|unitTypeId`, sekarang prioritas `barcode` → `kode_produk` →
   fallback nama+satuan. Bug nyata: 2 baris "Sedap Goreng" satuan Dos
   dengan barcode beda di `Products.csv` user, salah satu dulu terbuang
   diam-diam.
3. **Optimasi performa HTML Katalog Pesanan** (`c1a9efe`) — debounce
   search ~120ms, update stepper per-baris (bukan `renderList()` penuh),
   `renderCartSheet()` cuma jalan kalau sheet terbuka, `DocumentFragment`
   untuk batch render baris. **Diverifikasi pakai Chromium headless
   (Playwright)** — bukan cuma `flutter test` (JS tidak tereksekusi di
   situ). Skrip verifikasi: buat HTML sample 300 produk, load via
   `playwright.chromium.launch({executablePath: '/opt/pw-browsers/
   chromium-1194/chrome-linux/chrome'})`, cek debounce timing +
   sinkronisasi qty antara list & cart sheet.
4. **Urutan qty/satuan struk in-app** (`6f1fbc4`) — `"pcs 1 x"` →
   `"1 pcs x"`, menyamakan dengan versi cetak/share yang sudah benar.
5. **Reorder "Harga Lain" via drag-handle** (`b949268`) — kolom baru
   `alt_prices.sortOrder` (`schemaVersion` 9→10), `getAltPrices()` ganti
   urut ke `sortOrder ASC`, UI `ReorderableListView` + drag-handle di
   `produk_form_screen.dart`. **Guard penting di migrasi:**
   `if (from < 10 && from >= 8)` sebelum `addColumn(altPrices,
   altPrices.sortOrder)` — kalau upgrade LANGSUNG dari versi < 8,
   `createTable(altPrices)` di migrasi 7→8 SUDAH memakai skema Dart
   TERKINI (otomatis termasuk `sortOrder`), jadi `addColumn` lagi akan
   crash "duplicate column name". Ditemukan lewat full test suite (bukan
   cuma test migrasi baru sendiri) — jangan lupa jalankan SEMUA test
   setelah ubah `schemaVersion`, bukan cuma test yang baru ditulis.

**Item lain di PLAN.md (3, 4, 5, 8) BELUM dieksekusi** — lihat file itu untuk
detail lengkap & alasan masing-masing masih menggantung (butuh data final
dari user / keputusan desain / dependency ke item lain).

Test baru sesi ini (semua lolos revert-verify): `test/csv_import_dedup_test.dart`
(Tier 1), `test/migration_v10_test.dart` (Tier 1, migrasi + ordering),
`test/produk_form_reorder_alt_price_test.dart` (Tier 2 widget, simulasi drag
gesture asli via `tester.startGesture`+`moveBy` bertahap — drag satu
lompatan besar TIDAK cukup dikenali `ReorderableListView`, butuh beberapa
event `pointermove` kecil). Test migrasi lama (`v7`, `v8`, `v9`) diperbarui
fixture-nya (tambah tabel `alt_prices` minimal, assert versi akhir 10) supaya
tetap valid setelah `schemaVersion` naik. **`flutter analyze` bersih, semua
141 test hijau.**

**Catatan lingkungan sesi ini:** binary `flutter` ada di `/tmp/flutter/bin/flutter`
di environment ini (BUKAN `/opt/flutter/bin` seperti disebut CLAUDE.md — itu
mungkin beda per environment/container, cek `which flutter`/`find` dulu kalau
command CLAUDE.md gagal). Playwright global ada di `/opt/node22/lib/node_modules`
(`NODE_PATH` perlu di-set manual), Chromium executable di
`/opt/pw-browsers/chromium-1194/chrome-linux/chrome` (bukan `chromium/chrome-linux/chrome`
seperti disebut di system prompt — versi folder berubah, cek `find /opt/pw-browsers -iname "*chrome*"`
kalau path itu gagal).

### Sesi sebelumnya (commit `50752cd`) — poles layout topbar kasir
Lihat CHANGELOG untuk detail commit. Ringkasan: lebar collapsed field cari
dihitung presisi dari lebar tombol nyata (bukan hardcode), tinggi Stack
topbar diperbesar supaya label 2 baris tidak kepepet divider, tap
"+"/badan-produk saat search aktif tidak lagi collapse field.

### Fitur eksperimental Katalog Pesanan (branch `claude/order-html-eksperimental`)
Lengkap dua fase (generate HTML → kirim WA → pelanggan pilih barang → kasir
tempel balik ke keranjang), ditambah optimasi performa sesi ini (lihat di
atas). Detail arsitektur lengkap ada di `lib/core/services/order_page_service.dart`
(generator) & `lib/core/services/order_parser_service.dart` (parser).

### Yang SENGAJA belum dibangun (deferred, bukan lupa)
- Hosting "link hidup" (GitHub Pages dkk) untuk Katalog Pesanan — user pilih
  TIDAK sekarang (kirim manual via WA).
- UX varian (arrow-tap + auto-expand-on-search) hanya ada di HTML generated,
  belum diseragamkan ke kasir utama (yang masih pakai long-press).
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user.
- Item 8 PLAN.md (bawa UI pilih-harga ItemEntrySheet ke HTML) — masih
  diskusi kelayakan, belum ada keputusan scope.

## Ringkasan Sesi Audit Sebelumnya (masih berlaku, tidak diulang detail)
14 bug hasil audit kode menyeluruh sudah diperbaiki & dirilis sebagai
v2.1.1+3 (lihat CHANGELOG). PR #2 sudah di-merge ke `main`.

## Temuan yang SENGAJA Belum Diperbaiki (kandidat diskusi, dari audit)
- **Multi-satuan + varian bercampur**: invariant `storedQty induk = base +
  Σvarian` ambigu bila satu produk punya ≥2 baris satuan non-varian di
  keranjang. Butuh refactor atribusi varian per-baris — jangan disentuh
  tanpa keputusan user.
- Tombol minus di kartu produk (`_decrementProduct`) selalu mengurangi baris
  satuan PERTAMA bila produk ada di keranjang dengan >1 satuan.
- **Upload sync klien→host masih full-dump** (sengaja — antrian approval
  host hanya di memori; watermark upload butuh mekanisme ACK approve dari
  host, pekerjaan tersendiri).
- Fitur "hantu" yang tabel-nya ada tapi tanpa UI: `expenses` (paling layak
  dibangun — lihat saran fitur), `suppliers/purchases/purchase_items`,
  `customer_groups/customer_group_prices`.

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
- Referensi proyek tinggal di `docs/reference/` (jangan hapus) — termasuk
  `Mockup.zip` & `Contoh_Dataset.rar` yang masih ada & dipakai aktif untuk
  perencanaan migrasi data (lihat PLAN.md Item 3-5).
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.
- Katalog Pesanan (eksperimental): tanpa hosting, kasir utama tidak
  disentuh (hanya tombol baru ditambah).
- Harga Lain (`alt_prices`) TIDAK pernah dipilih otomatis oleh
  `PriceService.resolvePrice` — murni manual/tap. Urutan tampilnya sekarang
  bisa diatur user via drag-handle di form Produk (`sortOrder` kolom).
- Claude TIDAK punya akses berkelanjutan ke database toko user (offline-first,
  terenkripsi SQLCipher) — alur migrasi data dari dataset lama selalu:
  user kirim data mentah → Claude olah format → user import sendiri lewat
  fitur di app. Lihat "Konteks" di PLAN.md.

## Menggantung / Kandidat Berikutnya
- **PLAN.md Item 3** (konversi format `Products.csv` + fix rasio multi-satuan
  hilang, 31% katalog terdampak) — prioritas TINGGI, harus selesai SEBELUM
  data produk diimpor ke DB live. Menunggu user siap kirim/konfirmasi data
  final.
- **PLAN.md Item 4** (importer pelanggan + poin loyalty, fitur baru) —
  menunggu user jawab 3 pertanyaan desain (overwrite vs delta poin, kunci
  pencocokan, penanganan nama kembar).
- **PLAN.md Item 5** (import riwayat transaksi dari dataset lama) — setelah
  Item 3 selesai, dan setelah user konfirmasi cakupan tanggal file
  `Transaksi ...xlsx` yang tersedia.
- **PLAN.md Item 8** (bawa UI pilih-harga ke HTML Katalog) — menunggu
  keputusan user soal trade-off kompleksitas vs manfaat.
- Saran fitur audit di atas menunggu keputusan user.
- Belum ada PR untuk branch `claude/order-html-eksperimental`.

## Preferensi User
- Untuk fitur bervisual (mis. animasi), **usulkan beberapa opsi desain dulu**
  sebelum implementasi.
- Bahasa komunikasi & teks UI: Indonesia.
- Hati-hati agar perubahan tidak merusak logika/alur aplikasi yang sudah ada.
- Untuk perbaikan bug: laporkan dulu dengan contoh kasus + severity, tawarkan
  metode fix via poll, baru eksekusi sesuai konfirmasi.
- Untuk fitur baru berisiko/besar: diskusikan cakupan dulu (boleh
  dipersempit dari proposal awal), baru eksekusi setelah "eksekusi semua"
  atau konfirmasi serupa.
- Untuk rencana kerja yang didiskusikan tapi belum dieksekusi ("jangan
  coding dulu"): masukkan ke PLAN.md secara komprehensif, jangan cuma
  disimpan di riwayat chat.
