# Hand-off / Context Card

**Snapshot bergulir** keadaan proyek terkini untuk kesinambungan antar-sesi.
Ini BUKAN log — **timpa/rewrite** isinya tiap akhir sesi agar selalu mencerminkan
keadaan sekarang. Histori panjang ada di [CHANGELOG.md](../CHANGELOG.md).

_Terakhir diperbarui: 8 Juli 2026 (Fase 2 fitur eksperimental Katalog Pesanan — parser & Tempel Pesanan)._

---

## Di Mana Kita Sekarang

Fitur eksperimental **Katalog Pesanan** (branch `claude/order-html-eksperimental`)
sekarang lengkap dua fase, menutup alur ujung-ke-ujung: generate HTML →
kirim WA manual → pelanggan pilih barang → kasir tempel balik ke keranjang.

### Fase 1 — generator HTML (commit `e422639`, `dc9c3ef`)
- `lib/core/services/order_page_service.dart` — `OrderPageService.
  generateHtml({db, storeName, storeWhatsapp})` → satu file HTML
  self-contained (CSS+JS inline, tanpa CDN/font eksternal, tanpa hosting —
  keputusan eksplisit user: kirim manual via WA). Pelanggan pilih barang
  (termasuk varian, UX arrow-tap + auto-expand saat search cocok) lalu tekan
  "Kirim via WhatsApp" — teks pesanan berformat manusia-bisa-baca + baris
  kode mesin `#PSN:<productUnitId>=<qty>;...` di akhir.
- `lib/features/pengaturan/order_share_screen.dart` — layar
  `/pengaturan/katalog-pesanan` (badge "Eksperimental", owner-only), generate
  → `Share.shareXFiles` (pola sama seperti share struk/katalog).
- 6 test (`test/order_page_service_test.dart`) menemukan & membuktikan 2 bug
  nyata sebelum dianggap selesai: varian bocor jadi baris induk terpisah
  (`searchProducts()` tidak menyaring varian, beda dari `watchProducts()`),
  dan XSS lewat data JSON yang belum di-escape `"</"` → `"<\/"` di dalam
  `<script>`.

### Fase 2 — parser & UI Tempel Pesanan (commit `ef9ab12`)
- `lib/core/services/order_parser_service.dart` — `OrderParserService.
  parse({db, text})` → `ParsedOrder`. Regex-extract baris `#PSN:...`, lookup
  tiap `productUnitId` ke DB, **resolve harga LIVE via `PriceService`**
  (bukan angka di teks — katalog terkirim bisa sudah basi beberapa hari),
  dedup unitId dobel (gabung qty, bukan baris ganda), barang yang sudah
  dihapus/dinonaktifkan masuk `ParsedOrder.notFound` tanpa menggagalkan
  baris valid lain. Ikut extract `Nama:`/`HP:`/`Catatan:` (nilai `-` atau
  kosong dianggap null).
- `lib/features/kasir/widgets/paste_order_sheet.dart` — `PasteOrderSheet`
  (bottom sheet): tempel teks → preview daftar item + notFound → isi
  keranjang. `_ensureParentInCart()` sengaja DUPLIKAT self-contained (bukan
  reuse method private `kasir_screen.dart`) — sesuai keputusan user sesi
  sebelumnya bahwa kasir utama TIDAK boleh disentuh oleh fitur eksperimental
  ini, hanya ditambah tombol baru.
- `lib/features/kasir/kasir_screen.dart` — perubahan ADDITIF saja: tombol
  baru "Tempel Pesanan" (`Icons.content_paste_go_rounded`) di topbar,
  hanya tampil di mode kasir normal (bukan mode katalog/tambah-belanjaan).
- 6 test parser (Tier 1 DB, `test/order_parser_service_test.dart`) + 1 test
  layout (Tier 2 widget, `test/kasir_topbar_layout_test.dart`, render
  `KasirScreen` di lebar 360dp) membuktikan tombol baru TIDAK memicu
  `RenderFlex` overflow — CLAUDE.md mencatat topbar kasir historis rawan
  kasus ini. Kedua kelas regresi (dedup dimatikan, lebar label dipaksa 200)
  diverifikasi lewat revert-sementara: tanpa fix, test gagal dengan pesan
  yang sesuai; dengan fix, hijau lagi.

`flutter analyze` bersih, **119 test hijau** (112 lama + 7 baru Fase 2).

### Yang SENGAJA belum dibangun (deferred, bukan lupa)
- Hosting "link hidup" (GitHub Pages dkk) untuk Katalog Pesanan — user pilih
  TIDAK sekarang (kirim manual via WA). Opsi & tradeoff sudah didiskusikan
  kalau nanti mau dipertimbangkan ulang.
- UX varian (arrow-tap + auto-expand-on-search) hanya ada di HTML generated,
  belum diseragamkan ke kasir utama (yang masih pakai long-press). Perubahan
  terpisah, perlu dikonfirmasi ulang user kalau mau diselaraskan.
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user.

## Ringkasan Sesi Audit Sebelumnya (masih berlaku, tidak diulang detail)
14 bug hasil audit kode menyeluruh sudah diperbaiki & dirilis sebagai
v2.1.1+3 (lihat CHANGELOG untuk daftar commit `7d1fc6f`, `81f1af6`,
`c1bafd7`, `b6fefbe`). PR #2 sudah di-merge ke `main`. Build APK v2.1.1+3
sukses (dev pre-release di GitHub Releases).

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
  `Mockup.zip` & `Contoh_Dataset.rar` yang masih ada & dipakai aktif.
- Ekspor pakai `FilePicker.saveFile`, bukan `Printing.sharePdf`.
- Katalog Pesanan (eksperimental): tanpa hosting, kasir utama tidak
  disentuh (hanya tombol baru ditambah), Fase 1 (HTML) + Fase 2 (parser +
  Tempel Pesanan) sudah selesai keduanya.

## Menggantung / Kandidat Berikutnya
- Saran fitur audit di atas menunggu keputusan user.
- Belum ada PR untuk branch `claude/order-html-eksperimental` — menunggu
  instruksi user (buka PR / hal lain).
- Kalau Katalog Pesanan terbukti kepakai di lapangan: pertimbangkan lagi
  opsi hosting "link hidup" atau penyeragaman UX varian ke kasir utama
  (keduanya sengaja ditunda, lihat di atas).

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
